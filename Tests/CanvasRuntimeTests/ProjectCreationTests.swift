import AppKit
import SwiftUI
import Testing
import CanvasCore
@testable import SessionCanvas

@Suite(.serialized) @MainActor
struct ProjectCreationTests {
    @Test(arguments: [false, true])
    func occupiedCreationStaysNearTheClickAcrossRefreshAndRestart(hidden: Bool) async throws {
        let fixture = try CreationFixture()
        defer { fixture.remove() }
        let storage = fixture.folder.appendingPathComponent("canvas.sqlite").path
        let model = ApplicationModel(demo: false, storagePath: storage, nativeOpener: { _ in })
        model.settings = fixture.settings
        await model.connect()
        defer { model.shutdown() }
        model.selectLayer(.inactive)
        let point = Point(-8200, -4700)
        let viewport = Viewport(origin: Point(7000, 4000), zoom: 0.78)
        model.workspace.viewport = viewport
        let occupied = Placement(point + Point(-80, -30))
        model.workspace.sessions.append(Session(id: "existing", title: "Existing session", execution: .unknown))
        model.workspace.placements["existing"] = occupied
        if hidden { model.setStateVisible(.unknown, false) }
        model.beginCreation(at: point)
        await model.create(title: "Created near the click", prompt: "", projectID: nil, cwd: fixture.folder.path)
        let placement = try #require(model.workspace.placements["created"])
        // The only obstacle is close to the click; it must not send creation back to the global grid.
        #expect(abs(placement.position.x - point.x) <= Placement.width + 24)
        #expect(abs(placement.position.y - point.y) <= Placement.height + 24)
        #expect(!placement.rect.intersects(occupied.rect))
        #expect(model.workspace.project(at: placement.center) == nil)
        #expect(model.workspace.placements["existing"] == occupied)
        #expect(model.workspace.viewport == viewport)
        #expect(model.focusedSessionID == nil)
        await model.refresh()
        #expect(model.workspace.placements["created"] == placement)
        model.shutdown()
        let restored = ApplicationModel(demo: false, storagePath: storage, nativeOpener: { _ in })
        restored.settings = fixture.settings
        await restored.connect()
        defer { restored.shutdown() }
        #expect(restored.workspace.placements["created"] == placement)
    }

