import AppKit
import Foundation
import Testing
import CanvasCore
@testable import SessionCanvas

@Suite(.serialized) @MainActor
struct ImportRegressionTests {
    @Test func inventoryHidesInternalAgentsAndImportsExactProjectMembership() async throws {
        let fixture = try SourceFixture()
        defer { fixture.remove() }
        let source = CodexSource(mode: .history, settings: fixture.settings)
        defer { source.close() }
        try await source.connect()
        let snapshot = try await source.snapshot()
        #expect(Set(snapshot.sessions.map(\.id)) == ["normal", "named-review", "unassigned"])
        #expect(snapshot.projects == [Project(id: "p", name: "Existing project"), Project(id: "empty", name: "Empty project")])
        #expect(snapshot.sessions.first { $0.id == "normal" }?.projectID == "p")
        // Same directory and even a Guardian title do not imply membership or an internal agent.
        #expect(snapshot.sessions.first { $0.id == "named-review" }?.projectID == nil)
        #expect(snapshot.sessions.first { $0.id == "unassigned" }?.projectID == nil)
        #expect(snapshot.sessions.allSatisfy { $0.execution == .unknown })
        #expect(!source.canAssignProject)
    }

    @Test func refreshRemovesPreviouslyCachedGuardianNotes() async throws {
        let fixture = try SourceFixture()
        defer { fixture.remove() }
        let path = fixture.folder.appendingPathComponent("canvas.sqlite").path
        let database = try CanvasDatabase(path: path)
        var cached = Workspace()
        cached.reconcile(sessions: [Session(id: "guardian", title: "Guardian review")], projects: [])
        try database.save(cached, source: "codex-local:" + fixture.folder.path)
        let model = ApplicationModel(demo: false, storagePath: path)
        model.settings = fixture.settings
        await model.connect()
        #expect(model.connected)
        #expect(!model.workspace.sessions.contains { $0.id == "guardian" })
        #expect(model.workspace.placements["guardian"] == nil)
        #expect(model.workspace.projects.count == 2)
        let retained = model.workspace
        try Data("{".utf8).write(to: fixture.folder.appendingPathComponent(".codex-global-state.json"))
        await model.refresh()
        #expect(model.workspace == retained)
        #expect(model.errorMessage != nil)
        model.shutdown()
        #expect(!(try database.load(source: model.sourceID)).sessions.contains { $0.id == "guardian" })
    }

