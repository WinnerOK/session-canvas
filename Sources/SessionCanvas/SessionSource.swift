import Foundation
import CanvasCore

enum SourceMode: String, CaseIterable, Identifiable {
    case history, shared, demo
    var id: String { rawValue }
    var title: String {
        switch self { case .history: return "Codex desktop"; case .shared: return "Shared Codex server"; case .demo: return "Demo workspace" }
    }
}

struct ConnectionSettings: Codable {
    var executable: String
    var socket: String
    var nativeURLTemplate: String
    static var defaults: Self {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = ["/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex", home + "/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]
        return Self(executable: paths.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/local/bin/codex", socket: "", nativeURLTemplate: "codex://threads/{id}")
    }
}

struct CreatedSession {
    var session: Session
    var warning: String? = nil
}

@MainActor
protocol SessionSource: AnyObject {
    var mode: SourceMode { get }
    var sourceID: String { get }
    var canAssignProject: Bool { get }
    var canCreate: Bool { get }
    var canArchive: Bool { get }
    var creationUnavailableReason: String { get }
    var hasLiveState: Bool { get }
    var connectionStatus: String { get }
    var removedSessionIDs: Set<String> { get }
    var hiddenSessionIDs: Set<String> { get }
    var onChange: (() -> Void)? { get set }
    var onDisconnect: (() -> Void)? { get set }
    var onSessionObservation: ((Session, Session) -> Void)? { get set }
    func restoreCachedResults(_ sessions: [Session])
    func connect() async throws
    func snapshot() async throws -> (sessions: [Session], projects: [Project])
    func history(sessionID: String, cursor: String?) async throws -> HistoryPage
    func assign(sessionID: String, projectID: String?, revision: String) async throws -> Session
    func setArchived(sessionID: String, archived: Bool) async throws
    func creationDirectory(projectID: String) -> String?
    func create(title: String, prompt: String, projectID: String?, cwd: String) async throws -> CreatedSession
    func close()
}

extension SessionSource {
    var onSessionObservation: ((Session, Session) -> Void)? { get { nil } set {} }
    func restoreCachedResults(_ sessions: [Session]) {}
    var canArchive: Bool { false }
    func setArchived(sessionID: String, archived: Bool) async throws { throw CanvasError.message("Archiving is unavailable for this source.") }
    var creationUnavailableReason: String { "This Codex connection cannot create sessions in projects. Select the desktop-bundled Codex executable in Connection settings and reconnect." }
    func creationDirectory(projectID: String) -> String? { nil }
    var hiddenSessionIDs: Set<String> { [] }
    var hasLiveState: Bool { mode != .history }
    var connectionStatus: String { mode == .demo ? "Demo workspace" : mode == .shared ? "Shared server connected" : "Saved history only · desktop unavailable" }
}

@MainActor
final class CodexSource: SessionSource {
    let mode: SourceMode
    private(set) var sourceID: String
    private(set) var canAssignProject = false
    let canArchive = true
    private(set) var canCreate = false
    private(set) var creationUnavailableReason = "This Codex connection cannot create sessions in projects. Select the desktop-bundled Codex executable in Connection settings and reconnect."
    var onChange: (() -> Void)?
    var onDisconnect: (() -> Void)?
    var onSessionObservation: ((Session, Session) -> Void)?
    private let settings: ConnectionSettings
    private let rpc = RPCConnection()
    private let desktop = DesktopRuntime()
    private let observeDesktop: Bool
    private let observedSessionIDs: Set<String>?
    private var runtimeStatus: [String: JSONValue] = [:]
    private var activeTurnIDs: [String: String] = [:]
    var hasLiveState: Bool { mode == .shared || desktop.connected }
    var connectionStatus: String { mode == .shared ? "Shared server connected" : desktop.connected ? "Codex desktop connected" : "Saved history only · desktop unavailable" }
    private var previous: [String: Session] = [:]
    private var removed: Set<String> = []
    var removedSessionIDs: Set<String> { removed }
    private var legacyHistory: [String: [HistoryEntry]] = [:]
    private var supportsPagedHistory: Bool?
    private var savedObservations: [String: Session] = [:]
    private var savedFileRevisions: [String: String] = [:]
    private var historyObservationVersions: [String: UUID] = [:]
    private var cachedResults: [String: SessionResult] = [:]
    private struct StateCheckKey: Equatable {
        var revision: String
        var fileRevision: String
        var resultID: String
    }
    private var pendingStateChecks: [String: StateCheckKey] = [:]
    private var attemptedStateChecks: [String: StateCheckKey] = [:]
    private var stateCheckTask: Task<Void, Never>?
    private var stateCheckGeneration = UUID()
    private var rolloutPaths: [String: String] = [:]
    private var codexHome: String
    private var desktopProjects: DesktopProjectCatalog?
    private var serverProjectsBySession: [String: String] = [:]
    private var knownServerMemberships: Set<String> = []
    private var creating = false
    private var creationWorker: RPCConnection?
    private let workingDirectoryBase: URL
    private(set) var hiddenSessionIDs: Set<String> = []

    init(mode: SourceMode, settings: ConnectionSettings, workingDirectoryBase: URL? = nil, observeDesktop: Bool = true, observedSessionIDs: Set<String>? = nil) {
        self.mode = mode; self.settings = settings
        self.observeDesktop = observeDesktop
        self.observedSessionIDs = observedSessionIDs
        self.workingDirectoryBase = workingDirectoryBase ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Session Canvas/Workspaces", isDirectory: true)
        // History and shared observations of the same local Codex store share acknowledgment/layout identity.
        self.codexHome = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        self.sourceID = "codex-local:" + self.codexHome
        rpc.onDisconnect = { [weak self] in self?.stopStateRecovery(); self?.onDisconnect?() }
        rpc.onMessage = { [weak self] in self?.notification($0) }
        desktop.onChange = { [weak self] in self?.onChange?() }
    }
    func connect() async throws {
        stopStateRecovery(); attemptedStateChecks = [:]
        var args = ["app-server"]
        if mode == .shared {
            args += ["proxy"]
            if !settings.socket.isEmpty { args += ["--sock", NSString(string: settings.socket).expandingTildeInPath] }
        } else { args += ["--listen", "stdio://"] }
        try rpc.start(executable: NSString(string: settings.executable).expandingTildeInPath, arguments: args)
        let initialized = try await rpc.request("initialize", ["clientInfo": .object(["name": .string("session_canvas"), "title": .string("Session Canvas"), "version": .string("0.1.0")]), "capabilities": .object(["experimentalApi": .bool(true)])])
        if let home = initialized["codexHome"].string { codexHome = home; sourceID = "codex-local:" + home }
        try rpc.notify("initialized")
        // Project APIs and durable projectId on thread/start arrived after CLI 0.146.1.
        // Keep older/custom servers usable for browsing without sending an unverified create.
        if mode == .history, let response = try? await rpc.request("project/list", ["limit": .number(1)]), case .array = response["data"] {
            canCreate = true
            canAssignProject = Self.supportsProjectMoves(userAgent: initialized["userAgent"].string ?? "")
        }
        if mode == .history && observeDesktop { desktop.start(codexHome: codexHome) }
    }
    func restoreCachedResults(_ sessions: [Session]) {
        for session in sessions { if let result = session.latestResult { cachedResults[session.id] = result } }
    }
    func snapshot() async throws -> (sessions: [Session], projects: [Project]) {
        var result: [String: Session] = [:]
        var hidden: Set<String> = []
        for archived in [false, true] {
            var cursor: String?, seen: Set<String> = []
            repeat {
                var params: [String: JSONValue] = ["limit": .number(100), "archived": .bool(archived), "useStateDbOnly": .bool(true), "sortKey": .string("updated_at"),
                    "sourceKinds": .array(["cli", "vscode", "exec", "appServer", "subAgent", "subAgentReview", "subAgentCompact", "subAgentThreadSpawn", "subAgentOther", "unknown"].map(JSONValue.string))]
                if let cursor { params["cursor"] = .string(cursor) }
                let response = try await rpc.request("thread/list", params)
                guard case .array = response["data"] else { throw CanvasError.message("Codex returned an unsupported session inventory format.") }
                for value in response["data"].array {
                    if CodexWire.isInternalSession(value), let id = value["id"].string {
                        hidden.insert(id)
                        continue
                    }
                    var session = try decodeSession(value)
                    session.archived = archived
                    serverProjectsBySession[session.id] = value["projectId"].string
                    if value.object.keys.contains("projectId") { knownServerMemberships.insert(session.id) }
                    if let path = value["path"].string { rolloutPaths[session.id] = path }
                    session.latestResult = previous[session.id]?.latestResult ?? cachedResults[session.id] ?? session.latestResult
                    result[session.id] = session
                }
                cursor = response["nextCursor"].string
                if let cursor, !seen.insert(cursor).inserted { throw CanvasError.message("Codex repeated an inventory cursor. Existing notes were retained.") }
            } while cursor != nil
        }
        // Read only the connected home's exact metadata file; project identity is independent of cwd.
        if let catalog = try DesktopProjectCatalog.read(codexHome: codexHome) { desktopProjects = catalog }
        for id in result.keys { result[id]?.projectID = mappedProjectID(for: id) }
        for (id, value) in result { previous[id] = value }
        hiddenSessionIDs.formUnion(hidden)
        for id in removed.union(hiddenSessionIDs) { previous.removeValue(forKey: id) }
        // Reapply assignments for retained sessions too, including external project moves/removals.
        for id in previous.keys { previous[id]?.projectID = mappedProjectID(for: id) }
        let availableIDs = Set(previous.keys)
        desktop.observe(observedSessionIDs.map { availableIDs.intersection($0) } ?? availableIDs)
        // Bound parallel metadata reads; unchanged source revisions reuse saved evidence.
        let candidates = previous.values.filter {
            let current = desktop.applying(to: $0)
            return current.execution != .running && current.requests.isEmpty
        }
        for offset in stride(from: 0, to: candidates.count, by: 8) {
            await withTaskGroup(of: (Session, UUID?).self) { group in
                for candidate in candidates[offset..<min(offset + 8, candidates.count)] {
                    let historyVersion = historyObservationVersions[candidate.id]
                    group.addTask { @MainActor in (await self.recoverSavedState(candidate), historyVersion) }
                }
                for await (observed, version) in group {
                    // A background/API reply may land between a file task finishing and its result being consumed.
                    if historyObservationVersions[observed.id] == version { savedObservations[observed.id] = observed }
                }
            }
        }
        let sessions = previous.values.map { applyingObservations(to: $0) }
        scheduleStateRecovery(sessions)
        return (sessions.sorted { $0.updatedAt > $1.updatedAt }, desktopProjects?.projects ?? [])
    }
    private func stateCheckKey(_ session: Session) -> StateCheckKey? {
        guard observedSessionIDs?.contains(session.id) != false,
              !session.isArchived, session.execution == .unknown, session.requests.isEmpty,
              session.unknownReason == .historyMissing, let result = session.latestResult else { return nil }
        return StateCheckKey(revision: session.revision, fileRevision: rolloutRevision(sessionID: session.id), resultID: result.id)
    }
    private func scheduleStateRecovery(_ sessions: [Session]) {
        pendingStateChecks = [:]
        for session in sessions {
            if let key = stateCheckKey(session), attemptedStateChecks[session.id] != key { pendingStateChecks[session.id] = key }
        }
        guard stateCheckTask == nil, !pendingStateChecks.isEmpty else { return }
        let generation = stateCheckGeneration
        stateCheckTask = Task { [weak self] in
            defer { if self?.stateCheckGeneration == generation { self?.stateCheckTask = nil } }
            while !Task.isCancelled {
                // One request at a time, at least one second apart; let discovery return first.
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
                guard let self, self.stateCheckGeneration == generation,
                      let id = self.pendingStateChecks.keys.sorted().first,
                      let key = self.pendingStateChecks.removeValue(forKey: id) else { break }
                guard let baseline = self.previous[id], self.stateCheckKey(self.applyingObservations(to: baseline)) == key,
                      self.attemptedStateChecks[id] != key else { continue }
                self.attemptedStateChecks[id] = key
                do {
                    let page = try await self.readHistory(sessionID: id, cursor: nil, limit: 1, stateOnly: true)
                    guard !Task.isCancelled, self.stateCheckGeneration == generation else { break }
                    if let observation = page.sessionObservation { self.onSessionObservation?(observation, baseline) }
                } catch {
                    // Keep Unknown and suppress automatic retries until evidence changes or reconnect.
                }
            }
        }
    }
    private func stopStateRecovery() {
        stateCheckGeneration = UUID()
        stateCheckTask?.cancel(); stateCheckTask = nil; pendingStateChecks = [:]
    }
    private func applyingObservations(to session: Session) -> Session {
        var session = session
        if let saved = savedObservations[session.id], saved.revision == session.revision {
            if session.execution == .unknown { session.execution = saved.execution; session.savedState = saved.savedState }
            session.latestResult = saved.latestResult; session.unknownReason = saved.unknownReason
        }
        if let status = runtimeStatus[session.id], let live = try? CodexWire.session(.object(["id": .string(session.id), "status": status]), live: true) {
            session.execution = live.execution; session.requests = live.requests; session.savedState = false
        }
        return desktop.applying(to: session)
    }
    private func rolloutRevision(sessionID: String) -> String {
        guard let path = rolloutPaths[sessionID], let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return "" }
        return "\((attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)/\(attributes[.size] ?? "")/\(attributes[.systemFileNumber] ?? "")"
    }
    private func recoverSavedState(_ session: Session) async -> Session {
        let fileRevision = rolloutRevision(sessionID: session.id)
        let historyVersion = historyObservationVersions[session.id]
        if let saved = savedObservations[session.id], saved.revision == session.revision,
           savedFileRevisions[session.id] == fileRevision { return saved }
        var observed = session
        if let path = rolloutPaths[session.id] {
            guard FileManager.default.fileExists(atPath: path) else {
                observed.unknownReason = .historyMissing
                return observed
            }
            let home = codexHome
            do {
                let summary = try await Task.detached(priority: .utility, operation: {
                    try RolloutReader.summary(path: path, codexHome: home, sessionID: session.id)
                }).value
                guard historyObservationVersions[session.id] == historyVersion else { return savedObservations[session.id] ?? session }
                observed.execution = summary.execution
                observed.latestResult = summary.result ?? observed.latestResult
                observed.savedState = summary.execution == .idle
                observed.unknownReason = summary.execution == .unknown ? .incompleteHistory : nil
                savedFileRevisions[session.id] = fileRevision
                return observed
            } catch { observed.unknownReason = .incompleteHistory }
            // Missing, unsafe, or ambiguous exact-file evidence must stay visible as Unknown.
            return observed
        }
        observed.unknownReason = .historyMissing
        return observed
    }
    func setArchived(sessionID: String, archived: Bool) async throws {
        _ = try await rpc.request(archived ? "thread/archive" : "thread/unarchive", ["threadId": .string(sessionID)])
        previous[sessionID]?.archived = archived
        removed.remove(sessionID)
        onChange?()
    }
    func history(sessionID: String, cursor: String?) async throws -> HistoryPage {
        try await readHistory(sessionID: sessionID, cursor: cursor, limit: 12)
    }
    private func readHistory(sessionID: String, cursor: String?, limit: Int, stateOnly: Bool = false) async throws -> HistoryPage {
        let baseline = previous[sessionID]
        let fileRevision = rolloutRevision(sessionID: sessionID)
        if supportsPagedHistory != false {
            var params: [String: JSONValue] = ["threadId": .string(sessionID), "limit": .number(Double(limit)), "sortDirection": .string("desc"), "itemsView": .string("full")]
            if let cursor { params["cursor"] = .string(cursor) }
            do {
                let value = try await rpc.request("thread/turns/list", params)
                supportsPagedHistory = true
                guard case .array = value["data"] else { throw CanvasError.message("Codex returned an unsupported history format.") }
                let turns = Array(value["data"].array.reversed())
                let observation = cursor == nil ? observeLatestHistory(sessionID: sessionID, turns: turns, baseline: baseline, fileRevision: fileRevision) : nil
                return HistoryPage(entries: stateOnly ? [] : CodexWire.history(turns, sessionID: sessionID), nextCursor: value["nextCursor"].string, sessionObservation: observation)
            } catch let error as RPCFailure where [-32600, -32601, -32603].contains(error.code) { supportsPagedHistory = false }
        }
        // CLI 0.146.1 supports only legacy thread/read history. Paginate the returned entries locally.
        var observation: Session?
        if cursor == nil || legacyHistory[sessionID] == nil {
            do {
                let value = try await rpc.request("thread/read", ["threadId": .string(sessionID), "includeTurns": .bool(true)])
                let thread = value["thread"]
                guard thread["id"].string == sessionID else { throw CanvasError.message("Codex returned history for a different session.") }
                let session = try decodeSession(thread)
                if cursor == nil { observation = observeLatestHistory(sessionID: sessionID, turns: thread["turns"].array, baseline: baseline, fileRevision: fileRevision, metadata: session) }
                if stateOnly { return HistoryPage(entries: [], sessionObservation: observation) }
                legacyHistory[sessionID] = CodexWire.history(thread["turns"].array, sessionID: sessionID)
            } catch {
                if stateOnly { throw error }
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
        return HistoryPage(entries: Array(entries[start..<end]), nextCursor: start > 0 ? String(start) : nil, sessionObservation: observation)
    }
    private func observeLatestHistory(sessionID: String, turns: [JSONValue], baseline: Session?, fileRevision: String, metadata: Session? = nil) -> Session? {
        // A history response cannot replace source metadata/result changes received while it was in flight.
        guard previous[sessionID] == baseline else { return previous[sessionID].map { applyingObservations(to: $0) } }
        if let metadata, let baseline, metadata.updatedAt < baseline.updatedAt { return applyingObservations(to: baseline) }
        historyObservationVersions[sessionID] = UUID()
        guard rolloutRevision(sessionID: sessionID) == fileRevision else {
            savedObservations.removeValue(forKey: sessionID)
            savedFileRevisions.removeValue(forKey: sessionID)
            return baseline.map { applyingObservations(to: $0) }
        }
        guard var session = metadata ?? baseline else { return nil }
        session.archived = baseline?.archived
        session.projectID = baseline?.projectID
        session.latestResult = turns.reversed().lazy.compactMap { CodexWire.result($0, sessionID: sessionID) }.first ?? baseline?.latestResult
        previous[sessionID] = session
        var saved = session
        let terminal = turns.last.flatMap { CodexWire.result($0, sessionID: sessionID) } != nil
        saved.execution = terminal ? .idle : .unknown
        saved.savedState = terminal
        saved.unknownReason = terminal ? nil : .incompleteHistory
        savedObservations[sessionID] = saved
        savedFileRevisions[sessionID] = fileRevision
        return applyingObservations(to: session)
    }
    static func supportsProjectMoves(userAgent: String) -> Bool {
        // The generated 0.164.0-alpha.11.1 schema and isolated server verify projectId
        // on metadata/update. Older servers can silently ignore unknown fields.
        // Without a parent Codex originator override, initialization uses our client
        // name as the prefix; the version after it is still the server's version.
        let pattern = #"^(?:Codex Desktop|codex_cli_rs|session_canvas)/(\d+)\.(\d+)\.(\d+)(?:-alpha\.(\d+)\.(\d+))?(?: |$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: userAgent, range: NSRange(userAgent.startIndex..., in: userAgent)) else { return false }
        func number(_ index: Int) -> Int? { Range(match.range(at: index), in: userAgent).flatMap { Int(userAgent[$0]) } }
        guard let major = number(1), let minor = number(2), let patch = number(3) else { return false }
        if major != 0 { return major > 0 }
        if minor != 164 { return minor > 164 }
        if patch != 0 { return patch > 0 }
        guard let alpha = number(4), let build = number(5) else { return true }
        return alpha > 11 || alpha == 11 && build >= 1
    }
    private func mappedProjectID(for id: String) -> String? {
        desktopProjects?.projectID(for: id, serverProjectID: serverProjectsBySession[id],
                                   authoritativeServer: canAssignProject && knownServerMemberships.contains(id))
    }
    private func decodeSession(_ value: JSONValue) throws -> Session {
        var session = try CodexWire.session(value, live: mode == .shared)
        if canAssignProject && value.object.keys.contains("projectId") {
            session.revision += "|project:" + (value["projectId"].string ?? "none")
        }
        return session
    }
    private func recordMembership(_ thread: JSONValue, sessionID: String) throws {
        guard thread["id"].string == sessionID, thread.object.keys.contains("projectId"),
              thread["projectId"] == .null || thread["projectId"].string != nil else {
            throw CanvasError.message("Codex did not return confirmed session membership. Refresh before retrying the move.")
        }
        knownServerMemberships.insert(sessionID)
        serverProjectsBySession[sessionID] = thread["projectId"].string
        previous[sessionID]?.projectID = mappedProjectID(for: sessionID)
    }
    func assign(sessionID: String, projectID: String?, revision: String) async throws -> Session {
        guard canAssignProject, let baseline = previous[sessionID], baseline.revision == revision else {
            throw CanvasError.message("Project moves require a current session and a supported desktop Codex connection. Refresh or reconnect before retrying.")
        }
        if let catalog = try DesktopProjectCatalog.read(codexHome: codexHome) { desktopProjects = catalog }
        guard desktopProjects?.allowsLocalMembership(for: sessionID) == true else {
            throw CanvasError.message("This session has no confirmed local project membership. Organize it in its owning Codex host.")
        }
        let serverID: String?
        if let projectID {
            guard let mapped = desktopProjects?.serverProjectID(for: projectID) else { throw CanvasError.message("That project has no confirmed local Codex identity. Refresh before retrying.") }
            let project = try await rpc.request("project/read", ["projectId": .string(mapped)])["project"]
            guard project["id"].string == mapped else { throw CanvasError.message("Codex could not confirm the destination project.") }
            serverID = mapped
        } else { serverID = nil }
        let before = try await rpc.request("thread/read", ["threadId": .string(sessionID), "includeTurns": .bool(false)])["thread"]
        let expectedServerID = serverProjectsBySession[sessionID] ?? baseline.projectID.flatMap { desktopProjects?.serverProjectID(for: $0) }
        try recordMembership(before, sessionID: sessionID)
        guard before["projectId"].string == expectedServerID,
              try decodeSession(before).revision == revision,
              before["cwd"].string == baseline.cwd else {
            throw CanvasError.message("The session changed before the move. Its current Codex project was retained; refresh and try again.")
        }
        var mutationError: Error?
        do { _ = try await rpc.request("thread/metadata/update", ["threadId": .string(sessionID), "projectId": .string(serverID ?? "")]) }
        catch {
            mutationError = error
            if let failure = error as? RPCFailure, [-32601, -32602].contains(failure.code) { canAssignProject = false }
        }
        // Read back even after a rejected/lost reply. Never repeat a mutation to discover
        // its outcome, and never resume or alter the session's execution settings.
        let after: JSONValue
        do {
            after = try await rpc.request("thread/read", ["threadId": .string(sessionID), "includeTurns": .bool(false)])["thread"]
            try recordMembership(after, sessionID: sessionID)
        } catch {
            throw CanvasError.message("The project move could not be confirmed. Refresh to reconcile Codex membership before retrying; the request was not repeated.")
        }
        guard after["projectId"].string == serverID, mappedProjectID(for: sessionID) == projectID,
              after["cwd"] == before["cwd"] else {
            throw CanvasError.message(mutationError == nil ? "Codex did not retain the requested project. Its current membership will be refreshed." : "Codex rejected the project move. Its current membership will be refreshed.")
        }
        var confirmed = try decodeSession(after)
        confirmed.projectID = projectID
        // Metadata-only organization does not replace current work/result evidence.
        confirmed.execution = baseline.execution; confirmed.requests = baseline.requests
        confirmed.latestResult = previous[sessionID]?.latestResult ?? baseline.latestResult
        confirmed.archived = baseline.archived
        previous[sessionID] = confirmed
        return applyingObservations(to: confirmed)
    }
    func creationDirectory(projectID: String) -> String? { desktopProjects?.rootPaths(for: projectID).first }
    func create(title: String, prompt: String, projectID: String?, cwd: String) async throws -> CreatedSession {
        guard canCreate, !creating else { throw CanvasError.message(creationUnavailableReason) }
        guard prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CanvasError.message("Enter your instruction in Codex after creating this session.")
        }
        creating = true
        defer { creating = false; creationWorker?.stop(); creationWorker = nil }
        // Re-read the exact home and confirm the real server identity before creating anything.
        if let catalog = try DesktopProjectCatalog.read(codexHome: codexHome) { desktopProjects = catalog }
        var params: [String: JSONValue] = ["ephemeral": .bool(false)]
        var expectedServerProject: String?
        var directory = NSString(string: cwd.trimmingCharacters(in: .whitespacesAndNewlines)).expandingTildeInPath
        if let projectID {
            guard let serverID = desktopProjects?.serverProjectID(for: projectID) else {
                throw CanvasError.message("This project has no Codex server identity. Open the project in Codex, then refresh and try again.")
            }
            let response = try await rpc.request("project/read", ["projectId": .string(serverID)])
            let project = response["project"]
            guard project["id"].string == serverID, let root = project["roots"].array.first?["path"].string else {
                throw CanvasError.message("The selected project is unavailable or has no working folder. Refresh projects and try again.")
            }
            directory = root
            params["projectId"] = .string(serverID)
            params["runtimeWorkspaceRoots"] = .array(project["roots"].array.compactMap { $0["path"].string }.map(JSONValue.string))
            expectedServerProject = serverID
        }
        if directory.isEmpty {
            let workspace = workingDirectoryBase.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            directory = workspace.path
        }
        var isDirectory: ObjCBool = false
        guard directory.hasPrefix("/"), FileManager.default.fileExists(atPath: directory, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CanvasError.message("Choose an existing working folder before creating the session.")
        }
        params["cwd"] = .string(directory)
        // Inventory/history stays read-only. A short-lived child owns the new chat,
        // then exits so the desktop can resume the same identity immediately.
        let worker = RPCConnection()
        creationWorker = worker
        var observedCreation: JSONValue?
        worker.onMessage = { message in
            if message["method"].string == "thread/started", message["params"]["thread"]["id"].string != nil {
                observedCreation = message["params"]["thread"]
            }
        }
        try await connectCreationWorker(worker)
        let thread: JSONValue
        do { thread = try await worker.request("thread/start", params)["thread"] }
        catch {
            // Our dedicated stdio connection may have received thread/started before losing the reply.
            // Never retry thread/start: it has no idempotency key.
            if let observedCreation { thread = observedCreation }
            else if error is RPCFailure { throw error }
            else {
                canCreate = false
                creationUnavailableReason = "Session creation could not be confirmed. Refresh this canvas and check Codex before reconnecting to create another session."
                onChange?()
                throw CanvasError.message(creationUnavailableReason)
            }
        }
        guard let id = thread["id"].string, !id.isEmpty else {
            canCreate = false
            creationUnavailableReason = "Codex returned no session identity. Refresh this canvas and check Codex before reconnecting to create another session."
            onChange?()
            throw CanvasError.message(creationUnavailableReason)
        }
        var confirmed = thread
        var warning: String?
        let requestedName = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = requestedName.isEmpty ? "New session" : requestedName
        // Naming also materializes an empty rollout in the bundled server. Metadata
        // from thread/start/read alone does not prove that the desktop can load it.
        do { _ = try await worker.request("thread/name/set", ["threadId": .string(id), "name": .string(name)]) }
        catch { warning = "The session was created, but its name and saved history could not be confirmed. Check this session in Codex before creating a replacement." }
        await worker.stopAndWait()
        do {
            // Prove a second process can acquire the persisted chat, then release
            // that verifier too. Never resume on the long-lived inventory client.
            try await connectCreationWorker(worker)
            let read = try await worker.request("thread/resume", ["threadId": .string(id), "excludeTurns": .bool(true)])["thread"]
            guard read["id"].string == id else { throw CanvasError.message("Session identity did not match.") }
            confirmed = read
        } catch { warning = "The session was created, but opening its saved history could not be confirmed. Check this session in Codex before creating a replacement." }
        await worker.stopAndWait()
        serverProjectsBySession[id] = confirmed["projectId"].string
        if confirmed.object.keys.contains("projectId") { knownServerMemberships.insert(id) }
        var session = try decodeSession(confirmed)
        session.projectID = desktopProjects?.projectID(for: id, serverProjectID: confirmed["projectId"].string)
        if confirmed["projectId"].string != expectedServerProject || session.projectID != projectID {
            warning = "The session was created, but Codex did not confirm the selected project. Open it in Codex to check its project."
        }
        // Empty durable threads can be absent from thread/list until their first message.
        previous[id] = session
        if let path = confirmed["path"].string { rolloutPaths[id] = path }
        return CreatedSession(session: session, warning: warning)
    }
    private func connectCreationWorker(_ worker: RPCConnection) async throws {
        try worker.start(executable: NSString(string: settings.executable).expandingTildeInPath, arguments: ["app-server", "--listen", "stdio://"])
        let initialized = try await worker.request("initialize", ["clientInfo": .object(["name": .string("session_canvas_creator"), "version": .string("0.1.0")]), "capabilities": .object(["experimentalApi": .bool(true)])])
        guard initialized["codexHome"].string == codexHome else { throw CanvasError.message("The creation process connected to a different Codex store.") }
        try worker.notify("initialized")
    }
    private func notification(_ message: JSONValue) {
        guard let method = message["method"].string else { return }
        let params = message["params"], id = params["threadId"].string
        if mode == .shared, method == "thread/status/changed", let id { runtimeStatus[id] = params["status"] }
        if mode == .shared, method == "turn/started", let id, let turnID = params["turn"]["id"].string {
            activeTurnIDs[id] = turnID
            runtimeStatus[id] = .object(["type": .string("active"), "activeFlags": .array([])])
        }
        if mode == .shared, method == "turn/completed", let id, let turnID = params["turn"]["id"].string, activeTurnIDs[id] == turnID {
            activeTurnIDs.removeValue(forKey: id)
            runtimeStatus[id] = .object(["type": .string("idle")])
        }
        if method == "thread/deleted", let id { removed.insert(id); previous.removeValue(forKey: id) }
        if method == "thread/archived", let id { previous[id]?.archived = true }
        if method == "thread/unarchived", let restoredID = id ?? params["thread"]["id"].string {
            removed.remove(restoredID); previous[restoredID]?.archived = false
        }
        if method == "thread/name/updated", let id, let title = params["threadName"].string { previous[id]?.title = title }
        if method == "turn/completed", let id, let result = CodexWire.result(params["turn"], sessionID: id) {
            previous[id]?.latestResult = result
        }
        // Notifications are signals to re-read authoritative metadata; never answer server approval requests.
        if method.hasPrefix("thread/") || method == "turn/completed" || method == "turn/started" || method == "serverRequest/resolved" { onChange?() }
    }
    func close() { stopStateRecovery(); desktop.stop(); rpc.stop(); creationWorker?.stop(); runtimeStatus.removeAll(); activeTurnIDs.removeAll() }
}

@MainActor
final class DemoSource: SessionSource {
    let mode = SourceMode.demo
    let sourceID = "demo-v1"
    let canAssignProject = true
    let canCreate = true
    let canArchive = true
    let removedSessionIDs: Set<String> = []
    var onChange: (() -> Void)?
    var onDisconnect: (() -> Void)?
    private var sessions: [Session]
    private let projects = [Project(id: "canvas", name: "Session Canvas"), Project(id: "research", name: "Research")]
    init(restored: [Session]) { sessions = restored.isEmpty ? Self.seed : restored }
    func connect() async throws {}
    func setArchived(sessionID: String, archived: Bool) async throws {
        guard let i = sessions.firstIndex(where: { $0.id == sessionID }) else { throw CanvasError.message("Session is unavailable.") }
        sessions[i].archived = archived
    }
    func snapshot() async throws -> (sessions: [Session], projects: [Project]) { (sessions, projects) }
    func history(sessionID: String, cursor: String?) async throws -> HistoryPage {
        guard let session = sessions.first(where: { $0.id == sessionID }) else { throw CanvasError.message("Session is unavailable.") }
        var entries = [HistoryEntry(id: sessionID + "/prompt", role: "You", text: "\(session.title). Keep the result concise and include verification.")]
        if let result = session.latestResult { entries.append(HistoryEntry(id: result.id, role: result.outcome.label, text: result.text, result: result)) }
        else { entries.append(HistoryEntry(id: sessionID + "/progress", role: "Codex", text: session.requests.isEmpty ? "This demo session is working through its task." : "This demo session needs your attention. In a connected workspace, use Open in Codex to respond.")) }
        return HistoryPage(entries: entries)
    }
    func assign(sessionID: String, projectID: String?, revision: String) async throws -> Session {
        guard let i = sessions.firstIndex(where: { $0.id == sessionID }), sessions[i].revision == revision else { throw CanvasError.message("The session changed during your drag. Please try again.") }
        if let projectID, !projects.contains(where: { $0.id == projectID }) { throw CanvasError.message("That project no longer exists.") }
        try await Task.sleep(for: .milliseconds(220))
        sessions[i].projectID = projectID; sessions[i].revision = UUID().uuidString
        return sessions[i]
    }
    func create(title: String, prompt: String, projectID: String?, cwd: String) async throws -> CreatedSession {
        let session = Session(id: UUID().uuidString, title: title.isEmpty ? String(prompt.prefix(60)) : title, projectID: projectID, cwd: cwd, execution: .running)
        sessions.append(session)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, let i = self.sessions.firstIndex(where: { $0.id == session.id }) else { return }
            self.sessions[i].execution = .idle
            self.sessions[i].latestResult = SessionResult(id: session.id + "/turn-1/completed", outcome: .completed, text: "Demo result\n\nThe session is finished. Opening this viewer leaves its note green until you choose Acknowledge.\n\nNo real Codex execution was started.")
            self.onChange?()
        }
        return CreatedSession(session: session)
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
