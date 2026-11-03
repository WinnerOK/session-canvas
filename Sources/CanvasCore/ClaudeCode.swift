import Foundation

// Claude Code integration primitives. Everything here is a pure function over files so it can be
// tested with fixtures. Evidence sources, from most to least authoritative:
//   1. Status hooks: documented Claude Code hook events written by a tiny script (stable contract).
//   2. Internal runtime files (~/.claude/sessions/<pid>.json, ~/.claude/jobs/*/state.json):
//      undocumented, used only as a fallback and parsed tolerantly.
//   3. Transcripts (~/.claude/projects/*/<session>.jsonl): history, titles and terminal results.
// When no source establishes the current state, the session stays Unknown instead of guessing.

public enum ClaudeEvidence: String, Codable, Sendable {
    case hooks, internalFiles, transcript
    public var label: String {
        switch self {
        case .hooks: return "Live state from Claude Code status hooks"
        case .internalFiles: return "Live state from Claude Code runtime files (fallback)"
        case .transcript: return "State from saved transcript"
        }
    }
}

// MARK: - JSONL reading

public enum ClaudeJSONL {
    /// Reads `length` bytes at `offset`; a bounded read keeps huge transcripts cheap.
    public static func read(path: String, offset: UInt64, length: Int) -> Data {
        guard let handle = FileHandle(forReadingAtPath: path) else { return Data() }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
            return try handle.read(upToCount: length) ?? Data()
        } catch { return Data() }
    }
    public static func fileSize(_ path: String) -> UInt64 {
        ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.uint64Value ?? 0
    }
    public static func modified(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }
    /// Splits into lines; `dropFirst` discards a partial leading line from a tail read,
    /// and an incomplete trailing line (no newline yet, still being appended) is ignored.
    public static func lines(_ data: Data, dropFirst: Bool, keepUnterminated: Bool = false) -> [Data] {
        var result: [Data] = []
        var start = data.startIndex
        var first = true
        for index in data.indices where data[index] == 0x0A {
            if !(first && dropFirst), index > start { result.append(data[start..<index]) }
            first = false
            start = data.index(after: index)
        }
        if keepUnterminated, start < data.endIndex, !(first && dropFirst) { result.append(data[start..<data.endIndex]) }
        return result
    }
    private static let interesting: [Data] = ["\"type\":\"user\"", "\"type\":\"assistant\"", "\"type\":\"custom-title\"", "\"type\":\"ai-title\"", "\"type\":\"agent-name\""].map { Data($0.utf8) }
    /// Cheap pre-filter: most transcript bytes are request blobs and attachments we never need.
    public static func isInteresting(_ line: Data) -> Bool {
        interesting.contains { line.range(of: $0) != nil }
    }
    public static func object(_ line: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
    }
    static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    static let iso: ISO8601DateFormatter = ISO8601DateFormatter()
    public static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        return isoFractional.date(from: text) ?? iso.date(from: text)
    }
}

// MARK: - Transcript parsing

public struct ClaudeTranscriptSummary: Equatable, Sendable {
    public var sessionID: String
    public var cwd = ""
    /// How many dialogue lines were recorded in each working folder (the shell can `cd` mid-session).
    public var cwdCounts: [String: Int] = [:]
    /// Folders of files that tools read or changed (`file_path`/`path` inputs), counted like `cwdCounts`.
    public var pathCounts: [String: Int] = [:]
    /// The first few prompts (shortened), used only to match project keywords.
    public var promptSample = ""
    public var customTitle: String?
    public var aiTitle: String?
    public var agentName: String?
    public var firstPrompt: String?
    public var latestResult: SessionResult?
    /// A prompt was submitted after the last terminal answer (the turn has not ended in the file).
    public var turnOpen = false
    public var lastActivity: Date?
    public var hasDialogue = false
    public init(sessionID: String) { self.sessionID = sessionID }
    public var displayTitle: String? {
        for candidate in [customTitle, agentName, aiTitle, firstPrompt] {
            if let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return String(text.prefix(90)) }
        }
        return nil
    }
}

