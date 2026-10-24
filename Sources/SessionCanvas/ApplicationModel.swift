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
    @Published private(set) var visibility = CanvasVisibility()
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
    private var generation = UUID()
    private var saveTask: Task<Void, Never>?
    private var activityTask: Task<Void, Never>?
    private let nativeOpener: ((URL) -> Void)?
    private let observedSessionIDs: Set<String>?

    struct CreationContext: Identifiable {
        let id = UUID()
        var location: Point
        var projectID: String?
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
    var visibleSessions: [Session] {
        workspace.sessions.filter { session in
            session.id == revealedCreationID || matchesVisibility(session)
        }
    }
    private func matchesVisibility(_ session: Session) -> Bool {
        matchesSearch(session) && !visibility.hiddenStates.contains(state(session)) &&
            !visibility.hiddenProjectIDs.contains(session.projectID ?? "") && matchesLifecycle(session)
    }
    private func matchesLifecycle(_ session: Session) -> Bool {
        visibility.includesLifecycle(session, acknowledged: acknowledgments[session.id] ?? [], now: activityNow)
    }
    func updateActivityTime(now: Date = Date()) { activityNow = now; closeHiddenSelection() }
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
        Dictionary(grouping: workspace.sessions.filter { $0.id == revealedCreationID || matchesSearch($0) && !visibility.hiddenProjectIDs.contains($0.projectID ?? "") && matchesLifecycle($0) }, by: state).mapValues(\.count)
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
    func setHideUnknown(_ hidden: Bool) { var next = visibility; next.hideUnknown = hidden; setVisibility(next) }
    func showAllSessions() { search = ""; var next = CanvasVisibility(); next.hiddenStates = []; setVisibility(next) }
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
            if let source {
                guard let database else { throw CanvasError.message("Canvas storage is unavailable.") }
                try database.saveVisibility(next, source: source.sourceID)
            }
            visibility = next
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
            workspace = try database?.load(source: next.sourceID) ?? Workspace()
            acknowledgments = try database?.acknowledgments(source: next.sourceID) ?? [:]
            visibility = try database?.visibility(source: next.sourceID) ?? CanvasVisibility()
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
                workspace = try database?.load(source: next.sourceID) ?? Workspace()
                acknowledgments = try database?.acknowledgments(source: next.sourceID) ?? [:]
                visibility = try database?.visibility(source: next.sourceID) ?? CanvasVisibility()
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
            let hadPlacements = !workspace.placements.isEmpty
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
            closeHiddenSelection()
            errorMessage = "Refresh failed; existing notes have been retained. \(error.localizedDescription)"
        }
    }
    func openSession(_ id: String) {
        guard visibleSessions.contains(where: { $0.id == id }) else { return }
        selectedSessionID = id; history = []; nextHistoryCursor = nil; historyError = nil
        loadTask?.cancel()
        loadTask = Task { await loadHistory(older: false) }
    }
    func loadHistory(older: Bool) async {
        guard let source, let id = selectedSessionID else { return }
        isLoadingHistory = true; historyError = nil
        let token = generation, cursor = older ? nextHistoryCursor : nil
        let baseline = workspace.sessions.first { $0.id == id }
        defer { if generation == token && selectedSessionID == id { isLoadingHistory = false } }
        do {
            let page = try await source.history(sessionID: id, cursor: cursor)
            guard generation == token, selectedSessionID == id, !Task.isCancelled else { return }
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
        } catch { if generation == token && selectedSessionID == id { historyError = error.localizedDescription } }
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
            closeHiddenSelection()
        } catch { errorMessage = "Result was not marked unread. Please retry. \(error.localizedDescription)" }
    }
    func moveNote(id: String, position: Point, expectedRevision: String) {
        guard let session = workspace.sessions.first(where: { $0.id == id }), let previous = workspace.placements[id], !pendingSessions.contains(id) else { return }
        guard session.revision == expectedRevision else { errorMessage = "The session changed during the drag. Its current placement was retained."; return }
        let proposed = Placement(position), target = workspace.project(at: proposed.center)
        if let target, visibleRegions[target] == nil {
            errorMessage = "That project is hidden. Show it before moving a session there."; return
        }
        if session.projectID == target { workspace.placements[id] = proposed; persist(); return }
        guard canAssignProject else {
            errorMessage = "Codex desktop project membership is not exposed by this connection. The note stayed in its original area. You can try project regions in Demo workspace."
            objectWillChange.send(); return
        }
        guard let source else {
            errorMessage = "The session changed during the drag. Its current placement was retained."; return
        }
        pendingSessions.insert(id)
        workspace.placements[id] = proposed
        let token = generation
        Task {
            defer { if generation == token { pendingSessions.remove(id) } }
            do {
                try await source.assign(sessionID: id, projectID: target, revision: expectedRevision)
                guard generation == token else { return }
                await refresh()
                guard generation == token else { return }
                workspace.placements[id] = proposed
                persist()
            } catch { if generation == token { workspace.placements[id] = previous; errorMessage = error.localizedDescription } }
        }
    }
    func moveToProject(id: String, projectID: String?) {
        guard let session = workspace.sessions.first(where: { $0.id == id }) else { return }
        var copy = workspace
        let placement = copy.vacantPlacement(projectID: projectID, excluding: id)
        workspace.regions = copy.regions
        moveNote(id: id, position: placement.position, expectedRevision: session.revision)
    }
    func editRegion(id: String, rect: Rect) {
        guard let original = workspace.regions[id] else { return }
        let delta = Point(rect.x - original.x, rect.y - original.y)
        var changes: [String: Placement] = [:]
        for session in workspace.sessions where session.projectID == id {
            if let placement = workspace.placements[session.id] { changes[session.id] = Placement(placement.position + delta) }
        }
        guard workspace.validateRegion(id: id, rect: rect, memberPositions: changes) else {
            errorMessage = "Regions cannot overlap, enclose unrelated notes, or exclude their member notes."; return
        }
        workspace.regions[id] = rect
        for (id, placement) in changes { workspace.placements[id] = placement }
        persist()
    }
    func beginCreation(at point: Point) {
        creationError = nil
        creation = CreationContext(location: point, projectID: visibleProject(at: point))
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
            workspace.placements[session.id] = workspace.vacantPlacement(projectID: confirmed.projectID, excluding: session.id, near: context.location)
            creation = nil; persist()
            revealCreatedSession(session.id, focus: confirmed.projectID != context.projectID)
            if mode != .demo && result.warning == nil { openInCodex(session) }
            if let warning = result.warning { errorMessage = warning }
        } catch { if generation == token { creationError = error.localizedDescription } }
    }
    func revealCreatedSession(_ id: String, focus: Bool = true) {
        guard workspace.sessions.contains(where: { $0.id == id }) else { return }
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
        guard let source else { return }
        do {
            guard let database else { throw CanvasError.message("Canvas storage is unavailable.") }
            try database.save(workspace, source: source.sourceID)
        } catch { errorMessage = "Changes are not saved. \(error.localizedDescription)" }
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
