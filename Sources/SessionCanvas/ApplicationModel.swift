import AppKit
import SwiftUI
import CanvasCore

@MainActor
final class ApplicationModel: ObservableObject {
    @Published var workspace = Workspace()
    @Published var acknowledgments: [String: Set<String>] = [:]
    @Published var mode: SourceMode
    @Published var connectionStatus = "Not connected"
    @Published var connected = false
    @Published var hasLiveState = false
    @Published var isRefreshing = false
    @Published var selectedSessionID: String?
    @Published var search = "" { didSet { revealedCreationID = nil; closeHiddenSelection() } }
    @Published private(set) var visibility: CanvasVisibility = { var value = CanvasVisibility(); value.hiddenStates = []; return value }()
    @Published private(set) var geometryGeneration = 0
    @Published private(set) var hasUnsavedLayout = false
    private var storageReady = true
    @Published private(set) var activityNow = Date()
    @Published var history: [HistoryEntry] = []
    @Published var nextHistoryCursor: String?
    @Published var isLoadingHistory = false
    @Published var historyError: String?
    @Published var errorMessage: String?
    @Published var settings: ConnectionSettings
    @Published var showsSettings = false
    @Published var sidebarVisibility: NavigationSplitViewVisibility = .all
    @Published var creation: CreationContext?
    @Published var pendingSessions: Set<String> = []
    @Published var fitRequest = 0
    @Published var focusedProjectID: String?
    @Published var focusedSessionID: String?
    @Published private(set) var revealedCreationID: String?
    @Published var focusRequest = 0
    @Published var isCreating = false
    @Published private(set) var creationError: String?
    private var source: SessionSource?
    private var database: CanvasDatabase?
    private var refreshTask: Task<Void, Never>?
    private var changeTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var historyLoadToken = UUID()
    private var generation = UUID()
    private var saveTask: Task<Void, Never>?
    private var activityTask: Task<Void, Never>?
    private let nativeOpener: ((URL) -> Void)?
    private let observedSessionIDs: Set<String>?

    struct CreationContext: Identifiable {
        let id = UUID()
        var location: Point
        var projectID: String?
        var layer: CanvasLayer = .active
    }

