import AppKit
import Foundation
import Testing
import CanvasCore
@testable import SessionCanvas

@Suite(.serialized) @MainActor
struct ImportRegressionTests {
    @Test func unloadedSessionsRecoverTerminalStateBeforeOpeningViewer() async throws {
        let fixture = try SourceFixture()
        defer { fixture.remove() }
        let source = CodexSource(mode: .history, settings: fixture.settings)
        defer { source.close() }
        try await source.connect()
        let snapshot = try await source.snapshot()
        let session = try #require(snapshot.sessions.first { $0.id == "normal" })
        #expect(session.state(acknowledged: []) == .finished)
        #expect(session.latestResult?.id == "normal/last/completed")
        #expect(session.state(acknowledged: ["normal/last/completed"]) == .idle)
        #expect(snapshot.sessions.first { $0.id == "unassigned" }?.execution == .unknown)
        _ = try await source.snapshot()
        #expect(!FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent("reads").path))
        try Data().write(to: fixture.folder.appendingPathComponent("file-only"))
        let changedFile = try await source.snapshot()
        #expect(changedFile.sessions.first { $0.id == "normal" }?.execution == .unknown)
        #expect(changedFile.sessions.first { $0.id == "normal" }?.revision == session.revision)
        try Data().write(to: fixture.folder.appendingPathComponent("active"))
        let next = try await source.snapshot()
        #expect(next.sessions.first { $0.id == "normal" }?.execution == .unknown)
    }
    @Test func inventoryHidesInternalAgentsAndImportsExactProjectMembership() async throws {
        let fixture = try SourceFixture()
        defer { fixture.remove() }
        let source = CodexSource(mode: .history, settings: fixture.settings)
        defer { source.close() }
        try await source.connect()
        let snapshot = try await source.snapshot()
        #expect(Set(snapshot.sessions.map(\.id)) == ["normal", "named-review", "unassigned", "archived"])
        #expect(snapshot.projects == [Project(id: "p", name: "Existing project"), Project(id: "empty", name: "Empty project")])
        #expect(snapshot.sessions.first { $0.id == "normal" }?.projectID == "p")
        // Same directory and even a Guardian title do not imply membership or an internal agent.
        #expect(snapshot.sessions.first { $0.id == "named-review" }?.projectID == nil)
        #expect(snapshot.sessions.first { $0.id == "unassigned" }?.projectID == nil)
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
        var stale = retained
        for i in stale.sessions.indices { stale.sessions[i].execution = .unknown }
        #expect(model.workspace == stale)
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

    @Test func sourceArchiveRoundTripAndFailureKeepTheSameSession() async throws {
        let fixture = try SourceFixture()
        defer { fixture.remove() }
        let source = CodexSource(mode: .history, settings: fixture.settings)
        defer { source.close() }
        try await source.connect()
        let before = try #require(try await source.snapshot().sessions.first { $0.id == "normal" })
        try await source.setArchived(sessionID: "normal", archived: true)
        let archived = try #require(try await source.snapshot().sessions.first { $0.id == "normal" })
        #expect(archived.isArchived)
        #expect(archived.updatedAt == before.updatedAt)
        #expect(archived.projectID == before.projectID)
        try Data().write(to: fixture.folder.appendingPathComponent("legacy-history"))
        _ = try await source.history(sessionID: "normal", cursor: nil)
        try Data().write(to: fixture.folder.appendingPathComponent("omit-archived"))
        #expect(try await source.snapshot().sessions.first { $0.id == "normal" }?.state(acknowledged: []) == .archived)
        try await source.setArchived(sessionID: "normal", archived: false)
        #expect(try await source.snapshot().sessions.first { $0.id == "normal" }?.isArchived == false)
        try Data().write(to: fixture.folder.appendingPathComponent("reject-archive"))
        await #expect(throws: (any Error).self) { try await source.setArchived(sessionID: "normal", archived: true) }
        #expect(try await source.snapshot().sessions.first { $0.id == "normal" }?.isArchived == false)
    }

    @Test func cachedArchiveSurvivesHistoryMetadataForAnOmittedSession() async throws {
        let fixture = try SourceFixture()
        defer { fixture.remove() }
        let path = fixture.folder.appendingPathComponent("canvas.sqlite").path
        let database = try CanvasDatabase(path: path)
        var cached = Workspace()
        cached.reconcile(sessions: [Session(id: "cached", title: "Cached archive", isArchived: true)], projects: [])
        try database.save(cached, source: "codex-local:" + fixture.folder.path)
        let model = ApplicationModel(demo: false, storagePath: path)
        model.settings = fixture.settings
        defer { model.shutdown() }
        await model.connect()
        model.setStateVisible(.archived, true)
        try Data().write(to: fixture.folder.appendingPathComponent("legacy-history"))
        model.openSession("cached")
        await model.loadHistory(older: false)
        await model.refresh()
        let restored = try #require(model.workspace.sessions.first { $0.id == "cached" })
        #expect(restored.isArchived)
        #expect(model.state(restored) == .archived)
        #expect(model.workspace.placements[restored.id] == cached.placements[restored.id])
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SESSION_CANVAS_TEST_REAL_SOURCE"] == "1"))
    func installedCodexInventoryAndDesktopProjects() async throws {
        let source = CodexSource(mode: .history, settings: .defaults, observeDesktop: false)
        defer { source.close() }
        try await source.connect()
        let snapshot = try await source.snapshot()
        #expect(!snapshot.sessions.isEmpty)
        #expect(!snapshot.projects.isEmpty)
        #expect(!source.hiddenSessionIDs.isEmpty)
        #expect(Set(snapshot.sessions.map(\.id)).isDisjoint(with: source.hiddenSessionIDs))
        #expect(snapshot.sessions.contains { $0.projectID != nil })
        #expect(snapshot.sessions.contains { $0.stateIsFromHistory && $0.execution == .idle })
        print("Verified installed source: \(snapshot.sessions.count) sessions, \(source.hiddenSessionIDs.count) hidden internal sessions, \(snapshot.projects.count) projects, \(snapshot.sessions.filter { $0.projectID != nil }.count) assigned sessions.")
        print("Saved terminal/empty state: \(snapshot.sessions.filter { $0.stateIsFromHistory && $0.execution == .idle }.count); Unknown: \(snapshot.sessions.filter { $0.execution == .unknown }.count); archived: \(snapshot.sessions.filter(\.isArchived).count).")
        print("Unavailable local history: \(snapshot.sessions.filter { $0.unknownReason == .historyMissing }.count); incomplete evidence: \(snapshot.sessions.filter { $0.unknownReason == .incompleteHistory }.count).")
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
        archived_ids = {"archived"}
        reads = 0
        for line in sys.stdin:
            request = json.loads(line)
            if "id" not in request:
                continue
            method = request["method"]
            if method == "initialize":
                result = {"codexHome": str(home)}
            elif method == "thread/list":
                def session(ident, source, **extra):
                    path = home / "sessions" / (ident + ".jsonl")
                    path.parent.mkdir(exist_ok=True)
                    active = ident == "unassigned" or ident == "normal" and ((home / "active").exists() or (home / "file-only").exists())
                    records = [{"type":"session_meta", "payload":{"id":ident}}, {"type":"event_msg", "payload":{"type":"task_started" if active else "task_complete", "turn_id":"last"}}]
                    content = "".join(json.dumps(v) + "\n" for v in records)
                    if not path.exists() or path.read_text() != content: path.write_text(content)
                    return dict(id=ident, name="Guardian review" if ident != "normal" else "My work", source=source, cwd="/Projects/existing", path=str(path), updatedAt=2 if ident == "normal" and (home / "active").exists() else 1, **extra)
                if request.get("params", {}).get("archived"):
                    result = {"data": [] if (home / "omit-archived").exists() else [session(ident, "cli") for ident in archived_ids], "nextCursor": None}
                elif request.get("params", {}).get("cursor"):
                    result = {"data": [session("child", "appServer", parentThreadId="normal"), session("unassigned", "cli")], "nextCursor": None}
                else:
                    result = {"data": [s for s in [session("normal", "cli"), session("guardian", {"subAgent": {"other": "guardian"}}), session("review", {"subAgent": "review"}), session("named-review", "appServer")] if s["id"] not in archived_ids], "nextCursor": "page2"}
            elif method == "thread/turns/list":
                if (home / "legacy-history").exists():
                    print(json.dumps({"id": request["id"], "error": {"code": -32601}}), flush=True)
                    continue
                reads += 1
                (home / "reads").write_text(str(reads))
                ident = request["params"]["threadId"]
                result = {"data": [{"id":"last", "status":"inProgress" if ident == "unassigned" or ident == "normal" and (home / "active").exists() else "completed", "items":[]}], "nextCursor": None}
            elif method == "thread/read":
                result = {"thread":{"id":request["params"]["threadId"], "name":"My work", "cwd":"/Projects/existing", "updatedAt":1, "status":{"type":"notLoaded"}, "turns":[{"id":"last", "status":"completed", "items":[]}]}}
            elif method in ["thread/archive", "thread/unarchive"]:
                if (home / "reject-archive").exists():
                    print(json.dumps({"id": request["id"], "error": {"code": -32600}}), flush=True)
                    continue
                ident = request["params"]["threadId"]
                if method == "thread/archive": archived_ids.add(ident)
                else: archived_ids.discard(ident)
                result = {}
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