    @Test func refreshReflectsSavedProjectRenamesAndExplicitUnassignment() async throws {
        let fixture = try SourceFixture()
        defer { fixture.remove() }
        let source = CodexSource(mode: .history, settings: fixture.settings)
        defer { source.close() }
        try await source.connect()
        _ = try await source.snapshot()
        try #"{"local-projects":{"p":{"id":"p","name":"Renamed"}},"thread-project-assignments":{},"projectless-thread-ids":["normal"]}"#
            .write(to: fixture.folder.appendingPathComponent(".codex-global-state.json"), atomically: true, encoding: .utf8)
        let snapshot = try await source.snapshot()
        #expect(snapshot.projects == [Project(id: "p", name: "Renamed")])
        #expect(snapshot.sessions.first { $0.id == "normal" }?.projectID == nil)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SESSION_CANVAS_TEST_REAL_SOURCE"] == "1"))
    func installedCodexInventoryAndDesktopProjects() async throws {
        let source = CodexSource(mode: .history, settings: .defaults)
        defer { source.close() }
        try await source.connect()
        let snapshot = try await source.snapshot()
        #expect(!snapshot.sessions.isEmpty)
        #expect(!snapshot.projects.isEmpty)
        #expect(!source.hiddenSessionIDs.isEmpty)
        #expect(Set(snapshot.sessions.map(\.id)).isDisjoint(with: source.hiddenSessionIDs))
        #expect(snapshot.sessions.contains { $0.projectID != nil })
        print("Verified installed source: \(snapshot.sessions.count) sessions, \(source.hiddenSessionIDs.count) hidden internal sessions, \(snapshot.projects.count) projects, \(snapshot.sessions.filter { $0.projectID != nil }.count) assigned sessions.")
    }

    @Test(arguments: [-60.0, 130.0])
    func canvasRenderingStaysInsideItsFrameWhenPanned(noteY: Double) throws {
        _ = NSApplication.shared
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        model.workspace.viewport = Viewport(origin: Point(0, 0))
        let parent = CanvasTestBackground(frame: NSRect(x: 0, y: 0, width: 400, height: 320))
        let canvas = CanvasNSView(model: model)
        canvas.frame = NSRect(x: 0, y: 80, width: 400, height: 180)
        parent.addSubview(canvas)
        let baseline = try capture(parent)
        model.workspace.sessions = [Session(id: "s", title: "Overflowing note")]
        model.workspace.placements["s"] = Placement(Point(40, noteY))
        canvas.update()
        let panned = try capture(parent)
        // Inspect the header above and footer below the actual canvas, including note shadows.
        var changedOutsideCanvas = 0
        var changedInsideCanvas = 0
        for y in 0..<panned.pixelsHigh {
            let viewY = Double(y) * parent.bounds.height / Double(panned.pixelsHigh)
            for x in 0..<panned.pixelsWide {
                if baseline.colorAt(x: x, y: y) != panned.colorAt(x: x, y: y) {
                    if viewY < 75 || viewY >= 265 { changedOutsideCanvas += 1 }
                    if viewY >= 85 && viewY < 255 { changedInsideCanvas += 1 }
                }
            }
        }
        #expect(changedOutsideCanvas == 0)
        #expect(changedInsideCanvas > 0)
    }

    private func capture(_ view: NSView) throws -> NSBitmapImageRep {
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }
}

@MainActor private final class CanvasTestBackground: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) { NSColor.systemRed.setFill(); bounds.fill() }
}

private struct SourceFixture {
    let folder: URL
    let settings: ConnectionSettings
    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("canvas-import-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let executable = folder.appendingPathComponent("codex-fixture")
        settings = ConnectionSettings(executable: executable.path, socket: "", nativeURLTemplate: "codex://threads/{id}")
        let script = #"""
        #!/usr/bin/python3
        import json, pathlib, sys
        home = pathlib.Path(__file__).parent
        for line in sys.stdin:
            request = json.loads(line)
            if "id" not in request:
                continue
            method = request["method"]
            if method == "initialize":
                result = {"codexHome": str(home)}
            elif method == "thread/list":
                def session(ident, source, **extra):
                    return dict(id=ident, name="Guardian review" if ident != "normal" else "My work", source=source, cwd="/Projects/existing", updatedAt=1, **extra)
                if request.get("params", {}).get("cursor"):
                    result = {"data": [session("child", "appServer", parentThreadId="normal"), session("unassigned", "cli")], "nextCursor": None}
                else:
                    result = {"data": [session("normal", "cli"), session("guardian", {"subAgent": {"other": "guardian"}}), session("review", {"subAgent": "review"}), session("named-review", "appServer")], "nextCursor": "page2"}
            else:
                result = {}
            print(json.dumps({"id": request["id"], "result": result}), flush=True)
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try #"""
        {"local-projects":{"p":{"id":"p","name":"Existing project","rootPaths":["/Projects/existing"]},"empty":{"id":"empty","name":"Empty project","rootPaths":["/Projects/empty"]}},"project-order":["p","empty"],"thread-project-assignments":{"normal":{"projectKind":"local","projectId":"p"},"unassigned":{"projectKind":"local","projectId":"p"}},"projectless-thread-ids":["unassigned"]}
        """#.write(to: folder.appendingPathComponent(".codex-global-state.json"), atomically: true, encoding: .utf8)
    }
    func remove() { try? FileManager.default.removeItem(at: folder) }
}