/// Incremental transcript interpreter shared by the summary and the history viewer, so the
/// result identity shown in the viewer always matches the one on the canvas note.
public struct ClaudeTranscriptParser {
    public let sessionID: String
    public private(set) var summary: ClaudeTranscriptSummary
    public private(set) var entries: [HistoryEntry] = []
    private var collectEntries: Bool
    private var seen: Set<String> = []
    // Current assistant message being streamed as several lines (one per content block).
    private var currentMessageID: String?
    private var currentText: [String] = []
    private var currentEntryIndex: Int?
    private var lastAssistantText: (id: String, text: String)?
    /// `assumeOpenTurn` is used for tail reads that may start in the middle of a turn.
    public init(sessionID: String, collectEntries: Bool, assumeOpenTurn: Bool = false) {
        self.sessionID = sessionID; self.collectEntries = collectEntries
        summary = ClaudeTranscriptSummary(sessionID: sessionID)
        summary.turnOpen = assumeOpenTurn
    }

    static func text(of content: Any?) -> (text: String, toolResult: Bool, toolUse: Bool) {
        if let text = content as? String { return (text, false, false) }
        guard let blocks = content as? [[String: Any]] else { return ("", false, false) }
        var parts: [String] = [], toolResult = false, toolUse = false
        for block in blocks {
            switch block["type"] as? String {
            case "text": if let t = block["text"] as? String { parts.append(t) }
            case "tool_result": toolResult = true
            case "tool_use": toolUse = true
            default: break
            }
        }
        return (parts.joined(separator: "\n\n"), toolResult, toolUse)
    }

    public mutating func consume(_ line: Data) {
        guard ClaudeJSONL.isInteresting(line), let object = ClaudeJSONL.object(line) else { return }
        consume(object)
    }

    public mutating func consume(_ object: [String: Any]) {
        let type = object["type"] as? String
        if let uuid = object["uuid"] as? String, !seen.insert(uuid).inserted { return }
        switch type {
        case "custom-title": if let t = object["customTitle"] as? String { summary.customTitle = t }
        case "ai-title": if let t = object["aiTitle"] as? String { summary.aiTitle = t }
        case "agent-name": if let t = object["agentName"] as? String { summary.agentName = t }
        case "user", "assistant":
            if object["isSidechain"] as? Bool == true { return }
            if let cwd = object["cwd"] as? String {
                if summary.cwd.isEmpty { summary.cwd = cwd }
                summary.cwdCounts[cwd, default: 0] += 1
            }
            if let date = ClaudeJSONL.date(object["timestamp"]) { summary.lastActivity = max(summary.lastActivity ?? date, date) }
            let message = object["message"] as? [String: Any] ?? [:]
            let (text, toolResult, _) = Self.text(of: message["content"])
            if type == "user" { consumeUser(object, text: text, toolResult: toolResult) }
            else { consumeAssistant(object, message: message, text: text) }
        default: break
        }
    }

    private mutating func consumeUser(_ object: [String: Any], text: String, toolResult: Bool) {
        if object["isMeta"] as? Bool == true || object["isCompactSummary"] as? Bool == true { return }
        if toolResult { return }   // tool output continues the current turn
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if trimmed.hasPrefix("[Request interrupted") {
            if summary.turnOpen {
                let uuid = object["uuid"] as? String ?? UUID().uuidString
                let partial = lastAssistantText?.text ?? "The turn was interrupted before an answer."
                let result = SessionResult(id: sessionID + "/" + uuid + "/stopped", outcome: .stopped, text: partial)
                summary.latestResult = result; summary.turnOpen = false
                if collectEntries { entries.append(HistoryEntry(id: result.id, role: "Stopped", text: partial, result: result)) }
            }
            return
        }
        // Slash-command scaffolding and injected system text are not dialogue.
        if trimmed.hasPrefix("<") { return }
        endAssistantMessage()
        summary.hasDialogue = true
        if summary.firstPrompt == nil { summary.firstPrompt = trimmed.components(separatedBy: .newlines).first }
        if summary.promptSample.count < 900 { summary.promptSample += String(trimmed.prefix(300)) + "\n" }
        summary.turnOpen = true
        lastAssistantText = nil
        if collectEntries { entries.append(HistoryEntry(id: sessionID + "/" + (object["uuid"] as? String ?? UUID().uuidString), role: "You", text: trimmed)) }
    }