    @Test(arguments: [1.0, 0.78, 0.42, 0.03], [false, true])
    func projectlessContextCreationStaysAtTheClickWithoutMovingTheCanvas(zoom: Double, obstructed: Bool) async throws {
        _ = NSApplication.shared
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        await model.connect()
        defer { model.shutdown() }
        model.fitRequest = 0
        let viewport = Viewport(origin: Point(120, 700), zoom: zoom)
        model.workspace.viewport = viewport
        let canvas = CanvasNSView(model: model)
        canvas.frame = NSRect(x: 0, y: 0, width: 1400, height: 700)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        canvas.update()
        let screen = Point(700 - Placement.width * zoom / 2, 350 - Placement.height * zoom / 2)
        let point = viewport.world(screen)
        if obstructed {
            model.workspace.sessions.append(Session(id: "hidden", title: "Hidden session", execution: .idle))
            model.workspace.placements["hidden"] = Placement(point + Point(-80, -30))
            model.setStateVisible(.idle, false)
        }
        let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown,
            location: canvas.convert(NSPoint(x: screen.x, y: screen.y), to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let menu = try #require(canvas.menu(for: event))
        let item = try #require(menu.items.first { $0.title == "New session here…" })
        #expect(NSApp.sendAction(try #require(item.action), to: item.target, from: item))
        #expect(model.creation?.projectID == nil)
        await model.create(title: "Created at the click", prompt: "Demo prompt", projectID: nil, cwd: "Demo workspace")
        let session = try #require(model.workspace.sessions.first { $0.title == "Created at the click" })
        let expected = obstructed ? point + Point(0, 120) : point
        #expect(model.workspace.placements[session.id]?.position == expected)
        canvas.update()
        #expect(model.workspace.viewport == viewport)
        canvas.setFrameSize(NSSize(width: 1000, height: 700))
        canvas.update()
        #expect(model.workspace.viewport == viewport)
        let actual = viewport.screen(try #require(model.workspace.placements[session.id]).position)
        let expectedScreen = viewport.screen(expected)
        #expect(abs(actual.x - expectedScreen.x) < 0.000001)
        #expect(abs(actual.y - expectedScreen.y) < 0.000001)
        #expect(model.selectedSessionID == session.id)
    }

    @Test(arguments: [1.0, 0.42, 0.03])
    func projectContextMenuCreatesInTheChosenProject(zoom: Double) async throws {
        _ = NSApplication.shared
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        await model.connect()
        defer { model.shutdown() }
        model.fitRequest = 0
        model.workspace.viewport = Viewport(origin: Point(40, 60), zoom: zoom)
        let canvas = CanvasNSView(model: model)
        canvas.frame = NSRect(x: 0, y: 0, width: 1400, height: 700)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        canvas.update()
        let point = Point(300, 400)
        let screen = model.workspace.viewport.screen(point)
        let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown,
            location: canvas.convert(NSPoint(x: screen.x, y: screen.y), to: nil), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let menu = try #require(canvas.menu(for: event))
        let create = try #require(menu.items.first { $0.title == "New session in project…" })
        #expect(create.isEnabled)
        #expect(NSApp.sendAction(try #require(create.action), to: create.target, from: create))
        let context = try #require(model.creation)
        #expect(context.projectID == "canvas")
        #expect(abs(context.location.x - point.x) < 0.000001)
        #expect(abs(context.location.y - point.y) < 0.000001)
        await model.create(title: "Created from project", prompt: "Demo prompt", projectID: context.projectID, cwd: "Demo workspace")
        #expect(model.workspace.sessions.first { $0.title == "Created from project" }?.projectID == "canvas")
        #expect(model.creation == nil)
    }

    @Test func createsWithConfirmedServerProjectAndRetainsEmptyThread() async throws {
        let fixture = try CreationFixture()
        defer { fixture.remove() }
        let source = CodexSource(mode: .history, settings: fixture.settings)
        defer { source.close() }
        try await source.connect()
        #expect(source.sourceID == "codex-local:" + fixture.folder.path)
        _ = try await source.snapshot()
        #expect(source.canCreate)
        #expect(source.creationDirectory(projectID: "desktop-project") == fixture.folder.path)
        let created = try await source.create(title: "My new session", prompt: "", projectID: "desktop-project", cwd: "/unrelated")
        #expect(created.session.id == "created")
        #expect(created.session.title == "My new session")
        #expect(created.session.projectID == "desktop-project")
        #expect(created.warning == nil)
        let snapshot = try await source.snapshot()
        #expect(snapshot.sessions.count == 1)
        #expect(snapshot.sessions.first?.projectID == "desktop-project")
        let requests = try fixture.requests()
        let start = try #require(requests.first { $0["method"].string == "thread/start" })["params"]
        #expect(start["projectId"].string == "server-project")
        #expect(start["cwd"].string == fixture.folder.path)
        #expect(start["runtimeWorkspaceRoots"].array.compactMap(\.string) == [fixture.folder.path])
        #expect(start["ephemeral"] == .bool(false))
        #expect(requests.filter { $0["method"].string == "thread/start" }.count == 1)
        let resume = try #require(requests.first { $0["method"].string == "thread/resume" })
        let startRequest = try #require(requests.first { $0["method"].string == "thread/start" })
        let inventory = try #require(requests.first { $0["method"].string == "thread/list" })
        #expect(startRequest["process"] != inventory["process"])
        #expect(resume["process"] != startRequest["process"])
        #expect(resume["process"] != inventory["process"])
        #expect(resume["params"]["threadId"].string == "created")
        #expect(!requests.contains { $0["method"].string == "turn/start" })
    }

    @Test func blankNameAndDirectoryCreateAProjectlessResumableSession() async throws {
        let fixture = try CreationFixture()
        defer { fixture.remove() }
        let base = fixture.folder.appendingPathComponent("workspaces")
        let source = CodexSource(mode: .history, settings: fixture.settings, workingDirectoryBase: base)
        defer { source.close() }
        try await source.connect()
        let created = try await source.create(title: " \n", prompt: "", projectID: nil, cwd: " \n")
        #expect(created.warning == nil)
        #expect(created.session.title == "New session")
        #expect(created.session.projectID == nil)
        #expect(created.session.cwd.hasPrefix(base.path + "/"))
        var directory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: created.session.cwd, isDirectory: &directory))
        #expect(directory.boolValue)
        let start = try #require(try fixture.requests().first { $0["method"].string == "thread/start" })["params"]
        #expect(start["projectId"] == .null)
        #expect(start["cwd"].string == created.session.cwd)
    }

