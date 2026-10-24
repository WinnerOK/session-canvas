import Foundation
import Testing
import CanvasCore
@testable import SessionCanvas

@Suite(.serialized) @MainActor
struct LiveStateTests {
    @Test func desktopRuntimeOverridesUnloadedInventoryAndUpdatesWithoutManualRefresh() async throws {
        let fixture = try LiveFixture()
        defer { fixture.remove() }
        try await fixture.waitUntilReady()
        let model = ApplicationModel(demo: false, storagePath: ":memory:")
        model.settings = fixture.settings
        defer { model.shutdown() }
        await model.connect()
        #expect(model.connected)
        #expect(await eventually { model.workspace.sessions.first?.execution == .running })
        await model.refresh()
        #expect(model.workspace.sessions.first?.execution == .running, "Metadata reporting notLoaded must not erase desktop activity")
        try fixture.update("approval")
        #expect(await eventually { model.workspace.sessions.first?.state(acknowledged: []) == .permission })
        try fixture.update("input")
        #expect(await eventually { model.workspace.sessions.first?.state(acknowledged: []) == .waiting })
        try fixture.update("completed")
        #expect(await eventually { model.workspace.sessions.first?.state(acknowledged: []) == .finished })
        #expect(model.workspace.sessions.first?.latestResult?.id == "live/turn/completed")
        fixture.server.terminate()
        #expect(await eventually { model.workspace.sessions.first?.execution == .unknown })
        try fixture.update("running")
        try fixture.restart()
        try await fixture.waitUntilReady()
        #expect(await eventually { model.workspace.sessions.first?.execution == .running })
        #expect(model.hasLiveState)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SESSION_CANVAS_TEST_REAL_SOURCE"] == "1"))
    func installedDesktopFeedsLiveStateIntoTheApplication() async throws {
        let model = ApplicationModel(demo: false, storagePath: ":memory:")
        model.settings = .defaults
        defer { model.shutdown() }
        await model.connect()
        #expect(await eventually { model.hasLiveState && model.workspace.sessions.contains { $0.execution == .running } })
        let live = model.workspace.sessions.filter { $0.execution != .unknown }
        print("Verified desktop feed: \(live.count) live sessions, \(live.filter { $0.execution == .running }.count) running.")
    }

    @Test func canonicalDesktopTurnsKeepTerminalIdentityAndPendingRequests() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"id":"s","threadRuntimeStatus":{"type":"active","activeFlags":[]},"requests":[{"id":9,"method":"item/commandExecution/requestApproval"}],"turnHistory":{"kind":"canonical","history":{"islands":[{"entries":[{"value":"older"},{"value":"newer"}]}],"entitiesByKey":{"newer":{"turnId":"new","status":"inProgress"},"older":{"turnId":"old","status":"completed","items":[{"type":"agentMessage","text":"Verified result"}]}}}}}"#.utf8))
        let observed = DesktopObservation(value)
        #expect(observed.execution == .running)
        #expect(observed.requests.values.contains(.permission))
        #expect(observed.result?.id == "s/old/completed")
        #expect(observed.result?.text == "Verified result")
        let patched = try DesktopObservation.patching(value, with: [.object(["op": .string("remove"), "path": .array([.string("requests"), .number(0)])])])
        #expect(DesktopObservation(patched).requests.isEmpty)
    }

    @Test func invalidPatchesCannotProduceAFalseRunningState() throws {
        let value = JSONValue.object(["threadRuntimeStatus": .object(["type": .string("idle")])])
        #expect(throws: (any Error).self) {
            try DesktopObservation.patching(value, with: [.object(["op": .string("replace"), "path": .array([.string("missing"), .string("type")]), "value": .string("active")])])
        }
        #expect(DesktopObservation(value).execution == .idle)
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<250 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}