    private mutating func consumeAssistant(_ object: [String: Any], message: [String: Any], text: String) {
        if let blocks = message["content"] as? [[String: Any]] {
            for block in blocks where block["type"] as? String == "tool_use" {
                guard let input = block["input"] as? [String: Any] else { continue }
                for key in ["file_path", "path", "notebook_path"] {
                    if let value = input[key] as? String, value.hasPrefix("/") {
                        summary.pathCounts[(value as NSString).deletingLastPathComponent, default: 0] += 1
                    }
                }
            }
        }
        let messageID = message["id"] as? String ?? object["uuid"] as? String ?? UUID().uuidString
        if messageID != currentMessageID { endAssistantMessage(); currentMessageID = messageID }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            currentText.append(trimmed)
            let joined = currentText.joined(separator: "\n\n")
            lastAssistantText = (messageID, joined)
            if collectEntries {
                let entry = HistoryEntry(id: sessionID + "/" + messageID, role: "Claude", text: joined)
                if let i = currentEntryIndex { entries[i] = entry } else { entries.append(entry); currentEntryIndex = entries.count - 1 }
            }
        }
        let stop = message["stop_reason"] as? String
        let apiError = object["isApiErrorMessage"] as? Bool == true
        // Any stop reason other than tool_use ends the turn; streamed partial lines carry null.
        if apiError || (stop != nil && stop != "tool_use") {
            guard summary.turnOpen || apiError else { return }
            let body = lastAssistantText?.text ?? (apiError ? "The request failed." : "")
            guard !body.isEmpty else { return }
            let outcome: Outcome = apiError ? .failed : .completed
            let result = SessionResult(id: sessionID + "/" + messageID + (apiError ? "/failed" : ""), outcome: outcome, text: body)
            summary.latestResult = result; summary.turnOpen = false
            if collectEntries {
                if let i = currentEntryIndex, entries[i].id == sessionID + "/" + messageID {
                    entries[i] = HistoryEntry(id: result.id, role: outcome == .completed ? "Claude" : outcome.label, text: body, result: result)
                } else {
                    entries.append(HistoryEntry(id: result.id, role: outcome.label, text: body, result: result)); currentEntryIndex = entries.count - 1
                }
            }
        }
    }

    private mutating func endAssistantMessage() {
        currentMessageID = nil; currentText = []; currentEntryIndex = nil
    }
}

public enum ClaudeTranscript {
    public static let headBytes = 256 * 1024
    public static let tailBytes = 4 * 1024 * 1024
    public static let historyBytes = 48 * 1024 * 1024

    /// Reads the head (cwd, first prompt) and the tail (titles, latest result) of a transcript.
    public static func summary(path: String, sessionID: String) -> ClaudeTranscriptSummary {
        let size = ClaudeJSONL.fileSize(path)
        var parser = ClaudeTranscriptParser(sessionID: sessionID, collectEntries: false)
        if size <= UInt64(headBytes + tailBytes) {
            for line in ClaudeJSONL.lines(ClaudeJSONL.read(path: path, offset: 0, length: Int(size)), dropFirst: false) { parser.consume(line) }
        } else {
            let head = ClaudeJSONL.lines(ClaudeJSONL.read(path: path, offset: 0, length: headBytes), dropFirst: false)
            for line in head { parser.consume(line) }
            var headSummary = parser.summary
            // Restart for the tail so turn/result state reflects the end of the file, keeping head facts.
            var tail = ClaudeTranscriptParser(sessionID: sessionID, collectEntries: false, assumeOpenTurn: true)
            for line in ClaudeJSONL.lines(ClaudeJSONL.read(path: path, offset: size - UInt64(tailBytes), length: tailBytes), dropFirst: true) { tail.consume(line) }
            let t = tail.summary
            headSummary.customTitle = t.customTitle ?? headSummary.customTitle
            headSummary.aiTitle = t.aiTitle ?? headSummary.aiTitle
            headSummary.agentName = t.agentName ?? headSummary.agentName
            headSummary.latestResult = t.latestResult ?? headSummary.latestResult
            headSummary.turnOpen = t.turnOpen
            headSummary.lastActivity = t.lastActivity ?? headSummary.lastActivity
            headSummary.hasDialogue = headSummary.hasDialogue || t.hasDialogue
            if headSummary.cwd.isEmpty { headSummary.cwd = t.cwd }
            headSummary.cwdCounts.merge(t.cwdCounts, uniquingKeysWith: +)
            headSummary.pathCounts.merge(t.pathCounts, uniquingKeysWith: +)
            return headSummary
        }
        return parser.summary
    }

