import AppKit
import Testing
import CanvasCore
@testable import SessionCanvas

@Suite(.serialized)
@MainActor
struct ProjectMembershipTests {
    @Test(arguments: [false, true])
    func oldBackendConfirmationsCannotOverrideDesktopAfterRestart(desktopAssigned: Bool) async throws {
        let fixture = try MembershipFixture()
        defer { fixture.remove() }
        if desktopAssigned { try fixture.desktopMembership("a") }
        try fixture.patch(["projectId": "server-b"])
        let source = CodexSource(mode: .history, settings: fixture.settings, observeDesktop: false)
        defer { source.close() }
        try await source.connect()
        var cached = try #require(try await source.snapshot().sessions.first { $0.id == "existing" })
        let catalog = try #require(try DesktopProjectCatalog.read(codexHome: fixture.folder.path))
        cached.projectID = "b"
        cached.projectMembershipConfirmation = ProjectMembershipConfirmation(desktopRevision: catalog.membershipRevision(for: cached.id), serverProjectID: "server-b")
        cached.latestResult = SessionResult(id: "reviewed-result", outcome: .completed, text: "Retained result")
        var workspace = Workspace(); workspace.sessions = [cached]
        let database = try CanvasDatabase(path: fixture.folder.appendingPathComponent("old-confirmation.sqlite").path)
        try database.save(workspace, source: source.sourceID)
        let restored = try database.load(source: source.sourceID).sessions
        #expect(restored.first?.projectMembershipConfirmation != nil)
        let restart = CodexSource(mode: .history, settings: fixture.settings, observeDesktop: false)
        defer { restart.close() }
        try await restart.connect()
        restart.restoreCachedResults(restored)
        let recovered = try #require(try await restart.snapshot().sessions.first { $0.id == cached.id })
        #expect(recovered.projectID == (desktopAssigned ? "a" : nil))
        #expect(recovered.projectMembershipConfirmation == nil)
        #expect(recovered.latestResult == cached.latestResult)
        #expect(try fixture.requests().allSatisfy { $0["method"].string != "thread/metadata/update" })
    }

    @Test func externalDesktopMovesRemainAuthoritativeOverStaleBackend() async throws {
        let fixture = try MembershipFixture()
        defer { fixture.remove() }
        try fixture.desktopMembership("a")
        try fixture.patch(["projectId": "server-b"])
        let source = CodexSource(mode: .history, settings: fixture.settings, observeDesktop: false)
        defer { source.close() }
        try await source.connect()
        var session = try #require(try await source.snapshot().sessions.first { $0.id == "existing" })
        #expect(session.projectID == "a")
        for target in ["b", nil, "a"] as [String?] {
            try fixture.desktopMembership(target)
            let next = try #require(try await source.snapshot().sessions.first { $0.id == session.id })
            #expect(next.projectID == target)
            #expect(next.revision != session.revision)
            #expect(next.id == session.id && next.cwd == session.cwd)
            session = next
        }
        #expect(try fixture.requests().allSatisfy { $0["method"].string != "thread/metadata/update" })
    }

