import Foundation
import Testing
@testable import CanvasCore

@Suite struct RolloutReaderTests {
    @Test func discoverySummaryUsesLatestTerminalEvidenceAndRejectsLaterWork() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        let file = home.appendingPathComponent("sessions/record.jsonl")
        let identity = #"{"type":"session_meta","payload":{"id":"s"}}"# + "\n"
        let terminal = #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"t","last_agent_message":"Done"}}"# + "\n"
        // The identity is beyond the bounded tail; only its verified first record is read.
        let padding = String(repeating: " ", count: 300000) + "\n"
        try (identity + padding + terminal).write(to: file, atomically: true, encoding: .utf8)
        let summary = try RolloutReader.summary(path: file.path, codexHome: home.path, sessionID: "s")
        #expect(summary.execution == .idle)
        #expect(summary.result?.id == "s/t/completed")
        let next = #"{"type":"event_msg","payload":{"type":"task_started","turn_id":"next"}}"# + "\n"
        try (identity + padding + terminal + next).write(to: file, atomically: true, encoding: .utf8)
        #expect(try RolloutReader.summary(path: file.path, codexHome: home.path, sessionID: "s").execution == .unknown)
        try (identity + terminal + next.trimmingCharacters(in: .newlines)).write(to: file, atomically: true, encoding: .utf8)
        #expect(try RolloutReader.summary(path: file.path, codexHome: home.path, sessionID: "s").execution == .unknown)
        try (identity + padding + terminal.trimmingCharacters(in: .newlines)).write(to: file, atomically: true, encoding: .utf8)
        #expect(try RolloutReader.summary(path: file.path, codexHome: home.path, sessionID: "s").execution == .unknown)
        #expect(throws: (any Error).self) { try RolloutReader.summary(path: file.path, codexHome: home.path, sessionID: "other") }
    }
    @Test func onlyVerifiedDialogueAndTerminalEvidenceAreDisplayed() throws {
        var parser = RolloutReader.Parser(sessionID: "s")
        try consume(#"{"type":"session_meta","payload":{"id":"s","base_instructions":"hidden instructions"}}"#, into: &parser)
        try consume(#"{"type":"event_msg","payload":{"type":"task_started","turn_id":"t"}}"#, into: &parser)
        try consume(#"{"type":"response_item","payload":{"type":"message","role":"developer","content":[{"type":"input_text","text":"hidden developer"}]}}"#, into: &parser)
        try consume(#"{"type":"response_item","payload":{"type":"reasoning","summary":[{"text":"hidden reasoning"}]}}"#, into: &parser)
        try consume(#"{"type":"response_item","payload":{"id":"u","type":"message","role":"user","content":[{"type":"input_text","text":"Please investigate"}]}}"#, into: &parser)
        try consume(#"{"type":"response_item","payload":{"id":"a","type":"message","role":"assistant","content":[{"type":"output_text","text":"What do you think?"}]}}"#, into: &parser)
        #expect(parser.entries.count == 2)
        #expect(parser.entries.allSatisfy { $0.result == nil })
        try consume(#"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"t","last_agent_message":"What do you think?"}}"#, into: &parser)
        #expect(parser.entries.count == 2)
        #expect(parser.entries.last?.result?.id == "s/t/completed")
        #expect(!parser.entries.contains { $0.text.contains("hidden") })
    }
    @Test func wrongSessionIdentityIsRejected() {
        var parser = RolloutReader.Parser(sessionID: "s")
        #expect(throws: (any Error).self) { try consume(#"{"type":"session_meta","payload":{"id":"different"}}"#, into: &parser) }
    }
    @Test func repeatingTerminalEventsDoesNotCreateAnotherResult() throws {
        var parser = RolloutReader.Parser(sessionID: "s")
        try consume(#"{"type":"session_meta","payload":{"id":"s"}}"#, into: &parser)
        let event = #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"t","last_agent_message":"Done"}}"#
        try consume(event, into: &parser); try consume(event, into: &parser)
        #expect(parser.entries.count == 1)
    }
    @Test func incompleteAppendDoesNotCreateAResult() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        let path = home.appendingPathComponent("sessions/record.jsonl")
        let content = #"{"type":"session_meta","payload":{"id":"s"}}"# + "\n" + #"{"type":"event_msg","payload":{"type":"task_complete","turn_id":"t"}}"#
        try Data(content.utf8).write(to: path)
        #expect(try RolloutReader.read(path: path.path, codexHome: home.path, sessionID: "s").isEmpty)
    }
    @Test func pathOutsideSourceAndEscapingSymlinkAreRejected() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        let outside = home.appendingPathComponent("outside.jsonl")
        try Data((#"{"type":"session_meta","payload":{"id":"s"}}"# + "\n").utf8).write(to: outside)
        #expect(throws: (any Error).self) { try RolloutReader.read(path: outside.path, codexHome: home.path, sessionID: "s") }
        let link = home.appendingPathComponent("sessions/link.jsonl")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        #expect(throws: (any Error).self) { try RolloutReader.read(path: link.path, codexHome: home.path, sessionID: "s") }
    }
    private func consume(_ text: String, into parser: inout RolloutReader.Parser) throws { try parser.consume(Data(text.utf8)) }
}
