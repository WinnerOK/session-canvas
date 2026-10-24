import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> JSONValue { if case .object(let v) = self { return v[key] ?? .null }; return .null }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var number: Double? { if case .number(let v) = self { return v }; return nil }
    public var array: [JSONValue] { if case .array(let v) = self { return v }; return [] }
    public var object: [String: JSONValue] { if case .object(let v) = self { return v }; return [:] }
}

public enum CodexWire {
    public static func session(_ value: JSONValue, live: Bool) throws -> Session {
        guard let id = value["id"].string else { throw CanvasError.message("Codex returned a session without an identity.") }
        var execution: Execution = .unknown
        var requests: [String: RequestKind] = [:]
        if live {
            switch value["status"]["type"].string {
            case "idle": execution = .idle
            case "active":
                execution = .running
                for flag in value["status"]["activeFlags"].array.compactMap(\.string) {
                    if flag == "waitingOnApproval" { requests[flag] = .permission }
                    if flag == "waitingOnUserInput" { requests[flag] = .input }
                }
            default: break
            }
        }
        return Session(id: id, title: value["name"].string ?? "Untitled session", cwd: value["cwd"].string ?? "",
                       execution: execution, requests: requests,
                       latestResult: value["turns"].array.reversed().compactMap { result($0, sessionID: id) }.first,
                       updatedAt: Date(timeIntervalSince1970: value["updatedAt"].number ?? 0),
                       revision: String(value["updatedAt"].number ?? 0))
    }
    public static func result(_ turn: JSONValue, sessionID: String) -> SessionResult? {
        guard let turnID = turn["id"].string else { return nil }
        let outcome: Outcome
        switch turn["status"].string {
        case "completed": outcome = .completed
        case "failed": outcome = .failed
        case "interrupted": outcome = .stopped
        default: return nil
        }
        // Stable turn + outcome; never use arrival time as an acknowledgment key.
        let text = turn["items"].array.filter { $0["type"].string == "agentMessage" }.compactMap { $0["text"].string }.last
            ?? turn["error"]["message"].string ?? "This turn \(outcome.label.lowercased()). No response text was recorded."
        return SessionResult(id: "\(sessionID)/\(turnID)/\(outcome.rawValue)", outcome: outcome, text: text)
    }
    public static func history(_ turns: [JSONValue], sessionID: String) -> [HistoryEntry] {
        var entries: [HistoryEntry] = []
        for turn in turns {
            let turnID = turn["id"].string ?? "unknown"
            for item in turn["items"].array {
                let id = item["id"].string ?? UUID().uuidString
                switch item["type"].string {
                case "userMessage":
                    let text = item["content"].array.compactMap { $0["text"].string }.joined(separator: "\n")
                    if !text.isEmpty { entries.append(HistoryEntry(id: id, role: "You", text: text)) }
                case "agentMessage":
                    if let text = item["text"].string { entries.append(HistoryEntry(id: id, role: "Codex", text: text)) }
                case "plan":
                    if let text = item["text"].string { entries.append(HistoryEntry(id: id, role: "Plan", text: text)) }
                default: break // Do not render arbitrary tool payloads or hidden reasoning.
                }
            }
            if let result = result(turn, sessionID: sessionID) {
                entries.append(HistoryEntry(id: "result/\(turnID)", role: result.outcome.label, text: result.text, result: result))
            }
        }
        return entries
    }
}
