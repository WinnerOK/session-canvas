import AppKit
import Foundation
import CanvasCore

/// Session source for local Claude Code sessions. See CanvasCore/ClaudeCode.swift for the
/// evidence model: status hooks first, undocumented runtime files only as a fallback, and the
/// saved transcript for sessions without a live process.
@MainActor
final class ClaudeCodeSource: SessionSource {
    let mode = SourceMode.claudeCode
    let sourceID: String
    let canAssignProject = true
    let canCreate = true
    let removedSessionIDs: Set<String> = []
    var creationUnavailableReason: String { "Claude Code sessions are created in a terminal." }
    var onChange: (() -> Void)?
    var onDisconnect: (() -> Void)?

    let claudeHome: URL
    let statusDirectory: URL
    private let settings: ConnectionSettings
    private var summaries: [String: (key: String, summary: ClaudeTranscriptSummary)] = [:]
    private var transcriptPaths: [String: String] = [:]
    private var evidence: [String: ClaudeEvidence] = [:]
    private var liveJobs: [String: String] = [:]   // sessionID -> job short id (for `claude attach`)
    private var historyCache: [String: [HistoryEntry]] = [:]
    private var historyTruncated: Set<String> = []
    private var resolvedFolders: [String: String] = [:]
    private var workFolders: [String: String] = [:], relocatedFolders: [String: String] = [:], foundFolders: [String: String] = [:]
    private var watchers: [DispatchSourceFileSystemObject] = []
    /// Projects chosen by dragging a note: sessionID -> projectID. Kept by Session Canvas only;
    /// Claude Code has no project membership to change.
    private var assignments: [String: String] = [:]
    private var lastSessions: [String: Session] = [:]
    private var assignmentsURL: URL { statusDirectory.deletingLastPathComponent().appendingPathComponent("claude-project-assignments.json") }
    private var rulesURL: URL { statusDirectory.deletingLastPathComponent().appendingPathComponent("claude-project-rules.json") }
    private(set) var hooksInstalled = false
    private(set) var lastHookEvent: Date?
    private(set) var hooksLagging = false
    private var liveCount = 0