    /// Dialogue for the viewer: user prompts, assistant text and terminal results (no tool payloads
    /// or reasoning). Very large transcripts are read from their most recent `historyBytes`.
    public static func history(path: String, sessionID: String) -> (entries: [HistoryEntry], truncated: Bool) {
        let size = ClaudeJSONL.fileSize(path)
        let truncated = size > UInt64(historyBytes)
        let offset = truncated ? size - UInt64(historyBytes) : 0
        var parser = ClaudeTranscriptParser(sessionID: sessionID, collectEntries: true, assumeOpenTurn: truncated)
        for line in ClaudeJSONL.lines(ClaudeJSONL.read(path: path, offset: offset, length: Int(size - offset)), dropFirst: truncated) { parser.consume(line) }
        return (parser.entries, truncated)
    }
}

// MARK: - Status hooks (primary live evidence)

public enum ClaudeHookState: String, Codable, Sendable {
    case running, permission, input, idle, ended
}

public struct ClaudeHookRecord: Equatable, Sendable {
    public var sessionID: String
    public var pid: Int32
    public var timestamp: Date
    public var event: String
    public var state: ClaudeHookState?
    public var cwd: String?
    public var transcriptPath: String?

    /// Maps a documented hook event to an attention state. Unknown events establish nothing.
    public static func state(event: String, notificationType: String?, message: String?, source: String?) -> ClaudeHookState? {
        switch event {
        case "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "SubagentStart", "SubagentStop", "PreCompact", "PostCompact":
            return .running
        case "PermissionRequest": return .permission
        case "Notification":
            switch notificationType {
            case "permission_prompt": return .permission
            case "elicitation_dialog": return .input
            case "idle_prompt": return .idle
            case nil:
                // Older Claude Code versions sent only a message.
                let text = (message ?? "").lowercased()
                if text.contains("permission") { return .permission }
                if text.contains("waiting for your input") { return .idle }
                return nil
            default: return nil
            }
        case "Stop", "StopFailure": return .idle
        case "SessionStart": return source == "compact" ? .running : .idle
        case "SessionEnd": return .ended
        default: return nil
        }
    }

    public static func parse(_ data: Data) -> ClaudeHookRecord? {
        guard let object = ClaudeJSONL.object(data), let event = object["event"] as? [String: Any],
              let sessionID = event["session_id"] as? String, let name = event["hook_event_name"] as? String else { return nil }
        let pid = (object["pid"] as? NSNumber)?.int32Value ?? 0
        let ts = (object["ts"] as? NSNumber)?.doubleValue ?? 0
        return ClaudeHookRecord(sessionID: sessionID, pid: pid, timestamp: Date(timeIntervalSince1970: ts), event: name,
                                state: state(event: name, notificationType: event["notification_type"] as? String,
                                             message: event["message"] as? String, source: event["source"] as? String),
                                cwd: event["cwd"] as? String, transcriptPath: event["transcript_path"] as? String)
    }
}

// MARK: - Internal runtime files (fallback evidence)

public struct ClaudeProcessRecord: Equatable, Sendable {
    public var pid: Int32
    public var sessionID: String
    public var cwd: String?
    public var status: String?
    public var name: String?
    public var nameIsDerived: Bool
    public var kind: String?
    public var jobID: String?
    public static func parse(_ data: Data) -> ClaudeProcessRecord? {
        guard let o = ClaudeJSONL.object(data), let pid = (o["pid"] as? NSNumber)?.int32Value, let id = o["sessionId"] as? String else { return nil }
        return ClaudeProcessRecord(pid: pid, sessionID: id, cwd: o["cwd"] as? String, status: o["status"] as? String, name: o["name"] as? String,
                                   nameIsDerived: (o["nameSource"] as? String) == "derived", kind: o["kind"] as? String, jobID: o["jobId"] as? String)
    }
}

public struct ClaudeJobRecord: Equatable, Sendable {
    public var shortID: String
    public var sessionID: String
    public var state: String?
    public var name: String?
    public var cwd: String?
    public static func parse(_ data: Data, shortID: String) -> ClaudeJobRecord? {
        guard let o = ClaudeJSONL.object(data), let id = o["sessionId"] as? String else { return nil }
        return ClaudeJobRecord(shortID: shortID, sessionID: id, state: o["state"] as? String, name: o["name"] as? String, cwd: o["cwd"] as? String)
    }
}

// MARK: - State derivation

public struct ClaudeLiveState: Equatable, Sendable {
    public var execution: Execution
    public var requests: [String: RequestKind]
    public var evidence: ClaudeEvidence
    public var isLive: Bool
    /// The hook record contradicts a transcript that kept being written: hooks may be broken.
    public var hooksLagging = false
}

public enum ClaudeStatus {
    public static let lagTolerance: TimeInterval = 90