@MainActor private final class LiveFixture {
    let folder: URL
    let settings: ConnectionSettings
    private(set) var server = Process()
    init() throws {
        folder = URL(fileURLWithPath: "/private/tmp/live-" + String(UUID().uuidString.prefix(8)))
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("ipc"), withIntermediateDirectories: true)
        let executable = folder.appendingPathComponent("codex-fixture")
        settings = ConnectionSettings(executable: executable.path, socket: "", nativeURLTemplate: "codex://threads/{id}")
        let cli = #"""
        #!/usr/bin/python3
        import json,pathlib,sys
        for line in sys.stdin:
            m=json.loads(line)
            if "id" not in m: continue
            result={"codexHome":str(pathlib.Path(__file__).parent)} if m["method"]=="initialize" else {"data":[{"id":"live","name":"Current session","source":"appServer","status":{"type":"notLoaded"}}],"nextCursor":None}
            print(json.dumps({"id":m["id"],"result":result}),flush=True)
        """#
        try cli.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let script = folder.appendingPathComponent("desktop.py")
        try Self.script.write(to: script, atomically: true, encoding: .utf8)
        try update("running")
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = [script.path]
        server.standardOutput = Pipe(); server.standardError = Pipe()
        try server.run()
    }
    func waitUntilReady() async throws {
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent("ready").path) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw CanvasError.message("Desktop fixture did not start")
    }
    func update(_ state: String) throws { try state.write(to: folder.appendingPathComponent("state"), atomically: true, encoding: .utf8) }
    func restart() throws {
        server.waitUntilExit()
        try FileManager.default.removeItem(at: folder.appendingPathComponent("ipc/ipc.sock"))
        try FileManager.default.removeItem(at: folder.appendingPathComponent("ready"))
        let next = Process()
        next.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        next.arguments = [folder.appendingPathComponent("desktop.py").path]
        next.standardOutput = Pipe(); next.standardError = Pipe()
        try next.run(); server = next
    }
    func remove() { if server.isRunning { server.terminate() }; try? FileManager.default.removeItem(at: folder) }
    private static let script = #"""
    import json,pathlib,select,socket,struct,time,uuid
    home=pathlib.Path(__file__).parent
    listener=socket.socket(socket.AF_UNIX)
    listener.bind(str(home/"ipc/ipc.sock")); listener.listen()
    (home/"ready").touch()
    conn,_=listener.accept()
    def send(v):
        data=json.dumps(v).encode(); frame=struct.pack("<I",len(data))+data
        for part in [frame[:2],frame[2:9],frame[9:]]:
            conn.sendall(part); time.sleep(.002)
    def read(n):
        b=b""
        while len(b)<n:
            c=conn.recv(n-len(b))
            if not c: raise SystemExit()
            b+=c
        return b
    def state():
        phase=(home/"state").read_text()
        flags={"approval":["waitingOnApproval"],"input":["waitingOnUserInput"]}.get(phase,[])
        return {"id":"live","title":"Current session","threadRuntimeStatus":{"type":"idle" if phase=="completed" else "active","activeFlags":flags},"requests":[],"turns":[{"turnId":"turn","status":"completed" if phase=="completed" else "inProgress","items":[]}]}
    revision=0; following=False; last=None
    while True:
        ready,_,_=select.select([conn],[],[],.03)
        if ready:
            m=json.loads(read(struct.unpack("<I",read(4))[0]))
            if m.get("method")=="initialize":
                send({"type":"response","method":"initialize","requestId":m["requestId"],"resultType":"success","result":{"clientId":"observer"}})
            if m.get("method")=="thread-stream-following-changed" and m.get("params",{}).get("conversationId")=="live":
                following=m["params"]["following"]
                if following: last=None
        current=state()
        if following and current!=last:
            change={"type":"snapshot","revision":revision,"conversationState":current} if last is None else {"type":"patches","baseRevision":revision-1,"revision":revision,"patches":[{"op":"replace","path":[k],"value":current[k]} for k in current if current[k]!=last[k]]}
            send({"type":"broadcast","method":"thread-stream-state-changed","version":11,"sourceClientId":"desktop-owner","params":{"hostId":"local","conversationId":"live","change":change}})
            last=current; revision+=1
    """#
}
