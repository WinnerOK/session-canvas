import Foundation
import CanvasCore

enum SourceMode: String, CaseIterable, Identifiable {
    case history, shared, demo
    var id: String { rawValue }
    var title: String {
        switch self { case .history: return "Saved Codex sessions"; case .shared: return "Shared Codex server"; case .demo: return "Demo workspace" }
    }
}

struct ConnectionSettings: Codable {
    var executable: String
    var socket: String
    var nativeURLTemplate: String
    static var defaults: Self {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [home + "/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        return Self(executable: paths.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/local/bin/codex", socket: "", nativeURLTemplate: "codex://threads/{id}")
    }
}

@MainActor
protocol SessionSource: AnyObject {
    var mode: SourceMode { get }
    var sourceID: String { get }
    var canAssignProject: Bool { get }
    var canCreate: Bool { get }
    var removedSessionIDs: Set<String> { get }
    var onChange: (() -> Void)? { get set }
    var onDisconnect: (() -> Void)? { get set }
    func connect() async throws
    func snapshot() async throws -> (sessions: [Session], projects: [Project])
    func history(sessionID: String, cursor: String?) async throws -> HistoryPage
    func assign(sessionID: String, projectID: String?, revision: String) async throws
    func create(title: String, prompt: String, projectID: String?, cwd: String) async throws -> Session
    func close()
}

@MainActor
final class CodexSource: SessionSource {
    let mode: SourceMode
    private(set) var sourceID: String
    let canAssignProject = false
    let canCreate = false
    var onChange: (() -> Void)?
    var onDisconnect: (() -> Void)?
    private let settings: ConnectionSettings
    private let rpc = RPCConnection()
    private var previous: [String: Session] = [:]
    private var removed: Set<String> = []
    var removedSessionIDs: Set<String> { removed }
    private var legacyHistory: [String: [HistoryEntry]] = [:]
    private var supportsPagedHistory: Bool?
    private var rolloutPaths: [String: String] = [:]
    private var codexHome: String

