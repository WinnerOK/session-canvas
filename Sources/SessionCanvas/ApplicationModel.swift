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
    @Published var isRefreshing = false
    @Published var selectedSessionID: String?
    @Published var search = ""
    @Published var stateFilter: NoteState?
    @Published var history: [HistoryEntry] = []
    @Published var nextHistoryCursor: String?
    @Published var isLoadingHistory = false
    @Published var historyError: String?
    @Published var errorMessage: String?
    @Published var settings: ConnectionSettings
    @Published var showsSettings = false
    @Published var creation: CreationContext?
    @Published var pendingSessions: Set<String> = []
    @Published var fitRequest = 0
    @Published var focusedProjectID: String?
    @Published var focusRequest = 0
    @Published var isCreating = false
    private var source: SessionSource?
    private var database: CanvasDatabase?
    private var refreshTask: Task<Void, Never>?
    private var changeTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?
    private var generation = UUID()
    private var saveTask: Task<Void, Never>?

    struct CreationContext: Identifiable {
        let id = UUID()
        var location: Point
        var projectID: String?
    }

    init(demo: Bool, storagePath: String? = nil) {
        mode = demo ? .demo : .history
        settings = UserDefaults.standard.data(forKey: "connectionSettings").flatMap { try? JSONDecoder().decode(ConnectionSettings.self, from: $0) } ?? .defaults
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
    var canCreate: Bool { source?.canCreate == true && connected }
    var canAssignProject: Bool { source?.canAssignProject == true && connected }
    var selectedSession: Session? { workspace.sessions.first { $0.id == selectedSessionID } }
    func state(_ session: Session) -> NoteState { session.state(acknowledged: acknowledgments[session.id] ?? []) }
    var visibleSessions: [Session] {
        workspace.sessions.filter { session in
            (search.isEmpty || session.title.localizedCaseInsensitiveContains(search)) && (stateFilter == nil || state(session) == stateFilter)
        }
    }
    var unreviewedCount: Int {
        workspace.sessions.filter { session in session.latestResult.map { !(acknowledgments[session.id] ?? []).contains($0.id) } ?? false }.count
    }
    var sourceExplanation: String {
        switch mode {
        case .demo: return "Demo data · changes stay in this workspace"
        case .history: return "Saved sessions · live state and desktop project membership unavailable"
        case .shared: return "Shared runtime · desktop project membership unavailable"
        }
    }

    func connect(mode newMode: SourceMode? = nil) async {
        persist()
        refreshTask?.cancel(); changeTask?.cancel(); loadTask?.cancel(); saveTask?.cancel()
        source?.close()
        generation = UUID()
        let token = generation
        if let newMode { mode = newMode }
        connected = false; selectedSessionID = nil; history = []; historyError = nil
        pendingSessions = []; isRefreshing = false; isLoadingHistory = false; isCreating = false
        connectionStatus = "Connecting…"
        let next: SessionSource
        if mode == .demo {
            let saved = try? database?.load(source: "demo-v1")
            next = DemoSource(restored: saved?.sessions ?? [])
        } else { next = CodexSource(mode: mode, settings: settings) }
        source = next
        let cachedSourceID = next.sourceID
        do {
            workspace = try database?.load(source: next.sourceID) ?? Workspace()
            acknowledgments = try database?.acknowledgments(source: next.sourceID) ?? [:]
            if mode != .demo {
                for i in workspace.sessions.indices { workspace.sessions[i].execution = .unknown }
            }
            next.onChange = { [weak self] in
                guard let self, self.generation == token else { return }
                self.changeTask?.cancel()
                self.changeTask = Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    await self.refresh()
                }
            }
            next.onDisconnect = { [weak self] in
                guard let self, self.generation == token else { return }
                self.connected = false; self.connectionStatus = "Disconnected"
                for i in self.workspace.sessions.indices { self.workspace.sessions[i].execution = .unknown }
            }
            try await next.connect()
            guard generation == token else { return }
            if next.sourceID != cachedSourceID {
                workspace = try database?.load(source: next.sourceID) ?? Workspace()
                acknowledgments = try database?.acknowledgments(source: next.sourceID) ?? [:]
                for i in workspace.sessions.indices { workspace.sessions[i].execution = .unknown }
            }
            connected = true
            connectionStatus = mode == .demo ? "Demo workspace" : mode == .history ? "Saved sessions connected" : "Shared server connected"
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
            errorMessage = mode == .shared ? "No reachable shared Codex server. Select Saved Codex sessions to browse existing history, or configure its control socket. \(error.localizedDescription)" : error.localizedDescription
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
            let hadContent = !workspace.sessions.isEmpty
            let hadPlacements = !workspace.placements.isEmpty
            // Preserve cached notes when an inventory is incomplete or metadata-only discovery omits them.
            var merged = Dictionary(uniqueKeysWithValues: workspace.sessions.map { ($0.id, $0) })
            for session in snapshot.sessions {
                var updated = session
                if updated.latestResult == nil { updated.latestResult = merged[session.id]?.latestResult }
                merged[session.id] = updated
            }
            for id in source.removedSessionIDs { merged.removeValue(forKey: id) }
            workspace.reconcile(sessions: merged.values.sorted { $0.updatedAt > $1.updatedAt }, projects: snapshot.projects)
            if mode == .demo && !hadPlacements {
                workspace.regions = ["canvas": Rect(0, 0, 540, 440), "research": Rect(610, 0, 540, 440)]
                for (id, point) in ["demo-native": Point(20, 68), "demo-state": Point(280, 68), "demo-access": Point(20, 246), "demo-options": Point(630, 68), "demo-docs": Point(890, 68), "demo-stopped": Point(0, 500)] {
                    workspace.placements[id] = Placement(point)
                }
            }
            if let id = selectedSessionID, !workspace.sessions.contains(where: { $0.id == id }) { selectedSessionID = nil; history = [] }
            persist()
            if !hadContent && mode == .demo { fitRequest += 1 }
        } catch {
            guard generation == token else { return }
            for i in workspace.sessions.indices { workspace.sessions[i].execution = .unknown }
            errorMessage = "Refresh failed; existing notes have been retained. \(error.localizedDescription)"
        }
    }
    func openSession(_ id: String) {
        selectedSessionID = id; history = []; nextHistoryCursor = nil; historyError = nil
        loadTask?.cancel()
        loadTask = Task { await loadHistory(older: false) }
    }
    func loadHistory(older: Bool) async {
        guard let source, let id = selectedSessionID else { return }
        isLoadingHistory = true; historyError = nil
        let token = generation, cursor = older ? nextHistoryCursor : nil
        defer { if generation == token && selectedSessionID == id { isLoadingHistory = false } }
        do {
            let page = try await source.history(sessionID: id, cursor: cursor)
            guard generation == token, selectedSessionID == id, !Task.isCancelled else { return }
            if older { history = page.entries + history }
            else { history = page.entries }
            nextHistoryCursor = page.nextCursor
            if !older, let result = page.entries.compactMap(\.result).last,
               let i = workspace.sessions.firstIndex(where: { $0.id == id }) {
                workspace.sessions[i].latestResult = result
                persist()
            }
        } catch { if generation == token && selectedSessionID == id { historyError = error.localizedDescription } }
    }
    func acknowledge(_ result: SessionResult, sessionID: String) {
        guard selectedSessionID == sessionID, history.contains(where: { $0.result?.id == result.id }), let database else { return }
        do {
            try database.acknowledge(source: sourceID, session: sessionID, result: result.id)
            acknowledgments[sessionID, default: []].insert(result.id)
        } catch { errorMessage = "Acknowledgment was not saved. Please retry. \(error.localizedDescription)" }
    }
    func moveNote(id: String, position: Point, expectedRevision: String) {
        guard let session = workspace.sessions.first(where: { $0.id == id }), let previous = workspace.placements[id], !pendingSessions.contains(id) else { return }
        guard session.revision == expectedRevision else { errorMessage = "The session changed during the drag. Its current placement was retained."; return }
        let proposed = Placement(position), target = workspace.project(at: proposed.center)
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
    func beginCreation(at point: Point) { creation = CreationContext(location: point, projectID: workspace.project(at: point)) }
    func create(title: String, prompt: String, projectID: String?, cwd: String) async {
        guard let source, canCreate, let context = creation, !isCreating, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isCreating = true
        let token = generation
        defer { if generation == token { isCreating = false } }
        do {
            let session = try await source.create(title: title, prompt: prompt, projectID: projectID, cwd: cwd)
            guard generation == token else { return }
            await refresh()
            guard generation == token else { return }
            let placement = Placement(context.location)
            if workspace.project(at: placement.center) == session.projectID && !workspace.placements.contains(where: { $0.key != session.id && $0.value.rect.intersects(placement.rect) }) {
                workspace.placements[session.id] = placement
            }
            creation = nil; persist()
        } catch { if generation == token { errorMessage = error.localizedDescription } }
    }
    func openInCodex(_ session: Session) {
        guard mode != .demo else { return }
        let escaped = session.id.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? session.id
        guard settings.nativeURLTemplate.contains("{id}"), let url = URL(string: settings.nativeURLTemplate.replacingOccurrences(of: "{id}", with: escaped)), url.scheme == "codex",
              NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
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
    func shutdown() { persist(); source?.close(); refreshTask?.cancel() }
}
