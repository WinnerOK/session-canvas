import AppKit
import Testing
import CanvasCore
@testable import SessionCanvas

@Suite(.serialized) @MainActor
struct CanvasVisibilityTests {
    @Test func attentionProjectAndSearchFiltersComposeWithoutChangingLayout() {
        let model = fixture()
        let original = model.workspace
        model.setStateVisible(.running, false)
        model.setStateVisible(.waiting, false)
        #expect(Set(model.visibleSessions.map(\.id)) == ["permission", "finished", "idle", "unknown"])
        #expect(model.stateCounts[.running] == 1)
        #expect(Set(model.visibleProjects.map(\.id)) == ["a", "b"])
        model.setStateVisible(.permission, false)
        #expect(model.visibleProjects.map(\.id) == ["b"])
        #expect(Set(model.visibleRegions.keys) == ["b"])
        model.setProjectVisible("b", false)
        #expect(Set(model.visibleSessions.map(\.id)) == ["idle", "unknown"])
        #expect(model.visibleProjects.isEmpty)
        model.search = "fresh"
        #expect(model.visibleSessions.map(\.id) == ["idle"])
        #expect(model.stateCounts[.unknown] == nil)
        model.search = ""
        for state in NoteState.allCases { model.setStateVisible(state, false) }
        #expect(model.visibleSessions.isEmpty)
        #expect(model.visibleProjects.isEmpty)
        model.showAllAttentionStates()
        #expect(model.visibility.hiddenProjectIDs == ["b"])
        #expect(Set(model.visibleSessions.map(\.id)) == ["running", "permission", "idle", "unknown"])
        model.showAllSessions()
        #expect(model.visibleSessions.count == 6)
        #expect(Set(model.visibleProjects.map(\.id)) == ["a", "b"])
        #expect(model.workspace == original)
    }

    @Test func visibilitySurvivesReopeningAndIsIsolatedBySource() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("canvas-visibility-" + UUID().uuidString + ".sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let model = ApplicationModel(demo: true, storagePath: path)
        await model.connect()
        let original = model.workspace
        model.setStateVisible(.running, false)
        model.setStateVisible(.unknown, false)
        model.setProjectVisible("research", false)
        let expected = model.visibility
        #expect(model.workspace == original)
        model.shutdown()
        let restored = ApplicationModel(demo: true, storagePath: path)
        await restored.connect()
        #expect(restored.visibility == expected)
        #expect(!restored.visibleSessions.contains { $0.projectID == "research" || restored.state($0) == .running })
        let database = try CanvasDatabase(path: path)
        #expect(try database.visibility(source: "another-source") == CanvasVisibility())
        restored.showAllSessions()
        #expect(try database.visibility(source: restored.sourceID) == CanvasVisibility())
        restored.shutdown()
    }

    @Test func emptyAndHiddenProjectsLeaveOverviewAccessibilityAndFitBounds() throws {
        _ = NSApplication.shared
        let model = fixture()
        model.workspace.viewport = Viewport(origin: Point(40, 40), zoom: 0.08)
        let canvas = CanvasNSView(model: model)
        canvas.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        model.setProjectVisible("b", false)
        canvas.update()
        let labels = (canvas.accessibilityChildren() as? [NSAccessibilityElement])?.compactMap { $0.accessibilityLabel() } ?? []
        #expect(labels.contains { $0.hasPrefix("Project Alpha,") })
        #expect(!labels.contains { $0.contains("Project Beta") || $0.contains("Empty project") })
        #expect(model.visibleRegions.keys.sorted() == ["a"])
        // Remove unassigned notes too, so the fit must use only Alpha, not distant hidden/empty regions.
        model.setStateVisible(.idle, false)
        model.setStateVisible(.unknown, false)
        canvas.fitContent()
        #expect(model.workspace.viewport.zoom > 0.75)
        model.setProjectVisible("a", false)
        canvas.update()
        #expect(canvas.accessibilityChildren()?.isEmpty == true)
        #expect(model.workspace.regions.count == 3)
    }

    @Test func acknowledgmentReevaluatesVisibilityAndClosesAHiddenViewer() async throws {
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        await model.connect()
        model.setStateVisible(.idle, false)
        model.openSession("demo-state")
        await model.loadHistory(older: false)
        let result = try #require(model.history.compactMap(\.result).last)
        model.acknowledge(result, sessionID: "demo-state")
        #expect(model.acknowledgments["demo-state"]?.contains(result.id) == true)
        #expect(!model.visibleSessions.contains { $0.id == "demo-state" })
        #expect(model.selectedSessionID == nil)
        model.openSession("demo-state")
        #expect(model.selectedSessionID == nil)
        model.setStateVisible(.idle, true)
        model.openSession("demo-state")
        #expect(model.selectedSessionID == "demo-state")
        model.search = "nothing matches"
        #expect(model.selectedSessionID == nil)
        model.shutdown()
    }

    @Test func droppingOnAnInvisibleRegionCannotChangeMembership() async throws {
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        await model.connect()
        let session = try #require(model.workspace.sessions.first { $0.id == "demo-native" })
        let original = model.workspace.placements[session.id]
        model.setProjectVisible("research", false)
        model.moveNote(id: session.id, position: Point(630, 246), expectedRevision: session.revision)
        #expect(model.workspace.placements[session.id] == original)
        #expect(model.workspace.sessions.first { $0.id == session.id }?.projectID == "canvas")
        #expect(model.pendingSessions.isEmpty)
        #expect(model.errorMessage != nil)
        model.shutdown()
    }

    private func fixture() -> ApplicationModel {
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        model.workspace.projects = [Project(id: "a", name: "Project Alpha"), Project(id: "b", name: "Project Beta"), Project(id: "empty", name: "Empty project")]
        model.workspace.regions = ["a": Rect(0, 0, 760, 580), "b": Rect(8000, 0, 760, 580), "empty": Rect(100000, 0, 760, 580)]
        model.workspace.sessions = [
            Session(id: "running", title: "Build service", projectID: "a", execution: .running),
            Session(id: "permission", title: "Approve command", projectID: "a", execution: .running, requests: ["p": .permission]),
            Session(id: "waiting", title: "Answer question", projectID: "b", execution: .running, requests: ["q": .input]),
            Session(id: "finished", title: "Review result", projectID: "b", execution: .idle, latestResult: SessionResult(id: "r", outcome: .completed, text: "Done")),
            Session(id: "idle", title: "Fresh session", execution: .idle),
            Session(id: "unknown", title: "Saved history")
        ]
        for (index, session) in model.workspace.sessions.enumerated() {
            let x = session.projectID == "a" ? 20.0 : session.projectID == "b" ? 8020.0 : -600.0
            model.workspace.placements[session.id] = Placement(Point(x, 64 + Double(index % 2) * 172))
        }
        return model
    }
}
