import AppKit
import Testing
import CanvasCore
@testable import SessionCanvas

@Suite(.serialized)
@MainActor
struct ProjectMembershipTests {
    @Test func supportedMovesDoNotEraseDesktopProjectsWhenServerMembershipIsNull() async throws {
        let fixture = try MembershipFixture()
        defer { fixture.remove() }
        let file = fixture.folder.appendingPathComponent(".codex-global-state.json")
        var state = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        state["projectless-thread-ids"] = []
        state["thread-project-assignments"] = ["existing": ["projectKind": "local", "projectId": "a"]]
        try JSONSerialization.data(withJSONObject: state).write(to: file)
        let source = CodexSource(mode: .history, settings: fixture.settings, observeDesktop: false)
        defer { source.close() }
        try await source.connect()
        #expect(source.canAssignProject)
        let snapshot = try await source.snapshot(), sessions = snapshot.sessions
        #expect(sessions.first { $0.id == "existing" }?.projectID == "a")
        // Recover an existing Canvas snapshot flattened by the previous bug.
        let storage = fixture.folder.appendingPathComponent("canvas.sqlite").path
        var cached = Workspace()
        cached.reconcile(sessions: sessions, projects: snapshot.projects)
        for index in cached.sessions.indices { cached.sessions[index].projectID = nil }
        cached.viewport = Viewport(origin: Point(11, 17), zoom: 0.42)
        try CanvasDatabase(path: storage).save(cached, source: source.sourceID)
        let model = ApplicationModel(demo: false, storagePath: storage)
        model.settings = fixture.settings
        await model.connect()
        defer { model.shutdown() }
        model.showAllSessions()
        #expect(model.workspace.sessions.first { $0.id == "existing" }?.projectID == "a")
        #expect(model.visibleProjects.contains { $0.id == "a" })
        #expect(model.workspace.project(at: model.workspace.placements["existing"]!.center) == "a")
        #expect(model.workspace.viewport == cached.viewport)
        #expect(try fixture.requests().allSatisfy { $0["method"].string != "thread/metadata/update" })
    }

    @Test func verifiedMoveConfirmationDoesNotOverrideLaterDesktopChanges() async throws {
        let fixture = try MembershipFixture()
        defer { fixture.remove() }
        try fixture.desktopMembership("a")
        let source = CodexSource(mode: .history, settings: fixture.settings, observeDesktop: false)
        defer { source.close() }
        try await source.connect()
        var session = try #require(try await source.snapshot().sessions.first { $0.id == "existing" })
        session = try await source.assign(sessionID: session.id, projectID: "b", revision: session.revision)
        #expect(session.projectID == "b")
        #expect(session.projectMembershipConfirmation != nil)
        // Unrelated catalog edits do not invalidate this session's proof.
        let file = fixture.folder.appendingPathComponent(".codex-global-state.json")
        var state = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        state["thread-project-assignments"] = ["existing": ["projectKind": "local", "projectId": "a"],
                                               "unrelated": ["projectKind": "local", "projectId": "b"]]
        try JSONSerialization.data(withJSONObject: state).write(to: file)
        #expect(try await source.snapshot().sessions.first { $0.id == session.id }?.projectID == "b")
        try fixture.desktopMembership(nil)
        let changed = try #require(try await source.snapshot().sessions.first { $0.id == session.id })
        #expect(changed.projectID == nil)
        #expect(changed.projectMembershipConfirmation == nil)
        #expect(changed.revision != session.revision)
        // Old confirmation cannot regain authority after a restart.
        let restart = CodexSource(mode: .history, settings: fixture.settings, observeDesktop: false)
        defer { restart.close() }
        try await restart.connect()
        restart.restoreCachedResults([session])
        #expect(try await restart.snapshot().sessions.first { $0.id == session.id }?.projectID == nil)
        // Returning to an old legacy value cannot resurrect a discarded proof.
        try fixture.desktopMembership("a")
        #expect(try await source.snapshot().sessions.first { $0.id == session.id }?.projectID == "a")
        #expect(try await restart.snapshot().sessions.first { $0.id == session.id }?.projectID == "a")
    }