    init(mode: SourceMode, settings: ConnectionSettings) {
        self.mode = mode; self.settings = settings
        // History and shared observations of the same local Codex store share acknowledgment/layout identity.
        self.codexHome = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        self.sourceID = "codex-local:" + self.codexHome
        rpc.onDisconnect = { [weak self] in self?.onDisconnect?() }
        rpc.onMessage = { [weak self] in self?.notification($0) }
    }
    func connect() async throws {
        var args = ["app-server"]
        if mode == .shared {
            args += ["proxy"]
            if !settings.socket.isEmpty { args += ["--sock", NSString(string: settings.socket).expandingTildeInPath] }
        } else { args += ["--listen", "stdio://"] }
        try rpc.start(executable: NSString(string: settings.executable).expandingTildeInPath, arguments: args)
        let initialized = try await rpc.request("initialize", ["clientInfo": .object(["name": .string("session_canvas"), "title": .string("Session Canvas"), "version": .string("0.1.0")]), "capabilities": .object(["experimentalApi": .bool(true)])])
        if let home = initialized["codexHome"].string { codexHome = home; sourceID = "codex-local:" + home }
        try rpc.notify("initialized")
    }
    func snapshot() async throws -> (sessions: [Session], projects: [Project]) {
        var cursor: String?, seen: Set<String> = []
        var result: [String: Session] = [:]
        repeat {
            var params: [String: JSONValue] = ["limit": .number(100), "archived": .bool(false), "useStateDbOnly": .bool(true), "sortKey": .string("updated_at"),
                "sourceKinds": .array(["cli", "vscode", "exec", "appServer", "subAgent", "subAgentReview", "subAgentCompact", "subAgentThreadSpawn", "subAgentOther", "unknown"].map(JSONValue.string))]
            if let cursor { params["cursor"] = .string(cursor) }
            let response = try await rpc.request("thread/list", params)
            guard case .array = response["data"] else { throw CanvasError.message("Codex returned an unsupported session inventory format.") }
            for value in response["data"].array {
                var session = try CodexWire.session(value, live: mode == .shared)
                if let path = value["path"].string { rolloutPaths[session.id] = path }
                session.latestResult = previous[session.id]?.latestResult
                result[session.id] = session
            }
            cursor = response["nextCursor"].string
            if let cursor, !seen.insert(cursor).inserted { throw CanvasError.message("Codex repeated an inventory cursor. Existing notes were retained.") }
        } while cursor != nil
        for (id, value) in result { previous[id] = value }
        for id in removed { previous.removeValue(forKey: id) }
        return (previous.values.sorted { $0.updatedAt > $1.updatedAt }, [])
    }
    func history(sessionID: String, cursor: String?) async throws -> HistoryPage {
        if supportsPagedHistory != false {
            var params: [String: JSONValue] = ["threadId": .string(sessionID), "limit": .number(12), "sortDirection": .string("desc"), "itemsView": .string("full")]
            if let cursor { params["cursor"] = .string(cursor) }
            do {
                let value = try await rpc.request("thread/turns/list", params)
                supportsPagedHistory = true
                let turns = value["data"].array.reversed()
                return HistoryPage(entries: CodexWire.history(Array(turns), sessionID: sessionID), nextCursor: value["nextCursor"].string)
            } catch let error as RPCFailure where [-32600, -32601, -32603].contains(error.code) { supportsPagedHistory = false }
        }
        // CLI 0.146.1 supports only legacy thread/read history. Paginate the returned entries locally.
        if cursor == nil || legacyHistory[sessionID] == nil {
            do {
                let value = try await rpc.request("thread/read", ["threadId": .string(sessionID), "includeTurns": .bool(true)])
                let thread = value["thread"]
                guard thread["id"].string == sessionID else { throw CanvasError.message("Codex returned history for a different session.") }
                let session = try CodexWire.session(thread, live: mode == .shared)
                previous[sessionID] = session
                legacyHistory[sessionID] = CodexWire.history(thread["turns"].array, sessionID: sessionID)
            } catch {
                guard let path = rolloutPaths[sessionID] else { throw error }
                let home = codexHome
                legacyHistory[sessionID] = try await Task.detached(priority: .userInitiated) {
                    try RolloutReader.read(path: path, codexHome: home, sessionID: sessionID)
                }.value
            }
        }
        let entries = legacyHistory[sessionID] ?? []
        let end = min(Int(cursor ?? "") ?? entries.count, entries.count)
        let start = max(0, end - 40)
        return HistoryPage(entries: Array(entries[start..<end]), nextCursor: start > 0 ? String(start) : nil)
    }
    func assign(sessionID: String, projectID: String?, revision: String) async throws {
        throw CanvasError.message("The public Codex app-server protocol does not expose desktop project membership. This move was not applied.")
    }
    func create(title: String, prompt: String, projectID: String?, cwd: String) async throws -> Session {
        throw CanvasError.message("Creating in the existing desktop source is not verified for this connection. Create the conversation in Codex, then refresh this canvas.")
    }
    private func notification(_ message: JSONValue) {
        guard let method = message["method"].string else { return }
        let params = message["params"], id = params["threadId"].string
        if method == "thread/archived" || method == "thread/deleted", let id { removed.insert(id); previous.removeValue(forKey: id) }
        if method == "thread/unarchived", let id = params["thread"]["id"].string { removed.remove(id) }
        if method == "thread/name/updated", let id, let title = params["threadName"].string { previous[id]?.title = title }
        if method == "turn/completed", let id, let result = CodexWire.result(params["turn"], sessionID: id) {
            previous[id]?.latestResult = result
        }
        // Notifications are signals to re-read authoritative metadata; never answer server approval requests.
        if method.hasPrefix("thread/") || method == "turn/completed" || method == "turn/started" || method == "serverRequest/resolved" { onChange?() }
    }
    func close() { rpc.stop() }
}

