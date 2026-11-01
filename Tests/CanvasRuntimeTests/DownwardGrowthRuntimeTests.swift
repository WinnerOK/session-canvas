import AppKit
import CSQLite
import Testing
import CanvasCore
@testable import SessionCanvas

@Suite(.serialized) @MainActor
struct DownwardGrowthRuntimeTests {
    @Test func saveFailureRetainsTheCompleteCascadeAndRetrySavesIt() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let model = ApplicationModel(demo: true, storagePath: path)
        await model.connect(); defer { model.shutdown() }
        model.workspace = fixture()
        model.persist()
        model.acknowledgments = ["a": ["reviewed"]]
        let acknowledgment = model.acknowledgments
        let database = try CanvasDatabase(path: path)
        let saved = try database.load(source: model.sourceID)
        try sql("CREATE TRIGGER reject_growth BEFORE UPDATE ON workspace BEGIN SELECT RAISE(ABORT,'fixture'); END", path)

        let arrival = Session(id: "new", title: "New session", projectID: "p", execution: .running)
        model.workspace.sessions.append(arrival)
        model.persist()
        let grown = model.workspace
        #expect(grown.regions["p"] == Rect(0, 0, 300, 410))
        #expect(grown.regions["q"]!.y > saved.regions["q"]!.y)
        #expect(grown.placements["free"]!.position.y > saved.placements["free"]!.position.y)
        #expect(grown.viewport == saved.viewport)
        #expect(grown.sessions == saved.sessions + [arrival])
        #expect(model.hasUnsavedLayout && model.errorMessage != nil)
        #expect(model.acknowledgments == acknowledgment)
        #expect(try database.load(source: model.sourceID) == saved)

        try sql("DROP TRIGGER reject_growth", path)
        model.retryLayoutSave()
        #expect(!model.hasUnsavedLayout)
        #expect(model.workspace == grown)
        #expect(try database.load(source: model.sourceID) == grown)
    }

    @Test func nativeCanvasRendersTheAnchoredGrowthWithoutChangingViewport() throws {
        _ = NSApplication.shared
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        defer { model.shutdown() }
        model.workspace = fixture()
        model.synchronizeLayers()
        let canvas = CanvasNSView(model: model)
        canvas.frame = NSRect(x: 0, y: 0, width: 1000, height: 900)
        canvas.update()
        let viewport = model.workspace.viewport
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("session-canvas-growth-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try capture(canvas, to: directory.appendingPathComponent("before.png"))
        model.workspace.sessions.append(Session(id: "new", title: "New session", projectID: "p", execution: .running))
        model.synchronizeLayers()
        canvas.update()
        try capture(canvas, to: directory.appendingPathComponent("after.png"))
        #expect(model.workspace.viewport == viewport)
        #expect(model.workspace.placements["a"]?.position == Point(20, 64))
        #expect(model.workspace.placements["new"]?.position == Point(20, 236))
        let labels = (canvas.accessibilityChildren() as? [NSAccessibilityElement])?.compactMap { $0.accessibilityLabel() } ?? []
        #expect(labels.count == 5 && labels.contains { $0.contains("New session") })
        print("Downward growth native captures: \(directory.path)")
    }

    private func fixture() -> Workspace {
        var value = Workspace()
        value.projects = [Project(id: "p", name: "Target"), Project(id: "q", name: "Neighbor"), Project(id: "side", name: "Unchanged")]
        value.sessions = [("a", "p"), ("b", "q"), ("side", "side")].map {
            Session(id: $0.0, title: $0.0 == "a" ? "Existing session" : $0.0, projectID: $0.1, execution: .running)
        } + [Session(id: "free", title: "Unassigned session", execution: .running)]
        value.regions = ["p": Rect(0, 0, 300, 240), "q": Rect(0, 250, 300, 240), "side": Rect(400, 250, 300, 240)]
        value.placements = ["a": Placement(Point(20, 64)), "b": Placement(Point(20, 314)),
                            "side": Placement(Point(420, 314)), "free": Placement(Point(20, 510))]
        value.viewport = Viewport(origin: Point(40, 30), zoom: 1)
        return value
    }

    private func capture(_ canvas: CanvasNSView, to url: URL) throws {
        let bitmap = try #require(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
        canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }

    private func sql(_ statement: String, _ path: String) throws {
        var database: OpaquePointer?
        #expect(sqlite3_open(path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        #expect(sqlite3_exec(database, statement, nil, nil, nil) == SQLITE_OK)
    }
}