    public static func derive(hook: ClaudeHookRecord?, process: ClaudeProcessRecord?, job: ClaudeJobRecord?,
                              transcript: ClaudeTranscriptSummary?, transcriptModified: Date?, isAlive: (Int32) -> Bool) -> ClaudeLiveState {
        var state: ClaudeLiveState
        if let hook, let hookState = hook.state, hookState != .ended, hook.pid > 0, isAlive(hook.pid) {
            switch hookState {
            case .running: state = .init(execution: .running, requests: [:], evidence: .hooks, isLive: true)
            case .permission: state = .init(execution: .running, requests: ["hook": .permission], evidence: .hooks, isLive: true)
            case .input: state = .init(execution: .running, requests: ["hook": .input], evidence: .hooks, isLive: true)
            case .idle, .ended: state = .init(execution: .idle, requests: [:], evidence: .hooks, isLive: true)
            }
            // Self-check: transcript activity well after the last hook event while hooks say idle.
            if hookState == .idle, transcript?.turnOpen == true, let modified = transcriptModified,
               modified.timeIntervalSince(hook.timestamp) > lagTolerance {
                state = .init(execution: .running, requests: [:], evidence: .transcript, isLive: true, hooksLagging: true)
            }
        } else if let process, process.pid > 0, isAlive(process.pid) {
            switch process.status {
            case "busy": state = .init(execution: .running, requests: [:], evidence: .internalFiles, isLive: true)
            case "idle": state = .init(execution: .idle, requests: [:], evidence: .internalFiles, isLive: true)
            default:
                // An unrecognized status (format changed after an update) proves nothing.
                state = .init(execution: .unknown, requests: [:], evidence: .internalFiles, isLive: true)
            }
        } else {
            // No live process: the transcript's terminal state is the saved state.
            state = .init(execution: .idle, requests: [:], evidence: .transcript, isLive: false)
        }
        // A background job that ended its turn with a question waits for the user.
        if job?.state == "blocked", state.execution != .running {
            state.requests["job"] = .input
            if state.execution == .unknown { state.execution = .idle }
        }
        return state
    }
}

// MARK: - Projects