    init(demo: Bool, storagePath: String? = nil, nativeOpener: ((URL) -> Void)? = nil, observedSessionIDs: Set<String>? = nil) {
        self.nativeOpener = nativeOpener
        self.observedSessionIDs = observedSessionIDs
        mode = demo ? .demo : .history
        settings = UserDefaults.standard.data(forKey: "connectionSettings").flatMap { try? JSONDecoder().decode(ConnectionSettings.self, from: $0) } ?? .defaults
        activityTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { return }
                self.updateActivityTime()
            }
        }
        do {
            let path: String
            if let storagePath { path = storagePath }
            else {
                let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Session Canvas", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                path = folder.appendingPathComponent("canvas.sqlite").path
            }
            database = try CanvasDatabase(path: path)
        } catch { errorMessage = "Canvas storage is unavailable. Changes cannot be saved. \(error.localizedDescription)" }
    }
    var sourceID: String { source?.sourceID ?? "disconnected" }
    func toggleSidebar() { sidebarVisibility = sidebarVisibility == .detailOnly ? .all : .detailOnly }
    func toggleFullScreen() { NSApp.keyWindow?.toggleFullScreen(nil) }
    var canCreate: Bool { source?.canCreate == true && connected }
    var creationUnavailableReason: String { connected ? source?.creationUnavailableReason ?? "Session creation is unavailable." : "Connect to Codex to create a session." }
    func creationDirectory(projectID: String) -> String? { source?.creationDirectory(projectID: projectID) }
    var canAssignProject: Bool { source?.canAssignProject == true && connected }
    var selectedSession: Session? { workspace.sessions.first { $0.id == selectedSessionID } }
    func state(_ session: Session) -> NoteState { session.state(acknowledged: acknowledgments[session.id] ?? []) }
    var selectedLayer: CanvasLayer { workspace.selectedLayer }
    func layer(_ session: Session) -> CanvasLayer {
        CanvasLayer.classify(session, acknowledged: acknowledgments[session.id] ?? [], timeout: visibility.idleTimeout, now: activityNow)
    }
    var layerCounts: [CanvasLayer: Int] { Dictionary(grouping: workspace.sessions, by: layer).mapValues(\.count) }
    func selectLayer(_ layer: CanvasLayer, revealingCreation: Bool = false) {
        guard layer != selectedLayer else { return }
        var next = workspace
        next.reconcileLayers(acknowledgments: acknowledgments, now: activityNow, legacyVisibility: visibility, selecting: layer)
        if !saveUserLayout(next) {
            guard revealingCreation else { return }
            workspace = next; visibility = next.selectedVisibility; geometryGeneration += 1; hasUnsavedLayout = true
        }
        revealedCreationID = nil; focusedProjectID = nil; focusedSessionID = nil
        closeHiddenSelection()
    }
    func synchronizeLayers() {
        let before = workspace
        workspace.reconcileLayers(acknowledgments: acknowledgments, now: activityNow, legacyVisibility: visibility)
        visibility = workspace.selectedVisibility
        if before.placements != workspace.placements || before.regions != workspace.regions ||
            before.layerState?.assignments != workspace.layerState?.assignments || before.layerState?.homes != workspace.layerState?.homes {
            geometryGeneration += 1
        }
    }
    var visibleSessions: [Session] {
        workspace.sessions.filter { session in
            layer(session) == selectedLayer && (session.id == revealedCreationID || matchesVisibility(session))
        }
    }
    private func matchesVisibility(_ session: Session) -> Bool {
        matchesSearch(session) && !visibility.hiddenStates.contains(state(session)) &&
            !visibility.hiddenProjectIDs.contains(session.projectID ?? "") && layer(session) == selectedLayer
    }
    func updateActivityTime(now: Date = Date()) { activityNow = now; persist(); closeHiddenSelection() }
    func activityLabel(_ session: Session) -> String { ActivityTime.label(session.updatedAt, now: activityNow) }
    var creationIsOutsideFilters: Bool {
        guard let session = workspace.sessions.first(where: { $0.id == revealedCreationID }) else { return false }
        return !matchesVisibility(session)
    }
    func applyFiltersToCreation() { revealedCreationID = nil; closeHiddenSelection() }
    var visibleProjects: [Project] {
        let ids = Set(visibleSessions.compactMap(\.projectID))
        return workspace.projects.filter { ids.contains($0.id) }
    }
    var visibleRegions: [String: Rect] {
        let ids = Set(visibleProjects.map(\.id))
        return workspace.regions.filter { ids.contains($0.key) }
    }
    var hiddenProjects: [Project] { workspace.projects.filter { visibility.hiddenProjectIDs.contains($0.id) } }
    var stateCounts: [NoteState: Int] {
        Dictionary(grouping: workspace.sessions.filter { layer($0) == selectedLayer && ($0.id == revealedCreationID || matchesSearch($0) && !visibility.hiddenProjectIDs.contains($0.projectID ?? "")) }, by: state).mapValues(\.count)
    }
    func visibleProject(at point: Point) -> String? {
        visibleProjects.first { workspace.regions[$0.id]?.contains(point) == true }?.id
    }
    private func matchesSearch(_ session: Session) -> Bool { search.isEmpty || session.title.localizedCaseInsensitiveContains(search) }
    func setStateVisible(_ state: NoteState, _ visible: Bool) {
        var next = visibility
        if visible { next.hiddenStates.remove(state) } else { next.hiddenStates.insert(state) }
        setVisibility(next)
    }
    func setProjectVisible(_ id: String, _ visible: Bool) {
        var next = visibility
        if visible { next.hiddenProjectIDs.remove(id) } else { next.hiddenProjectIDs.insert(id) }
        setVisibility(next)
    }
    func showAllAttentionStates() {
        var next = visibility; next.hiddenStates = []; setVisibility(next)
    }
    func showAllProjects() {
        var next = visibility; next.hiddenProjectIDs = []; setVisibility(next)
    }
    func setIdleTimeout(_ timeout: IdleTimeout) { var next = visibility; next.idleTimeout = timeout; setVisibility(next) }
    func showAllSessions() { search = ""; var next = visibility; next.hiddenStates = []; next.hiddenProjectIDs = []; setVisibility(next) }
    var canRearrange: Bool { connected && !isRefreshing && !isCreating && pendingSessions.isEmpty && database != nil && !visibleSessions.isEmpty }
    func rearrange() {
        guard canRearrange, let database else { return }
        do {
            synchronizeLayers()
            let geometry = try CanvasRearranger.arrange(workspace.geometryProjection, visibleSessionIDs: Set(visibleSessions.map(\.id)), acknowledgments: acknowledgments)
            var next = workspace; next.installGeometry(geometry)
            try database.save(next, source: sourceID)
            workspace = next; geometryGeneration += 1; hasUnsavedLayout = false
        } catch { errorMessage = "Couldn’t rearrange sessions. \(error.localizedDescription)" }
    }
    func canArchive(_ session: Session) -> Bool {
        archiveEligible(session) && !pendingSessions.contains(session.id) && !isRefreshing
    }
    private func archiveEligible(_ session: Session) -> Bool { connected && source?.canArchive == true && (session.isArchived || state(session) == .idle && session.unknownReason == nil) }
    func toggleArchive(_ id: String) async {
        guard let source, let session = workspace.sessions.first(where: { $0.id == id }), canArchive(session) else { return }
        let token = generation
        pendingSessions.insert(id)
        defer { if token == generation { pendingSessions.remove(id) } }
        await refresh()
        guard token == generation, let current = workspace.sessions.first(where: { $0.id == id }),
              current.revision == session.revision, current.isArchived == session.isArchived, archiveEligible(current) else { return }
        do {
            try await source.setArchived(sessionID: id, archived: !session.isArchived)
            guard token == generation else { return }
            if let i = workspace.sessions.firstIndex(where: { $0.id == id }) { workspace.sessions[i].archived = !session.isArchived }
            persist(); closeHiddenSelection()
            await refresh()
        } catch { if token == generation { errorMessage = "Archive change failed. \(error.localizedDescription)" } }
    }
    private func setVisibility(_ next: CanvasVisibility) {
        do {
            var value = workspace
            value.reconcileLayers(acknowledgments: acknowledgments, now: activityNow, legacyVisibility: visibility)
            value.setLayerVisibility(next)
            value.reconcileLayers(acknowledgments: acknowledgments, now: activityNow)
            if let source {
                guard let database, storageReady else { throw CanvasError.message("Canvas storage is unavailable. Reconnect to retry.") }
                try database.save(value, source: source.sourceID)
            }
            workspace = value; visibility = value.selectedVisibility; geometryGeneration += 1; hasUnsavedLayout = false
            revealedCreationID = nil
            closeHiddenSelection()
        } catch { errorMessage = "Visibility changes could not be saved. \(error.localizedDescription)" }
    }
    private func closeHiddenSelection() {
        guard let id = selectedSessionID, !visibleSessions.contains(where: { $0.id == id }) else { return }
        loadTask?.cancel()
        selectedSessionID = nil; history = []; nextHistoryCursor = nil; historyError = nil; isLoadingHistory = false
    }
    var unreviewedCount: Int {
        visibleSessions.filter { session in session.latestResult.map { !(acknowledgments[session.id] ?? []).contains($0.id) } ?? false }.count
    }
    var sourceExplanation: String {
        switch mode {
        case .demo: return "Demo data · changes stay in this workspace"
        case .history: return hasLiveState ? "Live desktop state and saved local sessions" : "Saved history · waiting for Codex desktop"
        case .shared: return "Shared runtime and saved local projects"
        }
    }

    func connect(mode newMode: SourceMode? = nil) async {
        persist()
        refreshTask?.cancel(); changeTask?.cancel(); changeTask = nil; loadTask?.cancel(); saveTask?.cancel()
        source?.close()
        generation = UUID()
        let token = generation
        if let newMode { mode = newMode }
        connected = false; hasLiveState = false; selectedSessionID = nil; history = []; historyError = nil
        revealedCreationID = nil; focusedSessionID = nil
        pendingSessions = []; isRefreshing = false; isLoadingHistory = false; isCreating = false
        connectionStatus = "Connecting…"
        let next: SessionSource
        if mode == .demo {
            let saved = try? database?.load(source: "demo-v1")
            next = DemoSource(restored: saved?.sessions ?? [])
        } else { next = CodexSource(mode: mode, settings: settings, observedSessionIDs: observedSessionIDs) }
        source = next
        let cachedSourceID = next.sourceID
        do {
            storageReady = false
            workspace = try database?.loadLayered(source: next.sourceID, now: activityNow) ?? Workspace()
            acknowledgments = try database?.acknowledgments(source: next.sourceID) ?? [:]
            visibility = workspace.selectedVisibility; storageReady = database != nil
            if mode != .demo {
                for i in workspace.sessions.indices { workspace.sessions[i].execution = .unknown }
            }
            next.onChange = { [weak self] in
                guard let self, self.generation == token else { return }
                guard self.changeTask == nil else { return }
                self.changeTask = Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    self.changeTask = nil
                    await self.refresh()
                }
            }
            next.onDisconnect = { [weak self] in
                guard let self, self.generation == token else { return }
                self.connected = false; self.hasLiveState = false; self.connectionStatus = "Disconnected"
                for i in self.workspace.sessions.indices { self.workspace.sessions[i].execution = .unknown }
                self.persist()
                self.closeHiddenSelection()
            }
            next.onSessionObservation = { [weak self] observation, baseline in
                guard let self, self.generation == token,
                      let index = self.workspace.sessions.firstIndex(where: { $0.id == observation.id }),
                      self.workspace.sessions[index].revision == baseline.revision,
                      self.workspace.sessions[index].latestResult?.id == baseline.latestResult?.id,
                      self.workspace.sessions[index].requests.isEmpty,
                      self.workspace.sessions[index].execution == .unknown || self.workspace.sessions[index].stateIsFromHistory else { return }
                self.applyHistoryObservation(observation, at: index)
                self.closeHiddenSelection(); self.persist()
            }
            try await next.connect()
            guard generation == token else { return }
            if next.sourceID != cachedSourceID {
                storageReady = false
                workspace = try database?.loadLayered(source: next.sourceID, now: activityNow) ?? Workspace()
                acknowledgments = try database?.acknowledgments(source: next.sourceID) ?? [:]
                visibility = workspace.selectedVisibility; storageReady = database != nil
                for i in workspace.sessions.indices { workspace.sessions[i].execution = .unknown }
            }
            next.restoreCachedResults(workspace.sessions)
            connected = true
            connectionStatus = next.connectionStatus; hasLiveState = next.hasLiveState
            await refresh()
            refreshTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(12))
                    guard !Task.isCancelled, let self, self.connected, self.generation == token else { return }
                    await self.refresh()
                }
            }
        } catch {
            guard generation == token else { return }
            connected = false; connectionStatus = "Connection unavailable"
            if !storageReady { hasUnsavedLayout = true }
            errorMessage = mode == .shared ? "No reachable shared Codex server. Select Codex desktop for local sessions, or configure the shared server's control socket. \(error.localizedDescription)" : error.localizedDescription
        }
    }
    func refresh() async {
        guard let source, connected, !isRefreshing else { return }
        isRefreshing = true
        let token = generation
        defer { if token == generation { isRefreshing = false } }
        do {
            let snapshot = try await source.snapshot()
            guard generation == token else { return }
            connectionStatus = source.connectionStatus; hasLiveState = source.hasLiveState
            let hadContent = !workspace.sessions.isEmpty
            let hadPlacements = !workspace.placements.isEmpty || workspace.layerState?.layouts.values.contains { !$0.placements.isEmpty } == true
            // Preserve cached notes when an inventory is incomplete or metadata-only discovery omits them.
            var merged = Dictionary(uniqueKeysWithValues: workspace.sessions.map { ($0.id, $0) })
            for session in snapshot.sessions {
                var updated = session
                if updated.latestResult == nil { updated.latestResult = merged[session.id]?.latestResult }
                if updated.archived == nil { updated.archived = merged[session.id]?.archived }
                merged[session.id] = updated
            }
            for id in source.removedSessionIDs { merged.removeValue(forKey: id) }
            for id in source.hiddenSessionIDs {
                merged.removeValue(forKey: id)
                workspace.placements.removeValue(forKey: id)
            }
            workspace.reconcile(sessions: merged.values.sorted { $0.updatedAt > $1.updatedAt }, projects: snapshot.projects)
            if mode == .demo && !hadPlacements {
                workspace.regions = ["canvas": Rect(0, 0, 540, 440), "research": Rect(610, 0, 540, 440)]
                for (id, point) in ["demo-native": Point(20, 68), "demo-state": Point(280, 68), "demo-access": Point(20, 246), "demo-options": Point(630, 68), "demo-docs": Point(890, 68), "demo-stopped": Point(0, 500)] {
                    workspace.placements[id] = Placement(point)
                }
            }
            closeHiddenSelection()
            persist()
            if !hadContent && mode == .demo { fitRequest += 1 }
        } catch {
            guard generation == token else { return }
            for i in workspace.sessions.indices { workspace.sessions[i].execution = .unknown }
            persist()
            closeHiddenSelection()
            errorMessage = "Refresh failed; existing notes have been retained. \(error.localizedDescription)"
        }
    }
    func openSession(_ id: String) {
        guard visibleSessions.contains(where: { $0.id == id }) else { return }
        selectedSessionID = id; history = []; nextHistoryCursor = nil; historyError = nil
        loadTask?.cancel()
        historyLoadToken = UUID(); isLoadingHistory = false
        loadTask = Task { await loadHistory(older: false) }
    }
    func loadHistory(older: Bool) async {
        guard let source, let id = selectedSessionID, !isLoadingHistory else { return }
        guard !older || nextHistoryCursor != nil else { return }
        isLoadingHistory = true; historyError = nil
        let token = generation, cursor = older ? nextHistoryCursor : nil, request = UUID()
        historyLoadToken = request
        let baseline = workspace.sessions.first { $0.id == id }
        defer { if generation == token && selectedSessionID == id && historyLoadToken == request { isLoadingHistory = false } }
        do {
            let page = try await source.history(sessionID: id, cursor: cursor)
            guard generation == token, selectedSessionID == id, historyLoadToken == request, !Task.isCancelled else { return }
            if older { history = page.entries + history }
            else { history = page.entries }
            nextHistoryCursor = page.nextCursor
            if !older, let i = workspace.sessions.firstIndex(where: { $0.id == id }), workspace.sessions[i] == baseline {
                if let observation = page.sessionObservation, observation.id == id {
                    applyHistoryObservation(observation, at: i)
                } else if let result = page.entries.compactMap(\.result).last {
                    workspace.sessions[i].latestResult = result
                }
                persist()
                closeHiddenSelection()
            }
        } catch { if generation == token && selectedSessionID == id && historyLoadToken == request { historyError = error.localizedDescription } }
    }
    private func applyHistoryObservation(_ observation: Session, at index: Int) {
        // Keep local geometry/membership/archive facts; current live work outranks saved history.
        if workspace.sessions[index].requests.isEmpty && (workspace.sessions[index].execution == .unknown || workspace.sessions[index].stateIsFromHistory) {
            workspace.sessions[index].execution = observation.execution
            workspace.sessions[index].requests = observation.requests
            workspace.sessions[index].savedState = observation.savedState
            workspace.sessions[index].unknownReason = observation.unknownReason
        }
        workspace.sessions[index].latestResult = observation.latestResult
        workspace.sessions[index].revision = observation.revision
        workspace.sessions[index].updatedAt = observation.updatedAt
    }
    func canAcknowledge(_ result: SessionResult, sessionID: String) -> Bool {
        guard selectedSessionID == sessionID, !isLoadingHistory,
              let session = workspace.sessions.first(where: { $0.id == sessionID }), state(session) == .finished else { return false }
        return history.contains(where: { $0.result?.id == result.id }) && !(acknowledgments[sessionID] ?? []).contains(result.id)
    }
    func acknowledge(_ result: SessionResult, sessionID: String) {
        guard canAcknowledge(result, sessionID: sessionID), let database else { return }
        do {
            try database.acknowledge(source: sourceID, session: sessionID, result: result.id)
            acknowledgments[sessionID, default: []].insert(result.id)
            persist()
            closeHiddenSelection()
        } catch { errorMessage = "Acknowledgment was not saved. Please retry. \(error.localizedDescription)" }
    }
    private var acknowledgeAllTargets: [(session: String, result: String)] {
        workspace.sessions.compactMap { session in
            guard state(session) == .finished, let result = session.latestResult else { return nil }
            return (session.id, result.id)
        }
    }
    var acknowledgeAllCount: Int { acknowledgeAllTargets.count }
    var canAcknowledgeAll: Bool { connected && !isRefreshing && database != nil && acknowledgeAllCount > 0 }
    func acknowledgeAll() {
        guard canAcknowledgeAll, let database else { return }
        let targets = acknowledgeAllTargets
        do {
            try database.acknowledge(source: sourceID, results: targets)
            var next = acknowledgments
            for target in targets { next[target.session, default: []].insert(target.result) }
            acknowledgments = next
            persist()
            closeHiddenSelection()
        } catch { errorMessage = "Acknowledgments were not saved. Please retry. \(error.localizedDescription)" }
    }
    func canMarkUnread(_ result: SessionResult, sessionID: String) -> Bool {
        selectedSessionID == sessionID && !isLoadingHistory && selectedSession != nil &&
            (history.contains(where: { $0.result?.id == result.id }) || selectedSession?.latestResult?.id == result.id) &&
            (acknowledgments[sessionID] ?? []).contains(result.id)
    }
    func markUnread(_ result: SessionResult, sessionID: String) {
        guard canMarkUnread(result, sessionID: sessionID), let database else { return }
        do {
            try database.removeAcknowledgment(source: sourceID, session: sessionID, result: result.id)
            acknowledgments[sessionID]?.remove(result.id)
            persist()
            closeHiddenSelection()
        } catch { errorMessage = "Result was not marked unread. Please retry. \(error.localizedDescription)" }
    }
    func moveNote(id: String, position: Point, expectedRevision: String, explicitProjectAction: Bool = false, explicitProjectID: String? = nil) {
        guard let session = workspace.sessions.first(where: { $0.id == id }), workspace.placements[id] != nil, !pendingSessions.contains(id), !isRefreshing else { return }
        guard session.revision == expectedRevision else { errorMessage = "The session changed during the drag. Its current placement was retained."; return }
        let proposed = Placement(position), target = explicitProjectAction ? explicitProjectID : workspace.project(at: proposed.center)
        if let target, visibleRegions[target] == nil, !explicitProjectAction {
            errorMessage = "That project is hidden. Show it before moving a session there."; return
        }
        if session.projectID == target { var next = workspace; next.placements[id] = proposed; _ = saveUserLayout(next); return }
        guard canAssignProject else {
            errorMessage = "Project moves are unavailable through this Codex connection. Move the chat in Codex; its project will sync here. The session stayed in its original project."
            objectWillChange.send(); return
        }
        guard let source else {
            errorMessage = "The session changed during the drag. Its current placement was retained."; return
        }
        pendingSessions.insert(id)
        let token = generation, moveLayer = selectedLayer, moveGeometry = geometryGeneration
        Task {
            defer { if generation == token { pendingSessions.remove(id) } }
            do {
                let confirmed = try await source.assign(sessionID: id, projectID: target, revision: expectedRevision)
                guard generation == token else { return }
                guard confirmed.id == id, confirmed.projectID == target,
                      let index = workspace.sessions.firstIndex(where: { $0.id == id }) else {
                    throw CanvasError.message("Codex did not confirm the requested project. Refresh before retrying.")
                }
                guard workspace.sessions[index].projectID == session.projectID || workspace.sessions[index].projectID == target else {
                    throw CanvasError.message("The session moved to another project while this request was pending. Its current membership will be refreshed.")
                }
                let keepPosition = selectedLayer == moveLayer && geometryGeneration == moveGeometry
                workspace.sessions[index].projectID = confirmed.projectID
                workspace.sessions[index].projectMembershipConfirmation = confirmed.projectMembershipConfirmation
                workspace.sessions[index].revision = confirmed.revision
                workspace.sessions[index].updatedAt = confirmed.updatedAt
                synchronizeLayers()
                if keepPosition, layer(workspace.sessions[index]) == moveLayer, workspace.project(at: proposed.center) == target {
                    workspace.placements[id] = proposed
                }
                persist()
            } catch {
                guard generation == token else { return }
                await refresh()
                guard generation == token else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
    func moveToProject(id: String, projectID: String?) {
        guard let session = workspace.sessions.first(where: { $0.id == id }), !pendingSessions.contains(id), !isRefreshing else { return }
        var copy = workspace.geometryProjection
        let placement = copy.vacantPlacement(projectID: projectID, excluding: id)
        // Source confirmation owns the membership change; speculative growth cannot alter saved geometry.
        if !canAssignProject { errorMessage = "Project moves are unavailable through this Codex connection. Move the chat in Codex; its project will sync here. The session stayed in its original project."; return }
        moveNote(id: id, position: placement.position, expectedRevision: session.revision, explicitProjectAction: true, explicitProjectID: projectID)
    }
    func editRegion(id: String, rect: Rect) {
        guard let original = workspace.regions[id] else { return }
        let delta = Point(rect.x - original.x, rect.y - original.y)
        var changes: [String: Placement] = [:]
        for session in workspace.geometrySessions where session.projectID == id {
            if let placement = workspace.placements[session.id] { changes[session.id] = Placement(placement.position + delta) }
        }
        guard workspace.validateRegion(id: id, rect: rect, memberPositions: changes) else {
            errorMessage = "Regions cannot overlap, enclose unrelated notes, or exclude their member notes."; return
        }
        var next = workspace; next.regions[id] = rect
        for (id, placement) in changes { next.placements[id] = placement }
        _ = saveUserLayout(next)
    }
    func beginCreation(at point: Point) {
        creationError = nil
        creation = CreationContext(location: point, projectID: visibleProject(at: point), layer: selectedLayer)
    }
    func create(title: String, prompt: String, projectID: String?, cwd: String) async {
        guard let source, canCreate, let context = creation, !isCreating else { return }
        if mode == .demo && prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        creationError = nil
        isCreating = true
        let token = generation
        defer { if generation == token { isCreating = false } }
        do {
            let result = try await source.create(title: title, prompt: prompt, projectID: projectID, cwd: cwd)
            let session = result.session
            guard generation == token else { return }
            workspace.reconcile(sessions: workspace.sessions.filter { $0.id != session.id } + [session], projects: workspace.projects)
            await refresh()
            guard generation == token else { return }
            let confirmed = workspace.sessions.first(where: { $0.id == session.id }) ?? session
            synchronizeLayers()
            let destination = layer(confirmed), crossedLayer = context.layer != destination
            if selectedLayer != destination { selectLayer(destination, revealingCreation: true) }
            workspace.placements[session.id] = workspace.vacantPlacement(projectID: confirmed.projectID, excluding: session.id, near: crossedLayer ? nil : context.location)
            creation = nil; persist()
            revealCreatedSession(session.id, focus: crossedLayer || confirmed.projectID != context.projectID)
            if mode != .demo && result.warning == nil { openInCodex(session) }
            if let warning = result.warning { errorMessage = warning }
        } catch { if generation == token { creationError = error.localizedDescription } }
    }
    func revealCreatedSession(_ id: String, focus: Bool = true) {
        guard let session = workspace.sessions.first(where: { $0.id == id }) else { return }
        let destination = layer(session)
        if selectedLayer != destination { selectLayer(destination, revealingCreation: true) }
        revealedCreationID = id
        focusedProjectID = nil; focusedSessionID = focus ? id : nil
        if focus { focusRequest += 1 }
        openSession(id)
    }
    func openInCodex(_ session: Session) {
        guard mode != .demo else { return }
        let escaped = session.id.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? session.id
        guard settings.nativeURLTemplate.contains("{id}"), let url = URL(string: settings.nativeURLTemplate.replacingOccurrences(of: "{id}", with: escaped)), url.scheme == "codex" else {
            errorMessage = "No application handles this Codex session URL. Check the URL template in Connection settings."; return
        }
        if let nativeOpener { nativeOpener(url); return }
        guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
            errorMessage = "No application handles this Codex session URL. Check the URL template in Connection settings."; return
        }
        NSWorkspace.shared.open(url, configuration: .init()) { _, error in
            if error != nil { Task { @MainActor in self.errorMessage = "Codex could not open this session. Check Connection settings and retry." } }
        }
    }
    func setViewport(_ viewport: Viewport) {
        workspace.viewport = viewport
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }; self?.persist()
        }
    }
    func persist() {
        synchronizeLayers()
        guard let source else { return }
        do {
            guard let database, storageReady else { throw CanvasError.message("Canvas storage is unavailable. Reconnect to retry.") }
            try database.save(workspace, source: source.sourceID)
            hasUnsavedLayout = false
        } catch { hasUnsavedLayout = true; errorMessage = "Changes are not saved. \(error.localizedDescription)" }
    }
    @discardableResult private func saveUserLayout(_ next: Workspace) -> Bool {
        do {
            var saved = next; saved.rememberLayerLayout()
            if let source {
                guard let database, storageReady else { throw CanvasError.message("Canvas storage is unavailable. Reconnect to retry.") }
                try database.save(saved, source: source.sourceID)
            }
            workspace = saved; visibility = saved.selectedVisibility; geometryGeneration += 1
            hasUnsavedLayout = false
            return true
        } catch { errorMessage = "Layout was not changed. \(error.localizedDescription)"; return false }
    }
    func retryLayoutSave() {
        if storageReady { persist() }
        else { Task { await connect() } }
    }
    func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "connectionSettings") }
    }
    func shutdown() {
        persist(); generation = UUID(); connected = false; hasLiveState = false
        changeTask?.cancel(); changeTask = nil; refreshTask?.cancel(); loadTask?.cancel(); saveTask?.cancel(); activityTask?.cancel()
        source?.close()
    }
}