@MainActor
final class DemoSource: SessionSource {
    let mode = SourceMode.demo
    let sourceID = "demo-v1"
    let canAssignProject = true
    let canCreate = true
    let removedSessionIDs: Set<String> = []
    var onChange: (() -> Void)?
    var onDisconnect: (() -> Void)?
    private var sessions: [Session]
    private let projects = [Project(id: "canvas", name: "Session Canvas"), Project(id: "research", name: "Research")]
    init(restored: [Session]) { sessions = restored.isEmpty ? Self.seed : restored }
    func connect() async throws {}
    func snapshot() async throws -> (sessions: [Session], projects: [Project]) { (sessions, projects) }
    func history(sessionID: String, cursor: String?) async throws -> HistoryPage {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { throw CanvasError.message("Session is unavailable.") }
        var entries = [HistoryEntry(id: sessionID + "/prompt", role: "You", text: "\(session.title). Keep the result concise and include verification.")]
        if let result = session.latestResult { entries.append(HistoryEntry(id: result.id, role: result.outcome.label, text: result.text, result: result)) }
        else { entries.append(HistoryEntry(id: sessionID + "/progress", role: "Codex", text: session.requests.isEmpty ? "This demo session is working through its task." : "This demo session needs your attention. In a connected workspace, use Open in Codex to respond.")) }
        return HistoryPage(entries: entries)
    }
    func assign(sessionID: String, projectID: String?, revision: String) async throws {
        guard let i = sessions.firstIndex(where: { $0.id == sessionID }), sessions[i].revision == revision else { throw CanvasError.message("The session changed during your drag. Please try again.") }
        if let projectID, !projects.contains(where: { $0.id == projectID }) { throw CanvasError.message("That project no longer exists.") }
        try await Task.sleep(for: .milliseconds(220))
        sessions[i].projectID = projectID; sessions[i].revision = UUID().uuidString
    }
    func create(title: String, prompt: String, projectID: String?, cwd: String) async throws -> Session {
        let session = Session(id: UUID().uuidString, title: title.isEmpty ? String(prompt.prefix(60)) : title, projectID: projectID, cwd: cwd, execution: .running)
        sessions.append(session)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, let i = self.sessions.firstIndex(where: { $0.id == session.id }) else { return }
            self.sessions[i].execution = .idle
            self.sessions[i].latestResult = SessionResult(id: session.id + "/turn-1/completed", outcome: .completed, text: "Demo result\n\nThe session is finished. Opening this viewer leaves its note green until you choose Acknowledge.\n\nNo real Codex execution was started.")
            self.onChange?()
        }
        return session
    }
    func close() {}
    static var seed: [Session] {
        [
            Session(id: "demo-native", title: "Build the native canvas", projectID: "canvas", cwd: "/Projects/session-canvas", execution: .running),
            Session(id: "demo-state", title: "Review the attention model", projectID: "canvas", cwd: "/Projects/session-canvas", execution: .idle, latestResult: SessionResult(id: "demo-state/result-1", outcome: .completed, text: "The state model is ready.\n\n• Running, input, and permission states take priority.\n• Acknowledgment applies to this particular result.\n• Opening the viewer does not acknowledge anything.\n\nVerification: all model scenarios passed.")),
            Session(id: "demo-access", title: "Connect the session source", projectID: "canvas", execution: .running, requests: ["approval-1": .permission]),
            Session(id: "demo-options", title: "Compare storage options", projectID: "research", execution: .running, requests: ["question-1": .input]),
            Session(id: "demo-docs", title: "Investigate macOS gestures", projectID: "research", execution: .idle, latestResult: SessionResult(id: "demo-docs/result-1", outcome: .completed, text: "Use two-finger scrolling to pan, pinch to zoom, and secondary click for the context menu.\n\nAppKit owns pointer interaction; SwiftUI presents the surrounding interface.")),
            Session(id: "demo-stopped", title: "Check the packaged build", execution: .idle, latestResult: SessionResult(id: "demo-stopped/result-1", outcome: .stopped, text: "The demo turn was stopped. A stopped outcome still needs explicit acknowledgment."))
        ]
    }
}