public enum ClaudeProjects {
    /// Worktree sessions belong to their repository's project.
    public static func root(for cwd: String) -> String {
        for marker in ["/.claude/worktrees/", "/.codex/worktrees/"] {
            if let range = cwd.range(of: marker) { return String(cwd[..<range.lowerBound]) }
        }
        return cwd
    }
    public static func projectID(for cwd: String) -> String? {
        cwd.isEmpty ? nil : "cwd:" + root(for: cwd)
    }
    /// Claude Code stores each session under ~/.claude/projects/<key>, where the key is the launch folder
    /// with every non-alphanumeric character replaced by "-".
    public static func key(for path: String) -> String {
        String(path.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) && $0.isASCII ? Character($0) : "-" })
    }

    /// Finds the existing folder whose key equals `key` by walking the file system from "/"
    /// (keys are lossy, so each level is matched against real directory names). Used when a
    /// transcript's recorded folder was moved: Claude Code keeps the history under the new key.
    public static func resolve(key historyKey: String, fileManager: FileManager = .default) -> String? {
        func walk(_ dir: String, _ rest: Substring) -> String? {
            if rest.isEmpty { return dir }
            guard let entries = try? fileManager.contentsOfDirectory(atPath: dir) else { return nil }
            for entry in entries.sorted(by: { $0.count > $1.count }) {
                let k = key(for: entry)
                guard rest.hasPrefix(k) else { continue }
                let after = rest.dropFirst(k.count)
                let child = (dir as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: child, isDirectory: &isDir), isDir.boolValue else { continue }
                if after.isEmpty { return child }
                if after.hasPrefix("-"), let found = walk(child, after.dropFirst()) { return found }
            }
            return nil
        }
        guard historyKey.hasPrefix("-") else { return nil }
        return walk("/", historyKey.dropFirst())
    }

    /// The recorded folder if it still exists; otherwise the folder that the history location points to.
    public static func currentFolder(recorded: String, historyKey: String, fileManager: FileManager = .default) -> String {
        if !recorded.isEmpty, fileManager.fileExists(atPath: recorded) { return recorded }
        if let resolved = resolve(key: historyKey, fileManager: fileManager) {
            // A subfolder of the old launch folder keeps its relative part when it exists at the new place.
            if !recorded.isEmpty {
                let oldRoot = recorded.split(separator: "/").reduce(into: [String]()) { $0.append(($0.last.map { $0 + "/" } ?? "/") + $1) }
                    .first { key(for: $0) == historyKey }
                if let oldRoot, recorded.hasPrefix(oldRoot) {
                    let candidate = resolved + recorded.dropFirst(oldRoot.count)
                    if fileManager.fileExists(atPath: candidate) { return candidate }
                }
            }
            return resolved
        }
        return recorded
    }

    /// Sessions started in the home folder usually `cd` into a project. This picks the project they
    /// mostly worked in, so they are grouped with it; `nil` keeps the launch folder. Internal folders
    /// (hidden ones and ~/Library) never count; the project needs at least 10% of the session's lines. `relocate` maps folders that were moved since.
    /// `knownRoots` are other sessions' launch folders: the nearest one (or a git root) above the
    /// working folder becomes the project.
    /// Sessions started in a folder that holds other projects (`containers`, e.g. a work folder with
    /// several products) are regrouped the same way.
    public static func workFolder(launch: String, cwdCounts: [String: Int], home: String = NSHomeDirectory(),
                                  knownRoots: Set<String> = [], containers: Set<String> = [],
                                  relocate: (String) -> String? = { _ in nil },
                                  fileManager: FileManager = .default) -> String? {
        guard !home.isEmpty, launch == home || containers.contains(launch) else { return nil }
        var totals: [String: Int] = [:]
        let all = cwdCounts.values.reduce(0, +)
        for (recorded, count) in cwdCounts {
            let path = root(for: recorded)
            guard path != launch, path.hasPrefix(home + "/"), let first = path.dropFirst(home.count + 1).split(separator: "/").first,
                  !first.hasPrefix("."), first != "Library" else { continue }
            guard let current = fileManager.fileExists(atPath: path) ? path : relocate(path) else { continue }
            totals[projectRoot(of: current, home: home, knownRoots: knownRoots, fileManager: fileManager), default: 0] += count
        }
        guard let best = totals.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }),
              best.value >= 3, Double(best.value) >= 0.1 * Double(all) else { return nil }
        return best.key
    }

    /// The project a working folder belongs to: the nearest folder at or above it that another session
    /// was started in, otherwise the nearest git root, otherwise the folder itself.
    public static func projectRoot(of folder: String, home: String, knownRoots: Set<String>, fileManager: FileManager = .default) -> String {
        var ancestors: [String] = []
        var dir = folder
        while dir.hasPrefix(home + "/") { ancestors.append(dir); dir = (dir as NSString).deletingLastPathComponent }
        return ancestors.first(where: knownRoots.contains) ?? ancestors.first { fileManager.fileExists(atPath: $0 + "/.git") } ?? folder
    }

    /// Maps a folder that no longer exists to where it lives now: first through moves already known
    /// from other sessions (old launch folder → current one), then by looking for its first missing
    /// folder name a few levels below home. Returns the deepest existing part, or `nil`.
    public static func relocate(_ path: String, moves: [String: String], home: String,
                                search: (String) -> String?) -> String? {
        var target: String?
        if let old = moves.keys.filter({ path == $0 || path.hasPrefix($0 + "/") }).max(by: { $0.count < $1.count }), let new = moves[old] {
            target = new + path.dropFirst(old.count)
        } else {
            var dir = home
            for part in path.dropFirst(home.count + 1).split(separator: "/").map(String.init) {
                let next = dir + "/" + part
                if FileManager.default.fileExists(atPath: next) { dir = next; continue }
                guard let found = search(part) else { return nil }
                target = found + path.dropFirst(next.count)
                break
            }
        }
        guard var candidate = target else { return nil }
        while !FileManager.default.fileExists(atPath: candidate) {
            let parent = (candidate as NSString).deletingLastPathComponent
            guard parent.hasPrefix(home + "/") else { return nil }
            candidate = parent
        }
        return candidate == home ? nil : candidate
    }

    /// Finds a folder named `name` up to `depth` levels below home, skipping hidden folders and ~/Library.
    public static func findFolder(named name: String, home: String, depth: Int = 3, fileManager: FileManager = .default) -> String? {
        var level = [home]
        for _ in 0..<depth {
            var next: [String] = []
            for dir in level {
                for entry in ((try? fileManager.contentsOfDirectory(atPath: dir)) ?? []).sorted() where !entry.hasPrefix(".") {
                    if dir == home && entry == "Library" { continue }
                    let child = dir + "/" + entry
                    var isDir: ObjCBool = false
                    guard fileManager.fileExists(atPath: child, isDirectory: &isDir), isDir.boolValue else { continue }
                    if entry == name { return child }
                    next.append(child)
                }
            }
            level = next
        }
        return nil
    }

    public static func name(for root: String, home: String = NSHomeDirectory()) -> String {
        if root == home { return "~ (home)" }
        return URL(fileURLWithPath: root).lastPathComponent
    }
}

