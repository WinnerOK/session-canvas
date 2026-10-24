import Foundation

/// Compatibility reader for a local rollout explicitly identified by Codex's inventory.
/// It reads stored dialogue and terminal evidence only; it never infers live state.
public enum RolloutReader {
    public static func read(path: String, codexHome: String, sessionID: String) throws -> [HistoryEntry] {
        let file = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        let home = URL(fileURLWithPath: codexHome).resolvingSymlinksInPath().standardizedFileURL
        guard ["sessions", "archived_sessions"].contains(where: { file.path.hasPrefix(home.appendingPathComponent($0).path + "/") }), file.pathExtension == "jsonl" else {
            throw CanvasError.message("The history file is outside the connected source's session directories.")
        }
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: file) }
        catch { throw CanvasError.message("The saved history file is no longer available. Refresh the session list.") }
        defer { try? handle.close() }
        var parser = Parser(sessionID: sessionID), buffer = Data(), total = 0
        while let data = try handle.read(upToCount: 64 * 1024), !data.isEmpty {
            total += data.count
            guard total <= 128 * 1024 * 1024 else { throw CanvasError.message("This saved history exceeds the compatibility reader's 128 MB limit. Open it in Codex.") }
            buffer.append(data)
            while let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer.prefix(upTo: newline))
                buffer.removeSubrange(...newline)
                try parser.consume(line)
            }
            guard buffer.count <= 16 * 1024 * 1024 else { throw CanvasError.message("A history record is too large to display safely. Open it in Codex.") }
        }
        // An incomplete final line can be the writer's current append. Never parse it as completion.
        guard parser.verifiedIdentity else { throw CanvasError.message("The saved history could not be matched to this session.") }
        return parser.entries
    }

    public struct Parser {
        private let sessionID: String
        public private(set) var entries: [HistoryEntry] = []
        public private(set) var verifiedIdentity = false
        private var turnID: String?
        private var lineNumber = 0
        public init(sessionID: String) { self.sessionID = sessionID }
        public mutating func consume(_ line: Data) throws {
            lineNumber += 1
            guard let value = try? JSONDecoder().decode(JSONValue.self, from: line) else { return }
            let payload = value["payload"]
            if value["type"].string == "session_meta" {
                guard payload["id"].string == sessionID else { throw CanvasError.message("The saved history belongs to a different session.") }
                verifiedIdentity = true
                return
            }
            guard verifiedIdentity else { return }
            if value["type"].string == "event_msg" {
                switch payload["type"].string {
                case "task_started": turnID = payload["turn_id"].string
                case "task_complete", "turn_aborted", "task_failed":
                    guard let id = payload["turn_id"].string ?? turnID else { return }
                    let outcome: Outcome = payload["type"].string == "task_complete" ? .completed : payload["type"].string == "task_failed" ? .failed : .stopped
                    let text = payload["last_agent_message"].string ?? "This turn \(outcome.label.lowercased())."
                    let result = SessionResult(id: "\(sessionID)/\(id)/\(outcome.rawValue)", outcome: outcome, text: text)
                    if entries.last?.role == "Codex" && entries.last?.text == text { entries.removeLast() }
                    if !entries.contains(where: { $0.result?.id == result.id }) { entries.append(HistoryEntry(id: result.id, role: outcome.label, text: text, result: result)) }
                default: break
                }
            } else if value["type"].string == "response_item" {
                let type = payload["type"].string
                guard type == "message" || type == "agent_message" else { return }
                let role = type == "agent_message" ? "assistant" : payload["role"].string
                guard role == "user" || role == "assistant" else { return }
                let content = payload["content"].string ?? payload["content"].array.compactMap { item -> String? in
                    guard ["text", "input_text", "output_text"].contains(item["type"].string ?? "") else { return nil }
                    return item["text"].string
                }.joined(separator: "\n")
                guard !content.isEmpty else { return }
                entries.append(HistoryEntry(id: payload["id"].string ?? "\(sessionID)/line-\(lineNumber)", role: role == "user" ? "You" : "Codex", text: content))
            }
        }
    }
}
