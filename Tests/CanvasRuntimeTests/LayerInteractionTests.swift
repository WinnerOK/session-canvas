import AppKit
import CSQLite
import Testing
import CanvasCore
@testable import SessionCanvas

@Suite(.serialized) @MainActor
struct LayerInteractionTests {
    @Test func rearrangeChangesOnlyTheSelectedLayer() async throws {
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        await model.connect(); defer { model.shutdown() }
        model.workspace.sessions += [Session(id: "unknown", title: "Unknown", projectID: "canvas"),
                                     Session(id: "old", title: "Stale", projectID: "research", execution: .idle, updatedAt: Date(timeIntervalSince1970: 1))]
        model.persist(); model.setIdleTimeout(.oneHour)
        let stale = model.workspace.layerState?.layouts[.stale], inactive = model.workspace.layerState?.layouts[.inactive]
        let viewport = model.workspace.viewport
        model.rearrange()
        #expect(model.workspace.layerState?.layouts[.stale] == stale)
        #expect(model.workspace.layerState?.layouts[.inactive] == inactive)
        #expect(model.workspace.viewport == viewport && model.errorMessage == nil)
        let arranged = model.workspace
        model.rearrange(); #expect(model.workspace == arranged)
    }
    @Test func successfulCreationRemainsVisibleWhenDestinationPreferenceCannotSave() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let model = ApplicationModel(demo: true, storagePath: path)
        await model.connect(); defer { model.shutdown() }
        model.workspace.sessions.append(Session(id: "archived", title: "Archive", projectID: "canvas", isArchived: true))
        model.persist(); model.selectLayer(.inactive)
        let rect = try #require(model.workspace.regions["canvas"])
        model.beginCreation(at: Point(rect.x + 30, rect.y + 30))
        try sql("CREATE TRIGGER reject_create_layout BEFORE UPDATE ON workspace BEGIN SELECT RAISE(ABORT,'fixture'); END", path)
        await model.create(title: "Created while unsaved", prompt: "Demo only", projectID: "canvas", cwd: "")
        let session = try #require(model.workspace.sessions.first { $0.title == "Created while unsaved" })
        #expect(model.selectedLayer == .active && model.visibleSessions.contains { $0.id == session.id })
        #expect(model.selectedSessionID == session.id && model.hasUnsavedLayout)
        try sql("DROP TRIGGER reject_create_layout", path); model.retryLayoutSave()
        #expect(!model.hasUnsavedLayout)
    }
    @Test(arguments: ["note", "region", "resize"], ["layer", "state", "geometry"])
    func obsoleteGestureCannotCommitAfterContextChanges(kind: String, change: String) throws {
        _ = NSApplication.shared
        let model = fixture(); defer { model.shutdown() }
        let canvas = CanvasNSView(model: model); canvas.frame = NSRect(x: 0, y: 0, width: 1100, height: 700)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas; canvas.update()
        let world = kind == "note" ? Point(30, 100) : kind == "region" ? Point(380, 20) : Point(750, 570)
        let start = model.workspace.viewport.screen(world)
        canvas.mouseDown(with: try event(.leftMouseDown, start, canvas))
        switch change {
        case "layer": model.selectLayer(.inactive)
        case "state": model.workspace.sessions[0].execution = .unknown; model.updateActivityTime()
        default: model.editRegion(id: "a", rect: Rect(-800, 0, 760, 580))
        }
        let before = model.workspace
        canvas.mouseDragged(with: try event(.leftMouseDragged, start + Point(80, 40), canvas))
        canvas.mouseUp(with: try event(.leftMouseUp, start + Point(80, 40), canvas))
        #expect(model.workspace.placements == before.placements && model.workspace.regions == before.regions)
        #expect(model.workspace.sessions == before.sessions)
    }
    @Test(arguments: [1.0, 0.42, 0.25, 0.03])
    func projectMovesIgnoreInactiveGeometryAndCancelStaleGestures(zoom: Double) throws {
        _ = NSApplication.shared
        let model = fixture(); defer { model.shutdown() }
        model.workspace.viewport = Viewport(origin: Point(40, 60), zoom: zoom)
        let canvas = CanvasNSView(model: model); canvas.frame = NSRect(x: 0, y: 0, width: 1100, height: 700)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas; canvas.update()
        let inactiveBefore = model.workspace.layerState?.layouts[.inactive]
        let start = model.workspace.viewport.screen(zoom <= 0.25 ? Point(380, 290) : Point(380, 20))
        let end = start + Point(1000 * zoom, 0)
        canvas.mouseDown(with: try event(.leftMouseDown, start, canvas))
        canvas.mouseDragged(with: try event(.leftMouseDragged, end, canvas))
        canvas.mouseUp(with: try event(.leftMouseUp, end, canvas))
        #expect(abs((model.workspace.regions["a"]?.x ?? 0) - 1000) < 0.000001)
        #expect(model.workspace.layerState?.layouts[.inactive] == inactiveBefore)
        #expect(model.errorMessage == nil)
        let activeBefore = model.workspace.placements
        canvas.mouseDown(with: try event(.leftMouseDown, start + Point(1000 * zoom, 0), canvas))
        model.selectLayer(.inactive)
        canvas.mouseDragged(with: try event(.leftMouseDragged, end + Point(100, 30), canvas))
        canvas.mouseUp(with: try event(.leftMouseUp, end + Point(100, 30), canvas))
        #expect(model.workspace.layerState?.layouts[.active]?.placements == activeBefore)
        #expect(model.workspace.layerState?.layouts[.inactive] == inactiveBefore)
    }
    @Test func sourceWideBulkReviewFromInactiveAndLayerCountsIgnoreFilters() async throws {
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        await model.connect(); defer { model.shutdown() }
        model.setIdleTimeout(.fifteenMinutes)
        for i in model.workspace.sessions.indices { model.workspace.sessions[i].updatedAt = Date().addingTimeInterval(-3600) }
        model.workspace.sessions.append(Session(id: "unknown", title: "Uncertain", latestResult: SessionResult(id: "unread", outcome: .failed, text: "")))
        model.persist(); model.selectLayer(.inactive)
        let counts = model.layerCounts
        model.search = "no match"; model.setStateVisible(.unknown, false)
        #expect(model.visibleSessions.isEmpty && model.layerCounts == counts)
        model.acknowledgeAll()
        #expect(model.selectedLayer == .inactive && model.acknowledgeAllCount == 0)
        #expect(model.layerCounts[.stale] == 3)
        #expect(model.acknowledgments["unknown"] == nil)
    }
    @Test func overviewFitAndAccessibilityAreExclusiveAndRestoreIndependentViewports() throws {
        _ = NSApplication.shared
        let model = fixture(); defer { model.shutdown() }
        let canvas = CanvasNSView(model: model); canvas.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        for layer in [CanvasLayer.active, .inactive] {
            model.selectLayer(layer); model.workspace.viewport = Viewport(origin: Point(40, 60), zoom: 0.25)
            canvas.update()
            let labels = (canvas.accessibilityChildren() as? [NSAccessibilityElement])?.compactMap { $0.accessibilityLabel() } ?? []
            #expect(labels.count == 1)
            #expect(labels[0].contains(layer == .active ? "Alpha" : "Archived project"))
            canvas.fitContent()
            #expect(model.workspace.viewport.zoom > 0.5)
        }
        let inactiveViewport = model.workspace.viewport
        model.selectLayer(.active); let activeViewport = model.workspace.viewport
        model.selectLayer(.inactive); #expect(model.workspace.viewport == inactiveViewport)
        model.selectLayer(.active); #expect(model.workspace.viewport == activeViewport)
        model.selectLayer(.stale); canvas.update(); #expect(canvas.accessibilityChildren()?.isEmpty == true)
    }
    @Test func automaticSaveFailureRetainsSourceFactsAndManualEditFailureRetainsGeometry() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let model = ApplicationModel(demo: true, storagePath: path)
        await model.connect(); defer { model.shutdown() }
        let saved = try CanvasDatabase(path: path).load(source: model.sourceID)
        try sql("CREATE TRIGGER reject_layout BEFORE UPDATE ON workspace BEGIN SELECT RAISE(ABORT,'fixture'); END", path)
        let geometry = model.workspace.placements
        model.editRegion(id: "canvas", rect: Rect(-1000, 0, 540, 440))
        #expect(model.workspace.placements == geometry)
        let index = try #require(model.workspace.sessions.firstIndex { $0.id == "demo-native" })
        model.workspace.sessions[index].execution = .unknown; model.persist()
        #expect(model.hasUnsavedLayout && model.workspace.sessions[index].execution == .unknown)
        #expect(model.workspace.layerState?.assignments["demo-native"] == .inactive)
        #expect(try CanvasDatabase(path: path).load(source: model.sourceID) == saved)
        try sql("DROP TRIGGER reject_layout", path); model.retryLayoutSave()
        #expect(!model.hasUnsavedLayout)
        #expect(try CanvasDatabase(path: path).load(source: model.sourceID).layerState?.assignments["demo-native"] == .inactive)
    }
    private func fixture() -> ApplicationModel {
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        model.workspace.projects = [Project(id: "a", name: "Alpha"), Project(id: "archive", name: "Archived project")]
        model.workspace.sessions = [Session(id: "active", title: "Current", projectID: "a", execution: .running),
                                    Session(id: "archived", title: "Old", projectID: "archive", execution: .idle, isArchived: true)]
        model.workspace.regions = ["a": Rect(0, 0, 760, 580), "archive": Rect(1000, 0, 760, 580)]
        model.workspace.placements = ["active": Placement(Point(20, 64)), "archived": Placement(Point(1020, 64))]
        model.synchronizeLayers()
        return model
    }
    private func event(_ type: NSEvent.EventType, _ point: Point, _ canvas: NSView) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: canvas.convert(NSPoint(x: point.x, y: point.y), to: nil), modifierFlags: [], timestamp: 0,
                                       windowNumber: canvas.window?.windowNumber ?? 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }
    private func sql(_ statement: String, _ path: String) throws {
        var db: OpaquePointer?; #expect(sqlite3_open(path, &db) == SQLITE_OK); defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, statement, nil, nil, nil) == SQLITE_OK)
    }
}
