import Foundation
import CanvasCore

let args = CommandLine.arguments

// `SessionCanvasProbe --hook-settings STATUS_DIR SCRIPT_PATH` writes the status hook script and prints
// a settings fragment, for testing hooks with `claude --settings` without touching user settings.
if args.count == 4 && args[1] == "--hook-settings" {
    try! ClaudeHookInstaller.script(statusDirectory: args[2]).write(toFile: args[3], atomically: true, encoding: .utf8)
    chmod(args[3], 0o755)
    let settings = ClaudeHookInstaller.installing(into: [:], command: "'\(args[3])' # \(ClaudeHookInstaller.marker)")
    print(String(decoding: try! JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]), as: UTF8.self))
    exit(0)
}

// `SessionCanvasProbe --claude [CLAUDE_HOME] [STATUS_DIR]` prints only counts and timings for the
// Claude Code source; it never prints conversation content.
if args.count >= 2 && args[1] == "--claude" {
    let args = args.filter { $0 != "--groups" }
    let fm = FileManager.default
    let home = URL(fileURLWithPath: NSString(string: args.count > 2 ? args[2] : "~/.claude").expandingTildeInPath)
    let statusDir = URL(fileURLWithPath: args.count > 3 ? args[3] : fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Session Canvas/claude-status").path)
    let alive: (Int32) -> Bool = { $0 > 0 && (kill($0, 0) == 0 || errno == EPERM) }
    let started = Date()
    var hooks: [String: ClaudeHookRecord] = [:], processes: [String: ClaudeProcessRecord] = [:], jobs: [String: ClaudeJobRecord] = [:]
    for f in (try? fm.contentsOfDirectory(atPath: statusDir.path)) ?? [] where f.hasSuffix(".json") && !f.hasPrefix(".") {
        if let d = fm.contents(atPath: statusDir.appendingPathComponent(f).path), let r = ClaudeHookRecord.parse(d) { hooks[r.sessionID] = r }
    }
    for f in (try? fm.contentsOfDirectory(atPath: home.appendingPathComponent("sessions").path)) ?? [] where f.hasSuffix(".json") {
        if let d = fm.contents(atPath: home.appendingPathComponent("sessions/" + f).path), let r = ClaudeProcessRecord.parse(d), alive(r.pid) { processes[r.sessionID] = r }
    }
    for dir in (try? fm.contentsOfDirectory(atPath: home.appendingPathComponent("jobs").path)) ?? [] {
        if let d = fm.contents(atPath: home.appendingPathComponent("jobs/\(dir)/state.json").path), let r = ClaudeJobRecord.parse(d, shortID: dir) { jobs[r.sessionID] = r }
    }
    var counts: [String: Int] = [:], evidence: [String: Int] = [:], groups: [String: Int] = [:]
    var listed = 0, skipped = 0, withResult = 0, lagging = 0
    var rows: [(id: String, summary: ClaudeTranscriptSummary, launch: String, modified: Date?)] = []
    var moves: [String: String] = [:]
    let userHome = NSHomeDirectory()
    for dir in (try? fm.contentsOfDirectory(atPath: home.appendingPathComponent("projects").path)) ?? [] {
        let folder = home.appendingPathComponent("projects/" + dir)
        for file in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where file.hasSuffix(".jsonl") {
            let path = folder.appendingPathComponent(file).path, id = String(file.dropLast(6))
            let summary = ClaudeTranscript.summary(path: path, sessionID: id)
            guard summary.hasDialogue else { skipped += 1; continue }
            let launch = ClaudeProjects.currentFolder(recorded: summary.cwd, historyKey: dir)
            if !summary.cwd.isEmpty, summary.cwd != launch { moves[summary.cwd] = launch }
            rows.append((id, summary, launch, ClaudeJSONL.modified(path)))
        }
    }
    var found: [String: String?] = [:]
    let relocate: (String) -> String? = { path in
        ClaudeProjects.relocate(path, moves: moves, home: userHome) { name in
            if let hit = found[name] { return hit }
            let hit = ClaudeProjects.findFolder(named: name, home: userHome); found[name] = hit; return hit
        }
    }
    let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Session Canvas")
    let rules = ClaudeProjectRules.load(support.appendingPathComponent("claude-project-rules.json"), home: userHome) ?? ClaudeProjectRules(projects: [])
    let grouping = ClaudeGrouping(home: userHome, rules: rules, launchFolders: rows.map(\.launch), relocate: relocate)
    let printGroups = CommandLine.arguments.contains("--groups")
    for row in rows {
        listed += 1
        if row.summary.latestResult != nil { withResult += 1 }
        let work = grouping.workFolder(launch: row.launch, summary: row.summary)
        if let p = grouping.projectID(work: work, summary: row.summary) {
            groups[grouping.name(forProjectID: p), default: 0] += 1
            if printGroups { print(String(row.id.prefix(8)) + "\t" + p) }   // ids and folders only
        }
        let s = ClaudeStatus.derive(hook: hooks[row.id], process: processes[row.id], job: jobs[row.id], transcript: row.summary, transcriptModified: row.modified, isAlive: alive)
        if s.hooksLagging { lagging += 1 }
        let state = s.requests.values.contains(.permission) ? "permission" : s.requests.values.contains(.input) ? "waiting" : s.execution.rawValue
        counts[(s.isLive ? "live-" : "saved-") + state, default: 0] += 1
        evidence[s.evidence.rawValue, default: 0] += 1
    }
    let report: [String: Any] = ["sessions": listed, "skipped_without_dialogue": skipped, "with_result": withResult, "projects": groups.count,
                                 "states": counts, "evidence": evidence, "hook_records": hooks.count, "live_processes": processes.count,
                                 "jobs": jobs.count, "hooks_lagging": lagging, "project_groups": groups, "seconds": (Date().timeIntervalSince(started) * 100).rounded() / 100]
    print(String(decoding: try! JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted]), as: UTF8.self))
    exit(0)
}

guard args.count == 4 else {
    fputs("Usage: SessionCanvasProbe ROLLOUT_PATH CODEX_HOME SESSION_ID\n       SessionCanvasProbe --claude [CLAUDE_HOME] [STATUS_DIR]\n", stderr)
    exit(2)
}
do {
    let entries = try RolloutReader.read(path: args[1], codexHome: args[2], sessionID: args[3])
    let evidence: [String: Any] = ["identity_verified": true, "dialogue_entries": entries.count, "terminal_results": entries.filter { $0.result != nil }.count]
    let data = try JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
} catch {
    fputs("Saved-history verification failed. No conversation content was printed.\n", stderr)
    exit(1)
}