    @Test(arguments: [String?.none, "desktop-project"], [CanvasLayer.active, .inactive])
    func creationRevealsItsSessionEvenWhenUnknownIsHidden(projectID: String?, origin: CanvasLayer) async throws {
        let fixture = try CreationFixture()
        defer { fixture.remove() }
        var opened: [URL] = []
        let model = ApplicationModel(demo: false, storagePath: ":memory:", nativeOpener: { opened.append($0) })
        model.settings = fixture.settings
        await model.connect()
        defer { model.shutdown() }
        model.selectLayer(.inactive)
        model.setStateVisible(.unknown, false)
        model.setProjectVisible("desktop-project", false)
        model.workspace.sessions.append(Session(id: "old", title: "Older work", execution: .unknown))
        model.search = "older work"
        model.selectLayer(origin)
        model.beginCreation(at: Point(500, 500))
        await model.create(title: "Created from the dialog", prompt: "", projectID: projectID, cwd: fixture.folder.path)
        #expect(model.creation == nil)
        #expect(model.workspace.sessions.contains { $0.id == "created" })
        #expect(model.visibleSessions.contains { $0.id == "created" })
        #expect(model.selectedSessionID == "created")
        #expect(opened.map(\.absoluteString) == ["codex://threads/created"])
        #expect(model.creationIsOutsideFilters)
        #expect(model.visibility.hiddenStates.contains(.unknown))
        #expect(model.visibility.hiddenProjectIDs.contains("desktop-project"))
        #expect(model.visibleSessions.map(\.id) == ["created"])
        #expect(model.search == "older work")
        await model.refresh()
        #expect(model.visibleSessions.contains { $0.id == "created" })
        #expect(model.selectedSessionID == "created")
        // Explicit/fallback focus is separate from preserving a valid clicked position.
        model.revealCreatedSession("created")
        let canvas = CanvasNSView(model: model)
        canvas.frame = NSRect(x: 0, y: 0, width: 700, height: 600)
        model.workspace.viewport = Viewport(origin: Point(-30000, -50000), zoom: 0.03)
        canvas.update()
        let center = model.workspace.viewport.screen(try #require(model.workspace.placements["created"]).center)
        #expect(abs(center.x - 350) < 0.001)
        #expect(abs(center.y - 300) < 0.001)
        #expect(model.workspace.viewport.zoom >= 0.75)
        canvas.setFrameSize(NSSize(width: 450, height: 600))
        canvas.update()
        let resizedCenter = model.workspace.viewport.screen(try #require(model.workspace.placements["created"]).center)
        #expect(abs(resizedCenter.x - 225) < 0.001)
        #expect(abs(resizedCenter.y - 300) < 0.001)
        var panned = model.workspace.viewport
        panned.origin = panned.origin + Point(40, 20)
        model.setViewport(panned)
        canvas.setFrameSize(NSSize(width: 500, height: 620))
        #expect(model.workspace.viewport == panned)
        model.applyFiltersToCreation()
        #expect(model.visibleSessions.isEmpty)
        #expect(model.selectedSessionID == nil)
    }

    @Test func creationFailureRemainsInItsDialog() async throws {
        let fixture = try CreationFixture()
        defer { fixture.remove() }
        let model = ApplicationModel(demo: false, storagePath: ":memory:")
        model.settings = fixture.settings
        await model.connect()
        defer { model.shutdown() }
        model.beginCreation(at: Point(0, 0))
        await model.create(title: "", prompt: "", projectID: nil, cwd: fixture.folder.path + "/missing")
        #expect(model.creation != nil)
        #expect(model.workspace.sessions.isEmpty)
        // An alert on the covered parent is not feedback inside the active sheet.
        #expect(model.errorMessage == nil)
        #expect(model.creationError != nil)
    }

    @Test func nativeCreateButtonRevealsSession() async throws {
        _ = NSApplication.shared
        let fixture = try CreationFixture()
        defer { fixture.remove() }
        var opened: [URL] = []
        let model = ApplicationModel(demo: false, storagePath: ":memory:", nativeOpener: { opened.append($0) })
        model.settings = fixture.settings
        await model.connect()
        defer { model.shutdown() }
        model.setStateVisible(.unknown, false)
        model.creation = ApplicationModel.CreationContext(location: Point(500, 500), projectID: "desktop-project")
        let form = NSHostingView(rootView: NewSessionView(model: model, context: try #require(model.creation)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 480), styleMask: .titled, backing: .buffered, defer: false)
        window.contentView = form
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(200))
        form.layoutSubtreeIfNeeded()
        // Return activates the hosted form's actual default submit button.
        let submit = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
            isARepeat: false, keyCode: 36))
        #expect(window.performKeyEquivalent(with: submit))
        for _ in 0..<100 {
            if model.creation == nil { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        #expect(model.creation == nil)
        #expect(model.selectedSessionID == "created")
        #expect(model.visibleSessions.map(\.id) == ["created"])
        #expect(opened.map(\.absoluteString) == ["codex://threads/created"])
        #expect(try fixture.requests().filter { $0["method"].string == "thread/start" }.count == 1)
    }

    @Test func catalogUsesOnlyTheConnectedHomeProjectIDs() throws {
        let fixture = try CreationFixture()
        defer { fixture.remove() }
        let data = try Data(contentsOf: fixture.folder.appendingPathComponent(".codex-global-state.json"))
        let catalog = try DesktopProjectCatalog(data: data, codexHome: fixture.folder.path)
        #expect(catalog.serverProjectID(for: "desktop-project") == "server-project")
        #expect(catalog.projectID(for: "created", serverProjectID: "server-project") == "desktop-project")
        #expect(catalog.projectID(for: "remote", serverProjectID: "server-project") == nil)
        #expect(catalog.projectID(for: "unknown", serverProjectID: "server-project") == nil)
        let other = try DesktopProjectCatalog(data: data, codexHome: fixture.folder.path + "/other-home")
        #expect(other.serverProjectID(for: "desktop-project") == "other-server-project")
        #expect(other.projectID(for: "created", serverProjectID: "server-project") == nil)
    }

    @Test func missingProjectAndUnsubmittedPromptCannotCreate() async throws {
        let fixture = try CreationFixture()
        defer { fixture.remove() }
        let source = CodexSource(mode: .history, settings: fixture.settings)
        defer { source.close() }
        try await source.connect()
        _ = try await source.snapshot()
        for (projectID, prompt) in [("removed-project", ""), ("desktop-project", "Do not silently discard this")] {
            await #expect(throws: (any Error).self) {
                try await source.create(title: "", prompt: prompt, projectID: projectID, cwd: fixture.folder.path)
            }
        }
        #expect(!(try fixture.requests()).contains { $0["method"].string == "thread/start" })
    }

    @Test func unverifiedCreationReportsWarningWithoutAutomaticNavigation() async throws {
        let fixture = try CreationFixture(behavior: "name-failure")
        defer { fixture.remove() }
        var opened: [URL] = []
        let model = ApplicationModel(demo: false, storagePath: ":memory:", nativeOpener: { opened.append($0) })
        model.settings = fixture.settings
        await model.connect()
        defer { model.shutdown() }
        model.beginCreation(at: Point(0, 0))
        await model.create(title: "Name", prompt: "", projectID: nil, cwd: fixture.folder.path)
        #expect(opened.isEmpty)
        #expect(model.selectedSessionID == "created")
        #expect(model.errorMessage != nil)
        #expect(model.workspace.sessions.map(\.id) == ["created"])
    }

    @Test func ambiguousCreationCannotBeSubmittedAgain() async throws {
        let fixture = try CreationFixture(behavior: "missing-identity")
        defer { fixture.remove() }
        let source = CodexSource(mode: .history, settings: fixture.settings)
        defer { source.close() }
        try await source.connect()
        _ = try await source.snapshot()
        for _ in 0..<2 {
            await #expect(throws: (any Error).self) {
                try await source.create(title: "", prompt: "", projectID: "desktop-project", cwd: "")
            }
        }
        #expect(!source.canCreate)
        #expect(try fixture.requests().filter { $0["method"].string == "thread/start" }.count == 1)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SESSION_CANVAS_TEST_REAL_SOURCE"] == "1"))
    func installedServerCreatesPersistentSessionInIsolatedProject() async throws {
        let fixture = try CreationFixture()
        defer { fixture.remove() }
        // Isolate both config and SQLite: no real project, chat, or turn is created in the user's home.
        let script = #"""
        #!/usr/bin/python3
        import os, pathlib, sys
        home = str(pathlib.Path(__file__).parent)
        os.environ["CODEX_HOME"] = home
        os.environ["CODEX_SQLITE_HOME"] = home
        executable = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
        os.execv(executable, [executable] + sys.argv[1:])
        """#
        try script.write(toFile: fixture.settings.executable, atomically: true, encoding: .utf8)
        let rpc = RPCConnection()
        defer { rpc.stop() }
        var connectedHome = ""
        func connectProbe() async throws {
            try rpc.start(executable: fixture.settings.executable, arguments: ["app-server", "--listen", "stdio://"])
            let initialized = try await rpc.request("initialize", ["clientInfo": .object(["name": .string("session_canvas_creation_test"), "version": .string("0.1.0")]), "capabilities": .object(["experimentalApi": .bool(true)])])
            connectedHome = try #require(initialized["codexHome"].string)
            try rpc.notify("initialized")
        }
        try await connectProbe()
        let project = try await rpc.request("project/create", ["idempotencyKey": .string(UUID().uuidString), "name": .string("Isolated verification"), "roots": .array([.object(["path": .string(fixture.folder.path)])])])["project"]
        let projectID = try #require(project["id"].string)
        rpc.stop()
        try fixture.metadata(serverID: projectID, codexHome: connectedHome)
        let source = CodexSource(mode: .history, settings: fixture.settings, workingDirectoryBase: fixture.folder.appendingPathComponent("workspaces"))
        defer { source.close() }
        try await source.connect()
        #expect(source.sourceID == "codex-local:" + connectedHome)
        let snapshot = try await source.snapshot()
        #expect(snapshot.projects.map(\.id) == ["desktop-project"])
        let catalog = try #require(try DesktopProjectCatalog.read(codexHome: connectedHome))
        #expect(catalog.serverProjectID(for: "desktop-project") == projectID)
        #expect(source.canCreate)
        let created = try await source.create(title: "Isolated empty session", prompt: "", projectID: "desktop-project", cwd: "")
        #expect(created.session.projectID == "desktop-project")
        #expect(created.session.title == "Isolated empty session")
        #expect(created.warning == nil)
        #expect(try await source.snapshot().sessions.contains { $0.id == created.session.id && $0.projectID == "desktop-project" })
        // Keep the inventory client alive: it must not retain ownership of a created chat.
        try await connectProbe()
        let inventory = try await rpc.request("thread/list", ["limit": .number(100), "archived": .bool(false), "useStateDbOnly": .bool(true)])
        // The server omits empty chats from discovery even though exact-ID resume works.
        // Canvas must retain the note and expose direct navigation instead of sending
        // the user to search Codex's list for a chat that has no first message yet.
        #expect(!inventory["data"].array.contains { $0["id"].string == created.session.id })
        let read = try await rpc.request("thread/resume", ["threadId": .string(created.session.id), "excludeTurns": .bool(true)])["thread"]
        #expect(read["id"].string == created.session.id)
        #expect(read["projectId"].string == projectID)
        #expect(read["name"].string == "Isolated empty session")
        #expect(read["turns"].array.isEmpty)
        rpc.stop()
        let unnamed = try await source.create(title: "  \n", prompt: "", projectID: nil, cwd: "")
        #expect(!unnamed.session.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(unnamed.session.projectID == nil)
        #expect(unnamed.warning == nil)
        try await connectProbe()
        let resumed = try await rpc.request("thread/resume", ["threadId": .string(unnamed.session.id), "excludeTurns": .bool(true)])["thread"]
        #expect(resumed["id"].string == unnamed.session.id)
        #expect(resumed["name"].string == unnamed.session.title)
        #expect(resumed["projectId"] == .null)
        #expect(resumed["turns"].array.isEmpty)
        await rpc.stopAndWait()
        // Exercise the real ApplicationModel flow too, not just its source adapter.
        var opened: [URL] = []
        let model = ApplicationModel(demo: false, storagePath: ":memory:", nativeOpener: { opened.append($0) })
        model.settings = fixture.settings
        await model.connect()
        defer { model.shutdown() }
        model.setStateVisible(.unknown, false)
        model.beginCreation(at: Point(0, 0))
        await model.create(title: "Isolated dialog session", prompt: "", projectID: nil, cwd: fixture.folder.path)
        let selected = try #require(model.selectedSession)
        #expect(model.creation == nil)
        #expect(model.errorMessage == nil)
        #expect(model.creationError == nil)
        #expect(model.visibleSessions.map(\.id) == [selected.id])
        #expect(opened.map(\.absoluteString) == ["codex://threads/" + selected.id])
        try await connectProbe()
        let modelResume = try await rpc.request("thread/resume", ["threadId": .string(selected.id), "excludeTurns": .bool(true)])["thread"]
        #expect(modelResume["id"].string == selected.id)
        #expect(modelResume["name"].string == "Isolated dialog session")
        #expect(modelResume["turns"].array.isEmpty)
        await rpc.stopAndWait()
        // Archive only isolated test data; never mutate the user's existing sessions.
        try await source.setArchived(sessionID: created.session.id, archived: true)
        #expect(try await source.snapshot().sessions.first { $0.id == created.session.id }?.isArchived == true)
        try await connectProbe()
        let archivedRead = try await rpc.request("thread/read", ["threadId": .string(created.session.id), "includeTurns": .bool(false)])["thread"]
        #expect(archivedRead["id"].string == created.session.id)
        #expect(archivedRead["path"].string?.contains("/archived_sessions/") == true)
        await rpc.stopAndWait()
        try await source.setArchived(sessionID: created.session.id, archived: false)
        #expect(try await source.snapshot().sessions.first { $0.id == created.session.id }?.isArchived == false)
    }
}

private struct CreationFixture {
    let folder: URL
    let settings: ConnectionSettings
    init(behavior: String = "normal") throws {
        folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("canvas-create-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let executable = folder.appendingPathComponent("codex-fixture")
        settings = ConnectionSettings(executable: executable.path, socket: "", nativeURLTemplate: "codex://threads/{id}")
        let script = #"""
        #!/usr/bin/python3
        import json, os, pathlib, sys
        home = pathlib.Path(__file__).parent
        behavior = "BEHAVIOR"
        thread = dict(id="created", name=None, projectId="server-project", cwd=str(home), updatedAt=1, status={"type":"idle"})
        for line in sys.stdin:
            request = json.loads(line)
            if "id" not in request: continue
            request["process"] = os.getpid()
            with (home / "requests.jsonl").open("a") as log: log.write(json.dumps(request) + "\n")
            if (home / "thread.json").exists(): thread = json.loads((home / "thread.json").read_text())
            method, params = request["method"], request.get("params", {})
            if method == "initialize": result = {"codexHome": str(home)}
            elif method == "project/list": result = {"data": []}
            elif method == "project/read": result = {"project": {"id": "server-project", "roots": [{"path": str(home)}]}}
            elif method == "thread/list": result = {"data": [thread] if (home / "publish").exists() and not request.get("params", {}).get("archived") else []}
            elif method == "thread/start":
                thread.update(projectId=params.get("projectId"), cwd=params["cwd"])
                (home / "thread.json").write_text(json.dumps(thread))
                result = {} if behavior == "missing-identity" else {"thread": thread}
            elif method == "thread/name/set":
                if behavior == "name-failure":
                    print(json.dumps({"id": request["id"], "error": {"code": -1, "message": "fixture failure"}}), flush=True)
                    continue
                thread["name"] = params["name"]
                (home / "thread.json").write_text(json.dumps(thread))
                result = {}
            elif method in ["thread/read", "thread/resume"]: result = {"thread": thread}
            else: result = {}
            print(json.dumps({"id": request["id"], "result": result}), flush=True)
        """#.replacingOccurrences(of: "BEHAVIOR", with: behavior)
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try metadata()
    }
    func metadata(projectless: [String] = [], serverID: String = "server-project", codexHome: String? = nil) throws {
        let state: [String: Any] = [
            "local-projects": ["desktop-project": ["id": "desktop-project", "name": "Existing project", "rootPaths": [folder.path]]],
            "thread-project-assignments": ["unknown": ["projectKind": "remote", "projectId": "desktop-project"]], "projectless-thread-ids": projectless,
            "thread-project-membership-host-ids": ["remote": "remote-host"],
            "app-server-project-id-by-legacy-project-id-by-host": [
                "local:" + (codexHome ?? folder.path): ["desktop-project": serverID],
                "local:" + folder.path + "/other-home": ["desktop-project": "other-server-project"]]
        ]
        try JSONSerialization.data(withJSONObject: state).write(to: folder.appendingPathComponent(".codex-global-state.json"))
    }
    func requests() throws -> [JSONValue] {
        try String(contentsOf: folder.appendingPathComponent("requests.jsonl"), encoding: .utf8).split(separator: "\n").map { try JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
    }
    func remove() { try? FileManager.default.removeItem(at: folder) }
}