    @Test func unavailableMovesPreserveLocalGeometryAndExposeDisabledMenu() async throws {
        let fixture = try MembershipFixture()
        defer { fixture.remove() }
        try fixture.desktopMembership("a")
        let model = ApplicationModel(demo: false, storagePath: ":memory:")
        model.settings = fixture.settings
        await model.connect()
        defer { model.shutdown() }
        model.showAllSessions()
        let session = try #require(model.workspace.sessions.first { $0.id == "existing" })
        model.selectLayer(model.layer(session))
        let placement = try #require(model.workspace.placements[session.id])
        let local = Point(placement.position.x + 8, placement.position.y + 8)
        model.moveNote(id: session.id, position: local, expectedRevision: session.revision)
        #expect(model.workspace.placements[session.id]?.position == local)
        #expect(model.errorMessage == nil)
        model.moveToProject(id: session.id, projectID: "b")
        #expect(model.workspace.sessions.first { $0.id == session.id }?.projectID == "a")
        #expect(model.workspace.placements[session.id]?.position == local)
        #expect(model.errorMessage?.contains("Move the chat in Codex") == true)
        _ = NSApplication.shared
        let canvas = CanvasNSView(model: model)
        canvas.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        canvas.update()
        let screen = model.workspace.viewport.screen(try #require(model.workspace.placements[session.id]).center)
        let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: canvas.convert(NSPoint(x: screen.x, y: screen.y), to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let actions = try #require(canvas.menu(for: event)?.items.first { $0.title == "Move to project" }?.submenu)
        #expect(actions.items.allSatisfy { !$0.isEnabled })
        #expect(try fixture.requests().allSatisfy { $0["method"].string != "thread/metadata/update" })
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SESSION_CANVAS_TEST_REAL_SOURCE"] == "1"))
    func installedDesktopMembershipReadbackRejectsBackendOnlySupport() async throws {
        let source = CodexSource(mode: .history, settings: .defaults, observeDesktop: false, observedSessionIDs: [])
        defer { source.close() }
        try await source.connect()
        #expect(!source.canAssignProject)
        let home = String(source.sourceID.dropFirst("codex-local:".count))
        let catalog = try #require(try DesktopProjectCatalog.read(codexHome: home))
        let snapshot = try await source.snapshot()
        let session = try #require(snapshot.sessions.sorted { $0.id < $1.id }.first {
            catalog.allowsLocalMembership(for: $0.id) && catalog.membershipRevision(for: $0.id) != "unassigned"
        })
        let actual = session.projectID
        var old = session
        let other = try #require(catalog.projects.first { $0.id != actual })
        old.projectID = other.id
        old.projectMembershipConfirmation = ProjectMembershipConfirmation(desktopRevision: catalog.membershipRevision(for: old.id), serverProjectID: catalog.serverProjectID(for: other.id))
        source.restoreCachedResults([old])
        let recovered = try #require(try await source.snapshot().sessions.first { $0.id == session.id })
        #expect(recovered.projectID == actual)
        #expect(recovered.projectMembershipConfirmation == nil)
        #expect(recovered.cwd == session.cwd)
        print("Installed desktop membership matches the source; no mutation or desktop observation requested.")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SESSION_CANVAS_TEST_REAL_SOURCE"] == "1"))
    func installedServerMetadataDoesNotEnableDesktopProjectMoves() async throws {
        let home = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("canvas-membership-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let wrapper = home.appendingPathComponent("codex-isolated")
        let script = #"""
        #!/usr/bin/python3
        import os, pathlib, sys
        home = str(pathlib.Path(__file__).parent)
        os.environ["CODEX_HOME"] = home
        os.environ["CODEX_SQLITE_HOME"] = home
        # Finder-launched Canvas has no parent Codex originator override.
        os.environ.pop("CODEX_INTERNAL_ORIGINATOR_OVERRIDE", None)
        executable = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        os.execv(executable, [executable] + sys.argv[1:])
        """#
        try script.write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
        let rpc = RPCConnection()
        defer { rpc.stop() }
        var connectedHome = ""
        func connect() async throws {
            try rpc.start(executable: wrapper.path, arguments: ["app-server", "--listen", "stdio://"])
            let response = try await rpc.request("initialize", ["clientInfo": .object(["name": .string("session_canvas_membership_test"), "version": .string("0.1.0")]), "capabilities": .object(["experimentalApi": .bool(true)])])
            #expect(URL(fileURLWithPath: try #require(response["codexHome"].string)).resolvingSymlinksInPath() == home.resolvingSymlinksInPath())
            connectedHome = try #require(response["codexHome"].string)
            try rpc.notify("initialized")
        }
        try await connect()
        var projects: [String] = []
        for name in ["A", "B"] {
            let response = try await rpc.request("project/create", ["idempotencyKey": .string(UUID().uuidString), "name": .string(name), "roots": .array([.object(["path": .string(home.path)])])])
            projects.append(try #require(response["project"]["id"].string))
        }
        let created = try await rpc.request("thread/start", ["cwd": .string(connectedHome), "ephemeral": .bool(false)])["thread"]
        let id = try #require(created["id"].string)
        _ = try await rpc.request("thread/name/set", ["threadId": .string(id), "name": .string("Isolated existing session")])
        await rpc.stopAndWait()
        for projectID in projects + [""] {
            try await connect()
            let response = try await rpc.request("thread/metadata/update", ["threadId": .string(id), "projectId": .string(projectID)])["thread"]
            #expect(response["id"].string == id)
            #expect(response["projectId"].string == (projectID.isEmpty ? nil : projectID))
            #expect(response["cwd"] == created["cwd"])
            await rpc.stopAndWait()
            try await connect()
            let read = try await rpc.request("thread/read", ["threadId": .string(id), "includeTurns": .bool(false)])["thread"]
            #expect(read["projectId"].string == (projectID.isEmpty ? nil : projectID))
            #expect(read["id"].string == id)
            #expect(read["name"].string == "Isolated existing session")
            #expect(read["cwd"] == created["cwd"])
            #expect(read["turns"].array.isEmpty)
            await rpc.stopAndWait()
        }
        let metadata: [String: Any] = [
            "local-projects": ["a": ["id": "a", "name": "A", "rootPaths": [connectedHome]], "b": ["id": "b", "name": "B", "rootPaths": [connectedHome]]],
            "app-server-project-id-by-legacy-project-id-by-host": ["local:" + connectedHome: ["a": projects[0], "b": projects[1]]]]
        try JSONSerialization.data(withJSONObject: metadata).write(to: home.appendingPathComponent(".codex-global-state.json"))
        let bytes = try Data(contentsOf: home.appendingPathComponent(".codex-global-state.json"))
        let source = CodexSource(mode: .history, settings: ConnectionSettings(executable: wrapper.path, socket: "", nativeURLTemplate: "codex://threads/{id}"), observeDesktop: false)
        defer { source.close() }
        try await source.connect()
        // The actual server proved only SQLite metadata persistence. An isolated
        // home has no desktop which could confirm the visible project transfer.
        #expect(!source.canAssignProject)
        await #expect(throws: (any Error).self) {
            try await source.assign(sessionID: id, projectID: "b", revision: "")
        }
        #expect(try Data(contentsOf: home.appendingPathComponent(".codex-global-state.json")) == bytes)
    }
}

private struct MembershipFixture {
    let folder: URL
    let settings: ConnectionSettings
    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("canvas-membership-fixture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let executable = folder.appendingPathComponent("codex-fixture")
        settings = ConnectionSettings(executable: executable.path, socket: "", nativeURLTemplate: "codex://threads/{id}")
        let script = #"""
        #!/usr/bin/python3
        import json, pathlib, sys
        home = pathlib.Path(__file__).parent
        def thread(): return json.loads((home / "thread.json").read_text())
        for line in sys.stdin:
            req = json.loads(line)
            if "id" not in req: continue
            with (home / "requests.jsonl").open("a") as log: log.write(json.dumps(req) + "\n")
            method, params = req["method"], req.get("params", {})
            behavior = (home / "behavior").read_text() if (home / "behavior").exists() else "normal"
            error = None
            if method == "initialize": result = {"codexHome": str(home), "userAgent": "session_canvas/0.164.0-alpha.11.1 (Mac OS; arm64) dumb (session_canvas; 0.1.0)"}
            elif method == "project/list": result = {"data": []}
            elif method == "project/read": result = {"project": {"id": params["projectId"]}}
            elif method == "thread/list":
                anchors = [dict(id="anchor-" + key, name="Anchor " + key, cwd=str(home), updatedAt=1, projectId="server-" + key, status={"type": "notLoaded"}) for key in ["a", "b"]]
                result = {"data": [] if params.get("archived") else [thread()] + anchors}
            elif method == "thread/metadata/update":
                value = thread()
                if behavior not in ["reject", "ignore"]:
                    value["projectId"] = params["projectId"] or None
                    (home / "thread.json").write_text(json.dumps(value))
                (home / "mutated").touch()
                if behavior == "closed-applied": sys.exit(0)
                if behavior in ["reject", "lost-applied"]: error = {"code": -32000, "message": "fixture"}
                result = {"thread": value}
            elif method == "thread/read":
                result = {"thread": thread()}
                if behavior == "wrong-identity": result["thread"]["id"] = "other"
                if behavior == "unreadable" and (home / "mutated").exists(): error = {"code": -32000, "message": "fixture"}
            elif method == "thread/turns/list": result = {"data": []}
            else: result = {}
            print(json.dumps({"id": req["id"], **({"error": error} if error else {"result": result})}), flush=True)
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let thread: [String: Any] = ["id": "existing", "name": "Existing", "cwd": folder.path, "updatedAt": 1, "projectId": NSNull(), "status": ["type": "notLoaded"]]
        try JSONSerialization.data(withJSONObject: thread).write(to: folder.appendingPathComponent("thread.json"))
        try metadata()
    }
    func metadata(remote: Bool = false) throws {
        let state: [String: Any] = [
            "local-projects": ["a": ["id": "a", "name": "A"], "b": ["id": "b", "name": "B"]],
            "project-order": ["a", "b"], "projectless-thread-ids": ["existing"],
            "thread-project-membership-host-ids": remote ? ["existing": "remote-host"] : [:],
            "app-server-project-id-by-legacy-project-id-by-host": ["local:" + folder.path: ["a": "server-a", "b": "server-b"]]]
        try JSONSerialization.data(withJSONObject: state).write(to: folder.appendingPathComponent(".codex-global-state.json"))
    }
    func desktopMembership(_ projectID: String?) throws {
        let file = folder.appendingPathComponent(".codex-global-state.json")
        var state = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        state["projectless-thread-ids"] = projectID == nil ? ["existing"] : []
        state["thread-project-assignments"] = projectID.map { ["existing": ["projectKind": "local", "projectId": $0]] } ?? [:]
        try JSONSerialization.data(withJSONObject: state).write(to: file)
    }
    func patch(_ fields: [String: Any]) throws {
        let file = folder.appendingPathComponent("thread.json")
        var value = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        value.merge(fields) { _, new in new }
        try JSONSerialization.data(withJSONObject: value).write(to: file)
    }
    func behavior(_ name: String) throws { try name.write(to: folder.appendingPathComponent("behavior"), atomically: true, encoding: .utf8) }
    func requests() throws -> [JSONValue] {
        try String(contentsOf: folder.appendingPathComponent("requests.jsonl"), encoding: .utf8).split(separator: "\n").map { try JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
    }
    func remove() { try? FileManager.default.removeItem(at: folder) }
}