    @Test func moveSupportRequiresVerifiedDesktopVersion() {
        for version in ["0.164.0-alpha.11.1", "0.164.0", "0.165.0-alpha.1.0", "1.0.0"] {
            #expect(CodexSource.supportsProjectMoves(userAgent: "Codex Desktop/" + version + " (Mac OS; arm64)"))
            #expect(CodexSource.supportsProjectMoves(userAgent: "session_canvas/" + version + " (Mac OS; arm64) dumb (session_canvas; 0.1.0)"))
        }
        for agent in ["", "custom/1.0.0", "Codex Desktop/0.163.0-alpha.11.2", "Codex Desktop/0.164.0-alpha.10.9", "Codex Desktop/0.164.0-alpha.11.0", "session_canvas/0.163.0-alpha.11.2 (Mac OS) dumb (session_canvas; 0.1.0)", "session_canvas/0.1.0 (Mac OS)"] {
            #expect(!CodexSource.supportsProjectMoves(userAgent: agent))
        }
    }

    @Test(arguments: [false, true])
    func existingMembershipMovesRoundTripAndOverrideStaleDesktopCache(desktopAssigned: Bool) async throws {
        let fixture = try MembershipFixture()
        defer { fixture.remove() }
        if desktopAssigned { try fixture.desktopMembership("a") }
        let metadata = try Data(contentsOf: fixture.folder.appendingPathComponent(".codex-global-state.json"))
        let source = CodexSource(mode: .history, settings: fixture.settings, observeDesktop: false)
        defer { source.close() }
        try await source.connect()
        #expect(source.canAssignProject)
        var session = try #require(try await source.snapshot().sessions.first { $0.id == "existing" })
        let cwd = session.cwd
        let targets: [String?] = desktopAssigned ? ["b", nil, "a"] : ["a", "b", nil]
        for target in targets {
            let confirmed = try await source.assign(sessionID: session.id, projectID: target, revision: session.revision)
            #expect(confirmed.projectID == target)
            #expect(confirmed.id == session.id && confirmed.cwd == cwd)
            session = try #require(try await source.snapshot().sessions.first { $0.id == "existing" })
            #expect(session.projectID == target)
            let restart = CodexSource(mode: .history, settings: fixture.settings, observeDesktop: false)
            try await restart.connect()
            var saved = Workspace(); saved.sessions = [session]
            let database = try CanvasDatabase(path: fixture.folder.appendingPathComponent("confirmation.sqlite").path)
            try database.save(saved, source: source.sourceID)
            restart.restoreCachedResults(try database.load(source: source.sourceID).sessions)
            #expect(try await restart.snapshot().sessions.first { $0.id == "existing" }?.projectID == target)
            restart.close()
        }
        #expect(try Data(contentsOf: fixture.folder.appendingPathComponent(".codex-global-state.json")) == metadata)
        let requests = try fixture.requests()
        #expect(requests.filter { $0["method"].string == "thread/metadata/update" }.map { $0["params"]["projectId"].string } == targets.map { $0.map { "server-" + $0 } ?? "" })
        #expect(requests.allSatisfy { !["thread/start", "thread/resume", "turn/start", "thread/settings/update"].contains($0["method"].string ?? "") })
        #expect(requests.filter { $0["method"].string == "thread/metadata/update" }.allSatisfy { Set($0["params"].object.keys) == ["threadId", "projectId"] })
    }