/// Optional user rules that name projects and say what belongs to them, read from
/// `claude-project-rules.json`. Without the file, projects are plain folders.
public struct ClaudeProjectRules: Codable, Equatable, Sendable {
    public struct Project: Codable, Equatable, Sendable {
        public var name: String
        /// The project's folder; `~` is expanded. Sessions working at or below it belong here.
        public var folder: String
        /// More folders that belong to the same project.
        public var include: [String]?
        /// Words in a session's title or first prompts that place a session with no folder of its own here.
        public var keywords: [String]?
        /// Subfolders become their own projects; the rule then only names what is directly in it.
        public var split: Bool?
        public init(name: String, folder: String, include: [String]? = nil, keywords: [String]? = nil, split: Bool? = nil) {
            self.name = name; self.folder = folder; self.include = include; self.keywords = keywords; self.split = split
        }
    }
    public var projects: [Project]
    public init(projects: [Project]) { self.projects = projects }

    public static func load(_ url: URL, home: String = NSHomeDirectory()) -> ClaudeProjectRules? {
        guard let data = try? Data(contentsOf: url), var rules = try? JSONDecoder().decode(ClaudeProjectRules.self, from: data) else { return nil }
        let expand = { (p: String) in p == "~" ? home : p.hasPrefix("~/") ? home + p.dropFirst(1) : p }
        for i in rules.projects.indices {
            rules.projects[i].folder = expand(rules.projects[i].folder)
            rules.projects[i].include = rules.projects[i].include?.map(expand)
        }
        return rules
    }

    /// Folders that hold other projects: a session started there is grouped by where it worked.
    public var containers: Set<String> {
        var result: Set<String> = []
        let folders = projects.flatMap { [$0.folder] + ($0.include ?? []) }
        for project in projects {
            if project.split == true || folders.contains(where: { $0.hasPrefix(project.folder + "/") }) { result.insert(project.folder) }
        }
        return result
    }

    /// The project (id folder, name) for a working folder, by the longest matching folder.
    public func project(forFolder folder: String) -> (folder: String, name: String)? {
        var best: (rule: Project, matched: String)?
        for rule in projects {
            for candidate in [rule.folder] + (rule.include ?? []) where folder == candidate || folder.hasPrefix(candidate + "/") {
                if best == nil || candidate.count > best!.matched.count { best = (rule, candidate) }
            }
        }
        guard let best else { return nil }
        if best.rule.split == true, best.matched == best.rule.folder, folder != best.rule.folder,
           let child = folder.dropFirst(best.rule.folder.count + 1).split(separator: "/").first {
            let sub = best.rule.folder + "/" + child
            return (sub, String(child))
        }
        return (best.rule.folder, best.rule.name)
    }

    /// The project whose keywords appear most often (distinct words) in `text`; ties go to the earlier rule.
    public func project(forText text: String) -> (folder: String, name: String)? {
        let lower = text.lowercased()
        var best: (Project, Int)?
        for rule in projects {
            let hits = (rule.keywords ?? []).filter { !$0.isEmpty && lower.contains($0.lowercased()) }.count
            if hits > 0, hits > (best?.1 ?? 0) { best = (rule, hits) }
        }
        return best.map { ($0.0.folder, $0.0.name) }
    }
}

