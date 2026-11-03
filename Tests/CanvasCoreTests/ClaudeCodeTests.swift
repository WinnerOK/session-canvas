import Foundation
import Testing
@testable import CanvasCore

@Suite struct ClaudeCodeTests {
    private func line(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self) + "\n"
    }
    private func user(_ uuid: String, _ content: Any, extra: [String: Any] = [:]) -> String {
        line(["type": "user", "uuid": uuid, "cwd": "/Projects/app", "timestamp": "2026-11-03T10:00:00.000Z",
              "message": ["role": "user", "content": content]].merging(extra) { $1 })
    }
    private func assistant(_ uuid: String, message: String, blocks: [[String: Any]], stop: String?, extra: [String: Any] = [:]) -> String {
        var msg: [String: Any] = ["id": message, "role": "assistant", "content": blocks]
        msg["stop_reason"] = stop ?? NSNull()
        return line(["type": "assistant", "uuid": uuid, "cwd": "/Projects/app", "timestamp": "2026-11-03T10:00:05.000Z", "message": msg].merging(extra) { $1 })
    }
    private func write(_ text: String) throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    @Test func transcriptSummaryFindsTitleCwdAndTerminalResult() throws {
        let text = user("u1", "Fix the login bug")
            + assistant("a1", message: "m1", blocks: [["type": "text", "text": "Looking."]], stop: "tool_use")
            + assistant("a2", message: "m1", blocks: [["type": "tool_use", "id": "t1", "name": "Bash", "input": [:]]], stop: "tool_use")
            + user("u2", [["type": "tool_result", "tool_use_id": "t1", "content": "TOOL-OUTPUT"]])
            + assistant("a3", message: "m2", blocks: [["type": "text", "text": "Fixed and tested."]], stop: "end_turn")
            + line(["type": "ai-title", "aiTitle": "Login bug", "sessionId": "s"])
        let path = try write(text)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let summary = ClaudeTranscript.summary(path: path, sessionID: "s")
        #expect(summary.cwd == "/Projects/app")
        #expect(summary.displayTitle == "Login bug")
        #expect(summary.turnOpen == false)
        #expect(summary.latestResult == SessionResult(id: "s/m2", outcome: .completed, text: "Fixed and tested."))
        // History carries the same result identity, so it can be acknowledged from the viewer.
        let history = ClaudeTranscript.history(path: path, sessionID: "s").entries
        #expect(history.map(\.role) == ["You", "Claude", "Claude"])
        #expect(history.last?.result?.id == "s/m2")
        #expect(!history.contains { $0.text.contains("TOOL-OUTPUT") })   // tool payloads are excluded
    }

    @Test func openTurnKeepsPreviousResultAndInterruptionStops() throws {
        let finished = user("u1", "First") + assistant("a1", message: "m1", blocks: [["type": "text", "text": "One"]], stop: "end_turn")
        let open = finished + user("u2", "Second")
        let path = try write(open)
        defer { try? FileManager.default.removeItem(atPath: path) }
        var summary = ClaudeTranscript.summary(path: path, sessionID: "s")
        #expect(summary.turnOpen)
        #expect(summary.latestResult?.id == "s/m1")
        try (open + assistant("a2", message: "m2", blocks: [["type": "text", "text": "Partial"]], stop: nil)
             + user("u3", [["type": "text", "text": "[Request interrupted by user]"]])).write(toFile: path, atomically: true, encoding: .utf8)
        summary = ClaudeTranscript.summary(path: path, sessionID: "s")
        #expect(!summary.turnOpen)
        #expect(summary.latestResult?.outcome == .stopped)
        #expect(summary.latestResult?.text == "Partial")
    }

    @Test func metaSidechainAndCommandLinesAreNotDialogue() throws {
        let text = user("u1", "<command-name>/clear</command-name>")
            + user("u2", "injected", extra: ["isMeta": true])
            + user("u3", "subagent prompt", extra: ["isSidechain": true])
        let path = try write(text)
        defer { try? FileManager.default.removeItem(atPath: path) }
        #expect(!ClaudeTranscript.summary(path: path, sessionID: "s").hasDialogue)
    }

    @Test func largeTranscriptReadsHeadAndTail() throws {
        let head = user("u1", "Original task")
        let padding = line(["type": "api-request-blob", "message": String(repeating: "x", count: ClaudeTranscript.tailBytes + 1024)])
        let tail = assistant("a9", message: "m9", blocks: [["type": "text", "text": "Final answer"]], stop: "end_turn")
            + line(["type": "custom-title", "customTitle": "Renamed"])
        let path = try write(head + padding + tail)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let summary = ClaudeTranscript.summary(path: path, sessionID: "s")
        #expect(summary.firstPrompt == "Original task")
        #expect(summary.displayTitle == "Renamed")
        #expect(summary.latestResult?.id == "s/m9")
        #expect(!summary.turnOpen)
    }

    @Test func hookEventsMapToAttentionStates() {
        #expect(ClaudeHookRecord.state(event: "UserPromptSubmit", notificationType: nil, message: nil, source: nil) == .running)
        #expect(ClaudeHookRecord.state(event: "PreToolUse", notificationType: nil, message: nil, source: nil) == .running)
        #expect(ClaudeHookRecord.state(event: "PermissionRequest", notificationType: nil, message: nil, source: nil) == .permission)
        #expect(ClaudeHookRecord.state(event: "Notification", notificationType: "permission_prompt", message: nil, source: nil) == .permission)
        #expect(ClaudeHookRecord.state(event: "Notification", notificationType: nil, message: "Claude needs your permission to use Bash", source: nil) == .permission)
        #expect(ClaudeHookRecord.state(event: "Notification", notificationType: "elicitation_dialog", message: nil, source: nil) == .input)
        #expect(ClaudeHookRecord.state(event: "Notification", notificationType: "auth_success", message: nil, source: nil) == nil)
        #expect(ClaudeHookRecord.state(event: "Stop", notificationType: nil, message: nil, source: nil) == .idle)
        #expect(ClaudeHookRecord.state(event: "SessionStart", notificationType: nil, message: nil, source: "compact") == .running)
        #expect(ClaudeHookRecord.state(event: "SessionEnd", notificationType: nil, message: nil, source: nil) == .ended)
        #expect(ClaudeHookRecord.state(event: "SomeFutureEvent", notificationType: nil, message: nil, source: nil) == nil)
    }

    @Test func hookRecordParsesScriptOutput() {
        let data = Data(#"{"v":1,"pid":4242,"ts":1793000000,"event":{"session_id":"abc","hook_event_name":"Notification","notification_type":"permission_prompt","cwd":"/p","transcript_path":"/t.jsonl"}}"#.utf8)
        let record = ClaudeHookRecord.parse(data)
        #expect(record?.sessionID == "abc")
        #expect(record?.pid == 4242)
        #expect(record?.state == .permission)
        #expect(record?.cwd == "/p")
        #expect(ClaudeHookRecord.parse(Data("garbage".utf8)) == nil)
    }

    @Test func statusPrefersHooksThenInternalFilesThenTranscript() {
        let hook = ClaudeHookRecord(sessionID: "s", pid: 10, timestamp: Date(), event: "PermissionRequest", state: .permission)
        let process = ClaudeProcessRecord(pid: 10, sessionID: "s", status: "busy", nameIsDerived: true)
        let alive: (Int32) -> Bool = { $0 == 10 }
        var state = ClaudeStatus.derive(hook: hook, process: process, job: nil, transcript: nil, transcriptModified: nil, isAlive: alive)
        #expect(state.evidence == .hooks && state.requests.values.contains(.permission))
        // Hook from a dead process is ignored; fall back to internal files.
        var stale = hook; stale.pid = 99
        state = ClaudeStatus.derive(hook: stale, process: process, job: nil, transcript: nil, transcriptModified: nil, isAlive: alive)
        #expect(state.evidence == .internalFiles && state.execution == .running)
        // An unrecognized internal status (format changed in an update) proves nothing.
        var changed = process; changed.status = "thinking-v2"
        state = ClaudeStatus.derive(hook: nil, process: changed, job: nil, transcript: nil, transcriptModified: nil, isAlive: alive)
        #expect(state.execution == .unknown)
        // Without any live process the transcript's terminal state is saved state.
        state = ClaudeStatus.derive(hook: nil, process: nil, job: nil, transcript: nil, transcriptModified: nil, isAlive: alive)
        #expect(state.evidence == .transcript && !state.isLive && state.execution == .idle)
        // A blocked background job waits for the user.
        let job = ClaudeJobRecord(shortID: "abcd1234", sessionID: "s", state: "blocked")
        state = ClaudeStatus.derive(hook: nil, process: nil, job: job, transcript: nil, transcriptModified: nil, isAlive: alive)
        #expect(state.requests.values.contains(.input))
    }

    @Test func silentHooksAreDetectedFromTranscriptActivity() {
        let old = Date(timeIntervalSince1970: 1000)
        let hook = ClaudeHookRecord(sessionID: "s", pid: 10, timestamp: old, event: "Stop", state: .idle)
        var transcript = ClaudeTranscriptSummary(sessionID: "s"); transcript.turnOpen = true
        let state = ClaudeStatus.derive(hook: hook, process: nil, job: nil, transcript: transcript,
                                        transcriptModified: old.addingTimeInterval(600), isAlive: { _ in true })
        #expect(state.hooksLagging && state.execution == .running)
    }

    @Test func installerIsIdempotentAndPreservesOtherHooks() {
        let foreign: [String: Any] = ["model": "opus", "hooks": ["Stop": [["hooks": [["type": "command", "command": "say done"]]]]]]
        let command = "'/x/claude-status-hook.sh' # \(ClaudeHookInstaller.marker)"
        let once = ClaudeHookInstaller.installing(into: foreign, command: command)
        let twice = ClaudeHookInstaller.installing(into: once, command: command)
        #expect(ClaudeHookInstaller.isInstalled(settings: twice))
        let stop = (twice["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]
        #expect(stop?.count == 2)   // foreign + ours, not duplicated
        let removed = ClaudeHookInstaller.removing(from: twice)
        #expect(!ClaudeHookInstaller.isInstalled(settings: removed))
        #expect(removed["model"] as? String == "opus")
        #expect(((removed["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])?.count == 1)
        #expect((removed["hooks"] as? [String: Any])?["PreToolUse"] == nil)
    }

    @Test func movedFoldersResolveFromTheHistoryKey() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("canvas-" + UUID().uuidString.prefix(8))
        let moved = root.appendingPathComponent("Projects/work/acme.v2")
        try FileManager.default.createDirectory(at: moved.appendingPathComponent("metrics"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let newKey = ClaudeProjects.key(for: moved.path)
        #expect(ClaudeProjects.resolve(key: newKey) == moved.path)
        // The recorded folder is gone; the session's history now lives under the new key.
        let old = root.appendingPathComponent("Desktop/acme.old").path
        #expect(ClaudeProjects.currentFolder(recorded: old, historyKey: newKey) == moved.path)
        // An existing recorded folder is kept as is.
        #expect(ClaudeProjects.currentFolder(recorded: moved.path, historyKey: "-nowhere") == moved.path)
        // Nothing resolvable: keep what was recorded.
        #expect(ClaudeProjects.currentFolder(recorded: old, historyKey: "-no-such-folder-anywhere") == old)
        #expect(ClaudeProjects.key(for: "/Users/a/.claude/x_y") == "-Users-a--claude-x-y")
    }

    @Test func worktreesGroupWithTheirRepository() {
        #expect(ClaudeProjects.root(for: "/r/app/.claude/worktrees/feature") == "/r/app")
        #expect(ClaudeProjects.projectID(for: "/r/app") == "cwd:/r/app")
        #expect(ClaudeProjects.projectID(for: "") == nil)
    }

    @Test func homeSessionsGroupWithTheProjectTheyWorkedIn() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("canvas-home-" + UUID().uuidString.prefix(8)).path
        defer { try? fm.removeItem(atPath: home) }
        for dir in ["Projects/home/app/.git", "Projects/home/app/web/src", "Projects/work/acme/metrics", "Projects/tools/plain/sub", ".claude/jobs/x/tmp", "Library/Preferences"] {
            try fm.createDirectory(atPath: home + "/" + dir, withIntermediateDirectories: true)
        }
        // Mostly in a git project's subfolder: grouped with the repository.
        #expect(ClaudeProjects.workFolder(launch: home, cwdCounts: [home: 40, home + "/Projects/home/app/web/src": 20], home: home) == home + "/Projects/home/app")
        // Internal folders never count, and a session that stayed in home keeps its launch folder.
        #expect(ClaudeProjects.workFolder(launch: home, cwdCounts: [home: 5, home + "/.claude/jobs/x/tmp": 90, home + "/Library/Preferences": 9], home: home) == nil)
        #expect(ClaudeProjects.workFolder(launch: home, cwdCounts: [home: 12], home: home) == nil)
        // A brief visit is not enough.
        #expect(ClaudeProjects.workFolder(launch: home, cwdCounts: [home: 100, home + "/Projects/home/app": 2], home: home) == nil)
        // Sessions started elsewhere are never regrouped.
        #expect(ClaudeProjects.workFolder(launch: home + "/Projects/work/acme", cwdCounts: [home + "/Projects/home/app": 50], home: home) == nil)
        // Another session's launch folder wins over a nested folder; without either, the folder itself.
        #expect(ClaudeProjects.workFolder(launch: home, cwdCounts: [home + "/Projects/work/acme/metrics": 9], home: home, knownRoots: [home + "/Projects/work/acme"]) == home + "/Projects/work/acme")
        #expect(ClaudeProjects.workFolder(launch: home, cwdCounts: [home + "/Projects/tools/plain/sub": 9], home: home) == home + "/Projects/tools/plain/sub")
    }

    @Test func movedWorkFoldersAreFoundAgain() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("canvas-home-" + UUID().uuidString.prefix(8)).path
        defer { try? fm.removeItem(atPath: home) }
        for dir in ["Projects/work/acme/metrics", "Projects/home/app/web", ".hidden/app", "Desktop"] {
            try fm.createDirectory(atPath: home + "/" + dir, withIntermediateDirectories: true)
        }
        let search = { (name: String) in ClaudeProjects.findFolder(named: name, home: home) }
        // A move known from another session's history location.
        let moves = [home + "/Desktop/acme.old": home + "/Projects/work/acme"]
        #expect(ClaudeProjects.relocate(home + "/Desktop/acme.old/metrics/dashboards", moves: moves, home: home, search: search) == home + "/Projects/work/acme/metrics")
        // A project moved under Projects is found by its name; hidden folders are not searched.
        #expect(ClaudeProjects.relocate(home + "/app/web", moves: [:], home: home, search: search) == home + "/Projects/home/app/web")
        #expect(ClaudeProjects.findFolder(named: "hidden", home: home) == nil)
        #expect(ClaudeProjects.relocate(home + "/gone/x", moves: [:], home: home, search: search) == nil)
        // The relocated folder feeds grouping.
        let relocate = { (path: String) in ClaudeProjects.relocate(path, moves: moves, home: home, search: search) }
        #expect(ClaudeProjects.workFolder(launch: home, cwdCounts: [home + "/Desktop/acme.old/metrics": 30], home: home,
                                          knownRoots: [home + "/Projects/work/acme"], relocate: relocate) == home + "/Projects/work/acme")
    }

    @Test func transcriptCountsEveryWorkingFolder() {
        var parser = ClaudeTranscriptParser(sessionID: "s", collectEntries: false)
        for (i, cwd) in ["/h", "/h/p", "/h/p"].enumerated() {
            parser.consume(["type": "user", "uuid": "u\(i)", "cwd": cwd, "message": ["role": "user", "content": "hi \(i)"]])
        }
        #expect(parser.summary.cwd == "/h")
        #expect(parser.summary.cwdCounts == ["/h": 1, "/h/p": 2])
    }

    @Test func projectRulesGroupByFolderSplitAndKeywords() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("canvas-rules-" + UUID().uuidString.prefix(8)).path
        defer { try? fm.removeItem(atPath: home) }
        for dir in ["Projects/work/acme/mobile/app", "Projects/work/acme/docs", "Projects/work/stand", "Projects/side/food", "Projects/home/net"] {
            try fm.createDirectory(atPath: home + "/" + dir, withIntermediateDirectories: true)
        }
        let json = """
        {"projects": [
          {"name": "Mobile", "folder": "~/Projects/work/acme/mobile", "include": ["~/Projects/work/stand"], "keywords": ["mobile", "widget"]},
          {"name": "Work", "folder": "~/Projects/work/acme", "keywords": ["roadmap"]},
          {"name": "Network", "folder": "~/Projects/home/net", "keywords": ["router"]},
          {"name": "Home", "folder": "~/Projects/home", "keywords": ["lamp"]},
          {"name": "Side", "folder": "~/Projects/side", "split": true}
        ]}
        """
        let url = URL(fileURLWithPath: home + "/rules.json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        let rules = try #require(ClaudeProjectRules.load(url, home: home))
        #expect(rules.project(forFolder: home + "/Projects/work/acme/mobile/app")?.name == "Mobile")
        #expect(rules.project(forFolder: home + "/Projects/work/stand")?.name == "Mobile")
        #expect(rules.project(forFolder: home + "/Projects/work/acme/docs")?.name == "Work")
        #expect(rules.project(forFolder: home + "/Projects/side/food/src")?.folder == home + "/Projects/side/food")
        #expect(rules.project(forFolder: home + "/Projects/side")?.name == "Side")
        #expect(rules.project(forText: "the Router and the lamp")?.name == "Network")   // tie: earlier rule
        #expect(rules.project(forText: "nothing here") == nil)
        #expect(rules.containers == [home + "/Projects/work/acme", home + "/Projects/home", home + "/Projects/side"])

        let grouping = ClaudeGrouping(home: home, rules: rules, launchFolders: [home, home + "/Projects/work/acme"])
        func group(_ launch: String, _ counts: [String: Int], prompt: String = "") -> String? {
            var summary = ClaudeTranscriptSummary(sessionID: "s")
            summary.cwdCounts = counts; summary.promptSample = prompt
            return grouping.projectID(work: grouping.workFolder(launch: launch, summary: summary), summary: summary)
        }
        let acme = home + "/Projects/work/acme"
        // Started in a container, worked in a product: the product.
        #expect(group(acme, [acme: 10, acme + "/mobile/app": 8]) == "cwd:" + acme + "/mobile")
        // Never left the container: keywords may pick a product inside it, but not one elsewhere.
        #expect(group(acme, [acme: 10], prompt: "Widget layout") == "cwd:" + acme + "/mobile")
        #expect(group(acme, [acme: 10], prompt: "the lamp") == "cwd:" + acme)
        // Never left home: keywords pick any project; nothing matching stays home.
        #expect(group(home, [home: 10], prompt: "lamp is off") == "cwd:" + home + "/Projects/home")
        #expect(group(home, [home: 10], prompt: "which iPad") == "cwd:" + home)
        #expect(grouping.name(forProjectID: "cwd:" + acme) == "Work")
    }
}