    static var defaultStatusDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Session Canvas/claude-status", isDirectory: true)
    }

    init(settings: ConnectionSettings, claudeHome: URL? = nil, statusDirectory: URL? = nil) {
        self.settings = settings
        self.claudeHome = claudeHome ?? URL(fileURLWithPath: NSString(string: settings.resolvedClaudeHome).expandingTildeInPath, isDirectory: true)
        self.statusDirectory = statusDirectory ?? Self.defaultStatusDirectory
        sourceID = "claude-local:" + self.claudeHome.path
        if let data = try? Data(contentsOf: assignmentsURL), let saved = try? JSONDecoder().decode([String: String].self, from: data) { assignments = saved }
    }

    var hasLiveState: Bool { true }
    var connectionStatus: String {
        if !hooksInstalled { return "Claude Code · status hooks not installed (fallback)" }
        if hooksLagging { return "Claude Code · status hooks are not reporting" }
        return "Claude Code · status hooks active"
    }
    var statusHealth: String {
        var parts: [String] = []
        if hooksInstalled {
            parts.append(lastHookEvent.map { "Status hooks installed · last event \(ActivityTime.label($0))" } ?? "Status hooks installed · no events yet (restart running Claude Code sessions)")
        } else {
            parts.append("Status hooks are not installed. Live state comes from undocumented Claude Code runtime files and may stop working after an update.")
        }
        if hooksLagging { parts.append("Some transcripts advanced without hook events. Check that hooks are enabled (/hooks in Claude Code).") }
        parts.append("\(liveCount) live session(s).")
        return parts.joined(separator: " ")
    }
    func evidenceLabel(sessionID: String) -> String? { evidence[sessionID]?.label }

    func connect() async throws {
        guard FileManager.default.fileExists(atPath: claudeHome.appendingPathComponent("projects").path) else {
            throw CanvasError.message("No Claude Code sessions found at \(claudeHome.path). Check the Claude Code home folder in Connection settings.")
        }
        try? FileManager.default.createDirectory(at: statusDirectory, withIntermediateDirectories: true)
        hooksInstalled = Self.readSettings(claudeHome).map(ClaudeHookInstaller.isInstalled) ?? false
        startWatching()
    }

    // MARK: Inventory

    private struct ScanInput: Sendable {
        var path: String; var sessionID: String; var key: String; var modified: Date?
    }

    func snapshot() async throws -> (sessions: [Session], projects: [Project]) {
        hooksInstalled = Self.readSettings(claudeHome).map(ClaudeHookInstaller.isInstalled) ?? false
        let projectsDir = claudeHome.appendingPathComponent("projects")
        let known = summaries
        let home = claudeHome
        let statusDir = statusDirectory
        // File work happens off the main actor; only changed transcripts are re-read.
        let scan = await Task.detached(priority: .utility) { () -> (inputs: [ScanInput], fresh: [String: (String, ClaudeTranscriptSummary)], hooks: [String: ClaudeHookRecord], processes: [String: ClaudeProcessRecord], jobs: [String: ClaudeJobRecord]) in
            let fm = FileManager.default
            var inputs: [ScanInput] = []
            for dir in (try? fm.contentsOfDirectory(atPath: projectsDir.path)) ?? [] {
                let folder = projectsDir.appendingPathComponent(dir)
                for file in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where file.hasSuffix(".jsonl") {
                    let path = folder.appendingPathComponent(file).path
                    let attrs = try? fm.attributesOfItem(atPath: path)
                    let size = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
                    let modified = attrs?[.modificationDate] as? Date
                    let id = String(file.dropLast(6))
                    inputs.append(ScanInput(path: path, sessionID: id, key: "\(size)-\(modified?.timeIntervalSince1970 ?? 0)", modified: modified))
                }
            }
            var fresh: [String: (String, ClaudeTranscriptSummary)] = [:]
            for input in inputs where known[input.sessionID]?.key != input.key {
                fresh[input.sessionID] = (input.key, ClaudeTranscript.summary(path: input.path, sessionID: input.sessionID))
            }
            var hooks: [String: ClaudeHookRecord] = [:]
            for file in (try? fm.contentsOfDirectory(atPath: statusDir.path)) ?? [] where file.hasSuffix(".json") && !file.hasPrefix(".") {
                if let data = fm.contents(atPath: statusDir.appendingPathComponent(file).path), let record = ClaudeHookRecord.parse(data) {
                    hooks[record.sessionID] = record
                }
            }
            var processes: [String: ClaudeProcessRecord] = [:]
            let sessionsDir = home.appendingPathComponent("sessions")
            for file in (try? fm.contentsOfDirectory(atPath: sessionsDir.path)) ?? [] where file.hasSuffix(".json") {
                if let data = fm.contents(atPath: sessionsDir.appendingPathComponent(file).path), let record = ClaudeProcessRecord.parse(data),
                   ClaudeCodeSource.isAlive(record.pid) {
                    processes[record.sessionID] = record
                }
            }
            var jobs: [String: ClaudeJobRecord] = [:]
            let jobsDir = home.appendingPathComponent("jobs")
            for dir in (try? fm.contentsOfDirectory(atPath: jobsDir.path)) ?? [] {
                if let data = fm.contents(atPath: jobsDir.appendingPathComponent(dir).appendingPathComponent("state.json").path),
                   let record = ClaudeJobRecord.parse(data, shortID: dir) {
                    jobs[record.sessionID] = record
                }
            }
            return (inputs, fresh, hooks, processes, jobs)
        }.value

        for (id, value) in scan.fresh { summaries[id] = (value.0, value.1); historyCache.removeValue(forKey: id) }
        var sessions: [Session] = []
        var projects: [String: Project] = [:]
        var lagging = false, live = 0
        liveJobs = [:]
        lastHookEvent = scan.hooks.values.map(\.timestamp).max()
        var listed: Set<String> = []
        // Launch folders first: they are the known projects and tell which folders were moved.
        var launchFolders: [String: String] = [:], moves: [String: String] = [:]
        let userHome = NSHomeDirectory()
        for input in scan.inputs {
            guard let summary = summaries[input.sessionID]?.summary, summary.hasDialogue else { continue }
            let recorded = summary.cwd.isEmpty ? (scan.hooks[input.sessionID]?.cwd ?? scan.processes[input.sessionID]?.cwd ?? "") : summary.cwd
            // Folders can be moved after a session was recorded; Claude Code's history location is current.
            let historyKey = URL(fileURLWithPath: input.path).deletingLastPathComponent().lastPathComponent
            let cacheKey = recorded + "\u{0}" + historyKey
            let cwd = resolvedFolders[cacheKey] ?? ClaudeProjects.currentFolder(recorded: recorded, historyKey: historyKey)
            resolvedFolders[cacheKey] = cwd
            launchFolders[input.sessionID] = cwd
            if !recorded.isEmpty, recorded != cwd { moves[recorded] = cwd }
        }
        let relocate: (String) -> String? = { [self] path in
            if let cached = relocatedFolders[path] { return cached.isEmpty ? nil : cached }
            let found = ClaudeProjects.relocate(path, moves: moves, home: userHome) { name in
                if let hit = self.foundFolders[name] { return hit.isEmpty ? nil : hit }
                let hit = ClaudeProjects.findFolder(named: name, home: userHome)
                self.foundFolders[name] = hit ?? ""
                return hit
            }
            relocatedFolders[path] = found ?? ""
            return found
        }
        let grouping = ClaudeGrouping(home: userHome, rules: ClaudeProjectRules.load(rulesURL, home: userHome) ?? ClaudeProjectRules(projects: []),
                                      launchFolders: Array(launchFolders.values), relocate: relocate)
        for input in scan.inputs {
            guard let summary = summaries[input.sessionID]?.summary, summary.hasDialogue else { continue }
            transcriptPaths[input.sessionID] = input.path
            listed.insert(input.sessionID)
            let hook = scan.hooks[input.sessionID], process = scan.processes[input.sessionID], job = scan.jobs[input.sessionID]
            let state = ClaudeStatus.derive(hook: hook, process: process, job: job, transcript: summary, transcriptModified: input.modified, isAlive: Self.isAlive)
            lagging = lagging || state.hooksLagging
            if state.isLive { live += 1 }
            if let job, process?.kind == "bg" || job.state == "blocked" || job.state == "working" { liveJobs[input.sessionID] = job.shortID }
            let liveName = [job?.name, process?.nameIsDerived == false ? process?.name : nil].compactMap { $0 }.first
            let title = summary.customTitle ?? liveName ?? summary.displayTitle ?? "Untitled session"
            let cwd = launchFolders[input.sessionID] ?? ""
            // Sessions started in ~ are grouped by the project they worked in; they still resume from ~.
            let workKey = input.key + "\u{0}" + cwd
            let work: String
            if let cached = workFolders[workKey] { work = cached } else {
                work = grouping.workFolder(launch: cwd, summary: summary)
                workFolders[workKey] = work
            }
            let projectID = assignments[input.sessionID] ?? grouping.projectID(work: work, summary: summary)
            if let projectID {
                projects[projectID] = Project(id: projectID, name: grouping.name(forProjectID: projectID))
            }
            var session = Session(id: input.sessionID, title: title, projectID: projectID, cwd: cwd, execution: state.execution, requests: state.requests,
                                  latestResult: summary.latestResult, updatedAt: max(summary.lastActivity ?? .distantPast, hook?.timestamp ?? .distantPast),
                                  revision: input.key)
            session.archived = nil
            session.savedState = !state.isLive
            evidence[input.sessionID] = state.evidence
            sessions.append(session)
        }
        // Sessions announced by hooks before their first message (e.g. just created) have no transcript yet.
        for (id, hook) in scan.hooks where !listed.contains(id) {
            guard hook.state != .ended, hook.pid > 0, Self.isAlive(hook.pid), let cwd = hook.cwd else { continue }
            let state = ClaudeStatus.derive(hook: hook, process: scan.processes[id], job: scan.jobs[id], transcript: nil, transcriptModified: nil, isAlive: Self.isAlive)
            let projectID = ClaudeProjects.projectID(for: cwd)
            if let projectID { projects[projectID] = Project(id: projectID, name: ClaudeProjects.name(for: ClaudeProjects.root(for: cwd))) }
            var session = Session(id: id, title: scan.processes[id]?.name ?? "New session", projectID: projectID, cwd: cwd, execution: state.execution,
                                  requests: state.requests, updatedAt: hook.timestamp, revision: "hook-\(hook.timestamp.timeIntervalSince1970)")
            session.archived = nil; session.savedState = false
            evidence[id] = state.evidence
            live += 1
            sessions.append(session)
        }
        hooksLagging = lagging; liveCount = live
        lastSessions = Dictionary(sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let orderedProjects = projects.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return (sessions.sorted { $0.updatedAt > $1.updatedAt }, orderedProjects)
    }

    nonisolated static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    // MARK: History

    func history(sessionID: String, cursor: String?) async throws -> HistoryPage {
        guard let path = transcriptPaths[sessionID] else {
            return HistoryPage(entries: [HistoryEntry(id: sessionID + "/empty", role: "Claude Code", text: "No messages yet. Open the session in Claude Code to send the first instruction.")])
        }
        if cursor == nil || historyCache[sessionID] == nil {
            let loaded = await Task.detached(priority: .userInitiated) { ClaudeTranscript.history(path: path, sessionID: sessionID) }.value
            historyCache[sessionID] = loaded.entries
            if loaded.truncated { historyTruncated.insert(sessionID) } else { historyTruncated.remove(sessionID) }
        }
        let all = historyCache[sessionID] ?? []
        let end = cursor.flatMap(Int.init) ?? all.count
        let start = max(0, end - 40)
        var entries = Array(all[start..<end])
        if start == 0, historyTruncated.contains(sessionID) {
            entries.insert(HistoryEntry(id: sessionID + "/truncated", role: "Session Canvas", text: "Older messages of this very long session are not shown. Open it in Claude Code to read the full history."), at: 0)
        }
        return HistoryPage(entries: entries, nextCursor: start > 0 ? String(start) : nil)
    }

    /// Moving a note into a project is remembered locally; moving it out restores automatic grouping.
    func assign(sessionID: String, projectID: String?, revision: String) async throws -> Session {
        guard var session = lastSessions[sessionID], session.revision == revision else {
            throw CanvasError.message("The session changed during your drag. Please try again.")
        }
        if let projectID {
            guard projectID.hasPrefix("cwd:") else { throw CanvasError.message("That project no longer exists.") }
            assignments[sessionID] = projectID
        } else {
            assignments.removeValue(forKey: sessionID)
        }
        try? FileManager.default.createDirectory(at: assignmentsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(assignments).write(to: assignmentsURL, options: .atomic)
        let refreshed = try await snapshot()
        guard let updated = refreshed.sessions.first(where: { $0.id == sessionID }) else { return session }
        session = updated
        // A note dragged out of every project falls back to its own folder's project.
        if projectID == nil { session.projectID = nil }
        return session
    }

    // MARK: Open / create

    func creationDirectory(projectID: String) -> String? {
        projectID.hasPrefix("cwd:") ? String(projectID.dropFirst(4)) : nil
    }

    /// Opens the session in a terminal: background jobs are attached, others resumed.
    func open(_ session: Session) throws {
        let claude = Self.shellQuote(settings.resolvedClaudeExecutable)
        let command: String
        if let job = liveJobs[session.id] { command = "\(claude) attach \(Self.shellQuote(job))" }
        else { command = "\(claude) --resume \(Self.shellQuote(session.id))" }
        try runInTerminal(command, cwd: session.cwd, title: session.title)
    }

    func create(title: String, prompt: String, projectID: String?, cwd: String) async throws -> CreatedSession {
        var folder = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        if folder.isEmpty, let projectID { folder = creationDirectory(projectID: projectID) ?? "" }
        if folder.isEmpty { folder = NSHomeDirectory() }
        folder = NSString(string: folder).expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CanvasError.message("The working folder does not exist: \(folder)")
        }
        let id = UUID().uuidString.lowercased()
        var command = "\(Self.shellQuote(settings.resolvedClaudeExecutable)) --session-id \(id)"
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { command += " --name \(Self.shellQuote(name))" }
        let first = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !first.isEmpty { command += " \(Self.shellQuote(first))" }
        try runInTerminal(command, cwd: folder, title: name.isEmpty ? "New session" : name)
        var session = Session(id: id, title: name.isEmpty ? "New session" : name, projectID: ClaudeProjects.projectID(for: folder), cwd: folder,
                              execution: first.isEmpty ? .idle : .running)
        session.savedState = false
        return CreatedSession(session: session)
    }

    /// Runs `command` in a new terminal window or tab named after the session: the script sets the
    /// terminal title (OSC 0) and its file carries the session name, since terminals such as cmux name
    /// the tab after the opened file until a title arrives.
    private func runInTerminal(_ command: String, cwd: String, title: String) throws {
        let folder = cwd.isEmpty ? NSHomeDirectory() : cwd
        let label = Self.terminalLabel(title)
        let script = "#!/bin/zsh -l\ncd \(Self.shellQuote(folder)) || exit 1\nclear\nprintf '\\033]0;%s\\007' \(Self.shellQuote(label))\n\(command)\n"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SessionCanvas/\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(label + ".command")
        try script.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        let app = settings.resolvedTerminalApp
        let appURL = URL(fileURLWithPath: app)
        guard FileManager.default.fileExists(atPath: appURL.path) else {
            throw CanvasError.message("Terminal app not found at \(app). Choose one in Connection settings.")
        }
        NSWorkspace.shared.open([file], withApplicationAt: appURL, configuration: .init()) { _, error in
            if let error { Task { @MainActor in NSLog("Session Canvas could not open terminal: \(error.localizedDescription)") } }
        }
    }

    /// A short, file-name-safe version of a session title.
    nonisolated static func terminalLabel(_ title: String) -> String {
        let cleaned = title.components(separatedBy: CharacterSet(charactersIn: "/:\\\n\r\t\u{0}").union(.controlCharacters)).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Claude Code" : String(cleaned.prefix(60))
    }

    nonisolated static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: Hooks

    nonisolated static func settingsURL(_ home: URL) -> URL { home.appendingPathComponent("settings.json") }
    nonisolated static func readSettings(_ home: URL) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: settingsURL(home).path) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
    var hookScriptURL: URL { statusDirectory.deletingLastPathComponent().appendingPathComponent("claude-status-hook.sh") }

    /// Installs or removes the status hook in ~/.claude/settings.json, keeping a backup copy.
    func setHooksInstalled(_ install: Bool) throws {
        guard let settings = Self.readSettings(claudeHome) else {
            throw CanvasError.message("~/.claude/settings.json is not valid JSON. Fix it before installing hooks.")
        }
        let fm = FileManager.default
        let url = Self.settingsURL(claudeHome)
        if fm.fileExists(atPath: url.path) {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try? fm.copyItem(at: url, to: url.deletingLastPathComponent().appendingPathComponent("settings.json.session-canvas-\(stamp).bak"))
        }
        let updated: [String: Any]
        if install {
            try fm.createDirectory(at: statusDirectory, withIntermediateDirectories: true)
            try ClaudeHookInstaller.script(statusDirectory: statusDirectory.path).write(to: hookScriptURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookScriptURL.path)
            // The marker in the command lets us find and remove exactly our entries later.
            let command = Self.shellQuote(hookScriptURL.path) + " # " + ClaudeHookInstaller.marker
            updated = ClaudeHookInstaller.installing(into: settings, command: command)
        } else {
            updated = ClaudeHookInstaller.removing(from: settings)
        }
        let data = try JSONSerialization.data(withJSONObject: updated, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys])
        try data.write(to: url, options: .atomic)
        hooksInstalled = install
    }

    // MARK: Watching

    private func startWatching() {
        stopWatching()
        for url in [statusDirectory, claudeHome.appendingPathComponent("sessions"), claudeHome.appendingPathComponent("jobs")] {
            let fd = Darwin.open(url.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.onChange?() } }
            source.setCancelHandler { Darwin.close(fd) }
            source.resume()
            watchers.append(source)
        }
    }
    private func stopWatching() { watchers.forEach { $0.cancel() }; watchers = [] }

    func close() { stopWatching() }
}