    @Test(arguments: ["revision", "membership", "remote", "unknown-project", "wrong-identity"])
    func preflightRejectsStaleOrUnconfirmedMoves(_ reason: String) async throws {
        let fixture = try MembershipFixture()
        defer { fixture.remove() }
        let source = CodexSource(mode: .history, settings: fixture.settings, observeDesktop: false)
        defer { source.close() }
        try await source.connect()
        let session = try #require(try await source.snapshot().sessions.first { $0.id == "existing" })
        if reason == "revision" { try fixture.patch(["updatedAt": 2]) }
        if reason == "membership" { try fixture.patch(["projectId": "server-b"]) }
        if reason == "wrong-identity" { try fixture.behavior("wrong-identity") }
        if reason == "remote" { try fixture.metadata(remote: true) }
        await #expect(throws: (any Error).self) {
            try await source.assign(sessionID: session.id, projectID: reason == "unknown-project" ? "missing" : "a", revision: session.revision)
        }
        #expect(try fixture.requests().allSatisfy { $0["method"].string != "thread/metadata/update" })
    }

    @Test(arguments: ["reject", "ignore", "lost-applied", "closed-applied", "unreadable"])
    func mutationsAreVerifiedWithoutRepeatingThem(_ behavior: String) async throws {
        let fixture = try MembershipFixture()
        defer { fixture.remove() }
        let source = CodexSource(mode: .history, settings: fixture.settings, observeDesktop: false)
        defer { source.close() }
        try await source.connect()
        let session = try #require(try await source.snapshot().sessions.first { $0.id == "existing" })
        try fixture.behavior(behavior)
        if behavior == "lost-applied" {
            let confirmed = try await source.assign(sessionID: session.id, projectID: "a", revision: session.revision)
            #expect(confirmed.projectID == "a")
        } else {
            await #expect(throws: (any Error).self) { try await source.assign(sessionID: session.id, projectID: "a", revision: session.revision) }
        }
        #expect(try fixture.requests().filter { $0["method"].string == "thread/metadata/update" }.count == 1)
        if behavior == "closed-applied" || behavior == "unreadable" {
            try fixture.behavior("normal")
            let restarted = CodexSource(mode: .history, settings: fixture.settings, observeDesktop: false)
            try await restarted.connect()
            // An unverified outcome is not a stored confirmation. The backend write
            // survives, while discovery keeps the explicit desktop projectless fact.
            #expect(try await restarted.snapshot().sessions.first { $0.id == "existing" }?.projectID == nil)
            let stored = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: fixture.folder.appendingPathComponent("thread.json")))
            #expect(stored["projectId"].string == "server-a")
            restarted.close()
        }
    }

    @Test func modelDropConfirmsMembershipAndPersistsCoordinates() async throws {
        let fixture = try MembershipFixture()
        defer { fixture.remove() }
        let path = fixture.folder.appendingPathComponent("canvas.sqlite").path
        let model = ApplicationModel(demo: false, storagePath: path)
        model.settings = fixture.settings
        await model.connect()
        defer { model.shutdown() }
        #expect(model.canAssignProject)
        model.showAllSessions()
        let before = model.workspace.placements["existing"]
        let session = try #require(model.workspace.sessions.first { $0.id == "existing" })
        let region = try #require(model.workspace.regions["a"])
        let point = Point(region.x + Placement.width + 32, region.y + 64)
        model.moveNote(id: session.id, position: point, expectedRevision: session.revision)
        #expect(model.pendingSessions.contains(session.id))
        #expect(model.workspace.placements[session.id] == before)
        model.moveToProject(id: session.id, projectID: "b")
        for _ in 0..<100 {
            if model.pendingSessions.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.pendingSessions.isEmpty)
        #expect(model.errorMessage == nil)
        #expect(model.workspace.sessions.first { $0.id == session.id }?.projectID == "a")
        #expect(model.workspace.placements[session.id]?.position == point)
        #expect(try fixture.requests().filter { $0["method"].string == "thread/metadata/update" }.count == 1)
        model.shutdown()
        let restarted = ApplicationModel(demo: false, storagePath: path)
        restarted.settings = fixture.settings
        await restarted.connect()
        defer { restarted.shutdown() }
        #expect(restarted.workspace.sessions.first { $0.id == session.id }?.projectID == "a")
        #expect(restarted.workspace.placements[session.id]?.position == point)
        // The explicit project menu can target a filtered/empty region, unlike a
        // spatial drop onto an invisible area. Execution/review/viewport stay local.
        let index = try #require(restarted.workspace.sessions.firstIndex { $0.id == session.id })
        restarted.workspace.sessions[index].execution = .running
        restarted.workspace.sessions[index].requests = ["approval": .permission]
        restarted.workspace.sessions[index].latestResult = SessionResult(id: "old", outcome: .completed, text: "Prior result")
        restarted.acknowledgments[session.id] = ["old"]
        restarted.workspace.viewport = Viewport(origin: Point(11, 17), zoom: 1)
        let beforeMove = restarted.workspace.sessions[index], viewport = restarted.workspace.viewport
        restarted.setProjectVisible("b", false)
        _ = NSApplication.shared
        let canvas = CanvasNSView(model: restarted)
        canvas.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        canvas.update()
        let screen = viewport.screen(try #require(restarted.workspace.placements[session.id]).center)
        let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown,
            location: canvas.convert(NSPoint(x: screen.x, y: screen.y), to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let menu = try #require(canvas.menu(for: event))
        let move = try #require(menu.items.first { $0.title == "Move to project" }?.submenu)
        let item = try #require(move.items.first { $0.representedObject as? String == "b" })
        #expect(item.isEnabled)
        #expect(NSApp.sendAction(try #require(item.action), to: item.target, from: item))
        let pending = try #require(canvas.menu(for: event)?.items.first { $0.title == "Move to project" }?.submenu)
        #expect(pending.items.allSatisfy { !$0.isEnabled })
        for _ in 0..<100 {
            if restarted.pendingSessions.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let moved = try #require(restarted.workspace.sessions.first { $0.id == session.id })
        #expect(moved.projectID == "b")
        #expect(moved.cwd == beforeMove.cwd && moved.execution == beforeMove.execution && moved.requests == beforeMove.requests && moved.latestResult == beforeMove.latestResult)
        #expect(restarted.acknowledgments[session.id] == ["old"])
        #expect(restarted.workspace.viewport == viewport)
        #expect(restarted.errorMessage == nil)
    }

    @Test(arguments: ["reject", "external"])
    func failedModelDropReconcilesActualMembership(_ behavior: String) async throws {
        let fixture = try MembershipFixture()
        defer { fixture.remove() }
        let model = ApplicationModel(demo: false, storagePath: ":memory:")
        model.settings = fixture.settings
        await model.connect()
        defer { model.shutdown() }
        model.showAllSessions()
        let session = try #require(model.workspace.sessions.first { $0.id == "existing" })
        let before = model.workspace.placements[session.id]
        let others = model.workspace.placements.filter { $0.key != session.id }
        if behavior == "external" {
            try fixture.patch(["projectId": "server-b"])
            try fixture.desktopMembership("b")
        }
        else { try fixture.behavior("reject") }
        let region = try #require(model.workspace.regions["a"])
        model.moveNote(id: session.id, position: Point(region.x + 16, region.y + 64), expectedRevision: session.revision)
        for _ in 0..<100 {
            if model.pendingSessions.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.pendingSessions.isEmpty)
        #expect(model.errorMessage != nil)
        #expect(model.workspace.placements.filter { $0.key != session.id } == others)
        if behavior == "external" {
            #expect(model.workspace.sessions.first { $0.id == session.id }?.projectID == "b")
            #expect(model.workspace.project(at: model.workspace.placements[session.id]!.center) == "b")
            #expect(try fixture.requests().allSatisfy { $0["method"].string != "thread/metadata/update" })
        } else { #expect(model.workspace.placements[session.id] == before) }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SESSION_CANVAS_TEST_REAL_SOURCE"] == "1"))
    func installedServerPersistsExistingSessionProjectMovesInIsolation() async throws {
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
        let source = CodexSource(mode: .history, settings: ConnectionSettings(executable: wrapper.path, socket: "", nativeURLTemplate: "codex://threads/{id}"), observeDesktop: false)
        defer { source.close() }
        try await source.connect()
        #expect(source.canAssignProject)
        _ = try await source.snapshot()
        var session = try await source.create(title: "Isolated source membership", prompt: "", projectID: nil, cwd: connectedHome).session
        let original = session
        for target in ["a", "b", nil] as [String?] {
            session = try await source.assign(sessionID: session.id, projectID: target, revision: session.revision)
            #expect(session.projectID == target)
            #expect(session.id == original.id && session.cwd == original.cwd)
            #expect(try await source.snapshot().sessions.first { $0.id == session.id }?.projectID == target)
            try await connect()
            let read = try await rpc.request("thread/read", ["threadId": .string(session.id), "includeTurns": .bool(false)])["thread"]
            #expect(read["projectId"].string == target.map { projects[$0 == "a" ? 0 : 1] })
            #expect(read["cwd"].string == original.cwd)
            #expect(read["turns"].array.isEmpty)
            await rpc.stopAndWait()
        }
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
