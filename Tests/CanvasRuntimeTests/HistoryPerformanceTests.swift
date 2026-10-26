import Foundation
import Darwin
import Testing
import CanvasCore
@testable import SessionCanvas

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SESSION_CANVAS_TEST_HISTORY_PERFORMANCE"] == "1")) @MainActor
struct HistoryPerformanceTests {
    @Test(arguments: [0, 1, 2, 4]) func largeHistoryReplyKeepsMainActorResponsive(mebibytes: Int) async throws {
        let fixture = try HistoryPerformanceFixture(turnCount: 1, toolsPerTurn: mebibytes == 0 ? 0 : 1, outputBytes: mebibytes * 1024 * 1024)
        try await measure(fixture, expectedEntries: 3)
    }

    @Test func originalRichHistoryReplyKeepsMainActorResponsive() async throws {
        let fixture = try HistoryPerformanceFixture(turnCount: 12, toolsPerTurn: 128, outputBytes: 8192)
        try await measure(fixture, expectedEntries: 36)
    }

    private func measure(_ fixture: HistoryPerformanceFixture, expectedEntries: Int) async throws {
        defer { fixture.remove() }
        let source = CodexSource(mode: .history, settings: fixture.settings, observeDesktop: false)
        defer { source.close() }
        try await source.connect()
        let pulse = HistoryPulse()
        let timer = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(10))
                pulse.tick()
            }
        }
        defer { timer.cancel() }
        try await Task.sleep(for: .milliseconds(30))
        let start = ProcessInfo.processInfo.systemUptime, cpu = clock()
        let page = try await source.history(sessionID: "fixture", cursor: nil)
        pulse.tick()
        print("HISTORY_PERF bytes=\(fixture.byteCount) entries=\(page.entries.count) elapsed=\(ProcessInfo.processInfo.systemUptime - start) cpu=\(Double(clock() - cpu) / Double(CLOCKS_PER_SEC)) main_gap=\(pulse.maximumGap)")
        #expect(page.entries.count == expectedEntries)
        #expect(pulse.maximumGap < 0.25)
    }
}

@MainActor private final class HistoryPulse {
    private var previous = ProcessInfo.processInfo.systemUptime
    private(set) var maximumGap: TimeInterval = 0
    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        maximumGap = max(maximumGap, now - previous)
        previous = now
    }
}

private struct HistoryPerformanceFixture {
    let folder: URL
    let settings: ConnectionSettings
    let byteCount: Int
    init(turnCount: Int, toolsPerTurn: Int, outputBytes: Int) throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("canvas-history-perf-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let executable = folder.appendingPathComponent("fixture")
        settings = ConnectionSettings(executable: executable.path, socket: "", nativeURLTemplate: "codex://threads/{id}")
        var turns: [[String: Any]] = []
        for turn in 0..<turnCount {
            var items: [[String: Any]] = [["id": "u-\(turn)", "type": "userMessage", "content": [["text": "Synthetic request"]]]]
            for tool in 0..<toolsPerTurn {
                items.append(["id": "tool-\(turn)-\(tool)", "type": "commandExecution", "aggregatedOutput": String(repeating: "x", count: outputBytes)])
            }
            items.append(["id": "a-\(turn)", "type": "agentMessage", "text": "Synthetic result"])
            turns.append(["id": "t-\(turn)", "status": "completed", "items": items])
        }
        let reply = try JSONSerialization.data(withJSONObject: ["data": turns, "nextCursor": NSNull()])
        byteCount = reply.count
        try reply.write(to: folder.appendingPathComponent("reply.json"))
        let script = #"""
        #!/usr/bin/python3
        import json, pathlib, sys
        home = pathlib.Path(__file__).parent
        reply = (home / "reply.json").read_bytes()
        for line in sys.stdin:
            request = json.loads(line)
            if "id" not in request: continue
            method = request["method"]
            if method == "thread/turns/list":
                sys.stdout.buffer.write(b'{"id":' + str(request["id"]).encode() + b',"result":' + reply + b'}\n')
                sys.stdout.buffer.flush()
            else:
                result = {"codexHome": str(home)} if method == "initialize" else {"data": []}
                print(json.dumps({"id": request["id"], "result": result}), flush=True)
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }
    func remove() { try? FileManager.default.removeItem(at: folder) }
}