/// Decides which project a session belongs to (without manual choices): rules by folder, the folder a
/// home- or container-started session worked in, keywords for sessions that never left such a folder.
public struct ClaudeGrouping {
    public let home: String
    public let rules: ClaudeProjectRules
    public let containers: Set<String>
    public let knownRoots: Set<String>
    public let relocate: (String) -> String?
    public init(home: String, rules: ClaudeProjectRules, launchFolders: [String], relocate: @escaping (String) -> String? = { _ in nil }) {
        self.home = home; self.rules = rules; self.relocate = relocate
        containers = rules.containers
        var known = Set(launchFolders.filter { !$0.isEmpty && $0 != home }.map(ClaudeProjects.root(for:)))
        for rule in rules.projects where rule.split != true { known.formUnion([rule.folder] + (rule.include ?? [])) }
        knownRoots = known
    }
    public func name(forProjectID id: String) -> String {
        let folder = String(id.dropFirst(4))
        return rules.projects.first { $0.folder == folder }?.name ?? ClaudeProjects.name(for: ClaudeProjects.root(for: folder), home: home)
    }
    public func workFolder(launch: String, summary: ClaudeTranscriptSummary) -> String {
        let counts = summary.cwdCounts.merging(summary.pathCounts, uniquingKeysWith: +)
        return ClaudeProjects.workFolder(launch: launch, cwdCounts: counts, home: home, knownRoots: knownRoots, containers: containers, relocate: relocate) ?? launch
    }
    /// Project id ("cwd:<folder>") for a session whose folder work was computed by `workFolder`.
    public func projectID(work: String, summary: ClaudeTranscriptSummary) -> String? {
        var chosen = rules.project(forFolder: ClaudeProjects.root(for: work))?.folder
        if work == home || containers.contains(work) {
            let text = [summary.customTitle, summary.aiTitle, summary.agentName].compactMap { $0 }.joined(separator: "\n") + "\n" + summary.promptSample
            // In a container, keywords may only pick a project inside it (in ~, any project).
            if let byText = rules.project(forText: text), work == home || byText.folder.hasPrefix(work + "/") { chosen = byText.folder }
        }
        if let chosen { return "cwd:" + chosen }
        return ClaudeProjects.projectID(for: work)
    }
}

// MARK: - Hook installation

public enum ClaudeHookInstaller {
    public static let marker = "session-canvas-status-hook"
    public static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Notification", "Stop", "SubagentStop", "PreCompact", "SessionEnd"]

    public static func script(statusDirectory: String) -> String {
        """
        #!/bin/sh
        # \(marker) v1 — written by Session Canvas. Records the latest Claude Code hook event
        # per session so the canvas can show live state. Never blocks or alters Claude Code.
        dir='\(statusDirectory.replacingOccurrences(of: "'", with: "'\\''"))'
        payload=$(cat)
        sid=$(printf '%s' "$payload" | tr -d '\\n' | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\\([A-Za-z0-9._-]*\\)".*/\\1/p')
        [ -n "$sid" ] || exit 0
        mkdir -p "$dir" 2>/dev/null || exit 0
        pid=$PPID
        case "$(ps -o comm= -p "$pid" 2>/dev/null)" in
          *sh) pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ') ;;
        esac
        tmp="$dir/.$sid.$$"
        printf '{"v":1,"pid":%s,"ts":%s,"event":%s}\\n' "${pid:-0}" "$(date +%s)" "$payload" > "$tmp" 2>/dev/null && mv -f "$tmp" "$dir/$sid.json"
        exit 0

        """
    }

    static func isOurs(_ hook: [String: Any]) -> Bool {
        (hook["command"] as? String)?.contains(marker) == true
    }

    public static func isInstalled(settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return events.allSatisfy { event in
            ((hooks[event] as? [[String: Any]]) ?? []).contains { (($0["hooks"] as? [[String: Any]]) ?? []).contains(where: isOurs) }
        }
    }

    /// Returns settings with our hook groups added (idempotent); other hooks are preserved.
    public static func installing(into settings: [String: Any], command: String) -> [String: Any] {
        var result = removing(from: settings)
        var hooks = result["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var groups = hooks[event] as? [[String: Any]] ?? []
            var group: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": 5]]]
            switch event {
            case "PreToolUse", "PostToolUse", "PermissionRequest": group["matcher"] = "*"
            case "Notification": group["matcher"] = "permission_prompt|elicitation_dialog|idle_prompt"
            default: break
            }
            groups.append(group)
            hooks[event] = groups
        }
        result["hooks"] = hooks
        return result
    }

    public static func removing(from settings: [String: Any]) -> [String: Any] {
        var result = settings
        guard var hooks = result["hooks"] as? [String: Any] else { return result }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept: [[String: Any]] = groups.compactMap { group in
                guard let inner = group["hooks"] as? [[String: Any]] else { return group }
                let filtered = inner.filter { !isOurs($0) }
                if filtered.isEmpty { return nil }
                var copy = group; copy["hooks"] = filtered; return copy
            }
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }
        if hooks.isEmpty { result.removeValue(forKey: "hooks") } else { result["hooks"] = hooks }
        return result
    }
}
