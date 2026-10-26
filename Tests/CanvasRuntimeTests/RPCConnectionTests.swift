import Foundation
import Testing
import CanvasCore
@testable import SessionCanvas

@Suite(.serialized) @MainActor
struct RPCConnectionTests {
    @Test func cancellingASilentReaderReleasesTheWorker() async throws {
        let pipe = Pipe()
        defer { try? pipe.fileHandleForWriting.close() }
        let observation = AsyncStream<Void>.makeStream()
        var reader: RPCStreamReader? = RPCStreamReader(handle: pipe.fileHandleForReading,
            onValue: { _ in observation.continuation.yield(()) },
            onEnd: { observation.continuation.finish() })
        weak var released = reader
        reader?.start()
        try pipe.fileHandleForWriting.write(contentsOf: Data("{}\n".utf8))
        var iterator = observation.stream.makeAsyncIterator()
        try #require(await iterator.next() != nil)
        try await Task.sleep(for: .milliseconds(30))
        reader?.cancel(); reader = nil
        for _ in 0..<150 {
            if released == nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(released == nil)
    }

    @Test func lineBufferHandlesFragmentsCoalescedFramesAndUTF8() throws {
        var buffer = RPCLineBuffer()
        let message = Data("Привет 👋\nsecond\npartial".utf8)
        #expect(try buffer.append(Data(message.prefix(3))).isEmpty)
        let lines = try buffer.append(Data(message.dropFirst(3)))
        #expect(lines.map { String(decoding: $0, as: UTF8.self) } == ["Привет 👋", "second"])
        #expect(try buffer.append(Data(" end\n\nlast".utf8)).map { String(decoding: $0, as: UTF8.self) } == ["partial end", ""])
        #expect(try buffer.append(Data(" line\n".utf8)).map { String(decoding: $0, as: UTF8.self) } == ["last line"])
    }

    @Test func frameLimitAppliesToCompleteAndIncompleteIndividualFrames() throws {
        var exact = RPCLineBuffer(maximumFrameBytes: 4)
        #expect(try exact.append(Data("1234".utf8)).isEmpty)
        #expect(try exact.append(Data("\n1234\n".utf8)).count == 2)
        var complete = RPCLineBuffer(maximumFrameBytes: 4)
        #expect(throws: (any Error).self) { try complete.append(Data("12345\n".utf8)) }
        var incomplete = RPCLineBuffer(maximumFrameBytes: 4)
        #expect(try incomplete.append(Data("1234".utf8)).isEmpty)
        #expect(throws: (any Error).self) { try incomplete.append(Data("5".utf8)) }
    }

    @Test func fragmentedRepliesAndCoalescedNotificationsStayOrdered() async throws {
        let fixture = try RPCFixture()
        defer { fixture.remove() }
        let rpc = RPCConnection()
        defer { rpc.stop() }
        var notices: [Int] = []
        rpc.onMessage = { value in if let n = value["params"]["order"].number { notices.append(Int(n)) } }
        try rpc.start(executable: fixture.executable.path, arguments: ["current"])
        for _ in 0..<2 {
            let result = try await rpc.request("split")
            #expect(result["text"].string == "Привет 👋")
        }
        for _ in 0..<100 {
            if notices.count == 4 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(notices == [1, 2, 1, 2])
    }

    @Test func replacingConnectionRejectsOldRepliesNotificationsAndEOF() async throws {
        let fixture = try RPCFixture()
        defer { fixture.remove() }
        let rpc = RPCConnection()
        defer { rpc.stop() }
        var owners: [String] = []
        var disconnects = 0
        rpc.onMessage = { value in if let owner = value["params"]["owner"].string { owners.append(owner) } }
        rpc.onDisconnect = { disconnects += 1 }
        try rpc.start(executable: fixture.executable.path, arguments: ["old"])
        let obsolete = Task { try await rpc.request("slow") }
        for _ in 0..<150 {
            if FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent("ready").path) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent("ready").path))
        try rpc.start(executable: fixture.executable.path, arguments: ["current"])
        #expect(try await rpc.request("split")["text"].string == "Привет 👋")
        do { _ = try await obsolete.value; Issue.record("An obsolete request must fail when its connection closes") }
        catch { }
        try await Task.sleep(for: .milliseconds(350))
        #expect(owners == ["current", "current"])
        #expect(disconnects == 0)
        #expect(try await rpc.request("split")["text"].string == "Привет 👋")
    }

    @Test func finalReplyIsDeliveredBeforeEOFDisconnect() async throws {
        let fixture = try RPCFixture()
        defer { fixture.remove() }
        let rpc = RPCConnection()
        defer { rpc.stop() }
        var disconnects = 0
        rpc.onDisconnect = { disconnects += 1 }
        try rpc.start(executable: fixture.executable.path, arguments: ["current"])
        #expect(try await rpc.request("last")["text"].string == "Привет 👋")
        for _ in 0..<100 {
            if disconnects == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(disconnects == 1)
        do { _ = try await rpc.request("afterEOF"); Issue.record("A closed connection must reject new requests") }
        catch { }
    }
}

private struct RPCFixture {
    let folder: URL
    var executable: URL { folder.appendingPathComponent("fixture") }
    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("canvas-rpc-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let script = #"""
        #!/usr/bin/python3
        import json, pathlib, signal, sys, time
        owner = sys.argv[1]
        if owner == "old": signal.signal(signal.SIGTERM, signal.SIG_IGN)
        def encode(value): return json.dumps(value, ensure_ascii=False).encode() + b'\n'
        def notice(order): return {"method":"fixture/event", "params":{"order":order, "owner":owner}}
        for line in sys.stdin:
            request = json.loads(line)
            result = {"id":request["id"], "result":{"text":"Привет 👋"}}
            if request["method"] == "slow":
                pathlib.Path(__file__).with_name("ready").touch()
                time.sleep(.2)
                sys.stdout.buffer.write(encode(notice(99)) + encode(result))
                sys.stdout.buffer.flush()
                break
            if request["method"] == "last":
                sys.stdout.buffer.write(encode(result))
                sys.stdout.buffer.flush()
                break
            wire = encode(notice(1)) + encode(result) + encode(notice(2))
            split = wire.index("Привет".encode()) + 1
            sys.stdout.buffer.write(wire[:split])
            sys.stdout.buffer.flush()
            time.sleep(.01)
            sys.stdout.buffer.write(wire[split:])
            sys.stdout.buffer.flush()
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }
    func remove() { try? FileManager.default.removeItem(at: folder) }
}
