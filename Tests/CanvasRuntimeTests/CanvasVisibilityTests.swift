import AppKit
import Testing
import CanvasCore
@testable import SessionCanvas

@Suite(.serialized) @MainActor
struct CanvasVisibilityTests {
    @Test func attentionProjectAndSearchFiltersComposeWithoutChangingLayout() {
        let model = fixture(); defer { model.shutdown() }
        let original = model.workspace
        model.setStateVisible(.running, false); model.setStateVisible(.waiting, false)
        #expect(Set(model.visibleSessions.map(\.id)) == ["permission", "finished", "idle"])
        #expect(model.stateCounts[.running] == 1)
        model.setStateVisible(.permission, false); #expect(model.visibleProjects.map(\.id) == ["b"])
        model.setProjectVisible("b", false); #expect(model.visibleSessions.map(\.id) == ["idle"])
        model.search = "fresh"; #expect(model.visibleSessions.map(\.id) == ["idle"])
        model.search = ""
        for state in model.selectedLayer.states { model.setStateVisible(state, false) }
        #expect(model.visibleSessions.isEmpty && model.visibleProjects.isEmpty)
        model.showAllAttentionStates(); #expect(model.visibility.hiddenProjectIDs == ["b"])
        #expect(Set(model.visibleSessions.map(\.id)) == ["running", "permission", "idle"])
        model.showAllSessions(); #expect(model.visibleSessions.count == 5)
        #expect(model.layerCounts[.inactive] == 1)
        #expect(model.workspace.placements == original.placements && model.workspace.regions == original.regions)
        #expect(model.workspace.sessions == original.sessions)
    }
    @Test func visibilitySurvivesReopeningAndIsIsolatedBySourceAndLayer() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let model = ApplicationModel(demo: true, storagePath: path)
        await model.connect()
        model.setStateVisible(.running, false); model.setProjectVisible("research", false); model.setIdleTimeout(.oneWeek)
        let expected = model.visibility
        model.selectLayer(.inactive); model.setStateVisible(.unknown, false); model.shutdown()
        let restored = ApplicationModel(demo: true, storagePath: path)
        await restored.connect(); defer { restored.shutdown() }
        #expect(restored.selectedLayer == .inactive && restored.visibility.hiddenStates == [.unknown])
        #expect(restored.visibility.hiddenProjectIDs.isEmpty)
        restored.selectLayer(.active); #expect(restored.visibility == expected)
        #expect(!restored.visibleSessions.contains { $0.projectID == "research" || restored.state($0) == .running })
        restored.showAllSessions()
        #expect(restored.visibility.idleTimeout == .oneWeek)
        #expect(restored.visibility.hiddenStates.isEmpty && restored.visibility.hiddenProjectIDs.isEmpty)
        #expect(try CanvasDatabase(path: path).loadLayered(source: "another-source").selectedVisibility.hiddenStates.isEmpty)
    }
    @Test func emptyAndHiddenProjectsLeaveOverviewAccessibilityAndFitBounds() {
        _ = NSApplication.shared
        let model = fixture(); defer { model.shutdown() }
        model.workspace.viewport = Viewport(origin: Point(40, 40), zoom: 0.08)
        let canvas = CanvasNSView(model: model); canvas.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        model.setProjectVisible("b", false); canvas.update()
        let labels = (canvas.accessibilityChildren() as? [NSAccessibilityElement])?.compactMap { $0.accessibilityLabel() } ?? []
        #expect(labels.contains { $0.hasPrefix("Project Alpha,") })
        #expect(!labels.contains { $0.contains("Project Beta") || $0.contains("Empty project") })
        model.setStateVisible(.idle, false); canvas.fitContent()
        #expect(model.workspace.viewport.zoom > 0.75)
        model.setProjectVisible("a", false); canvas.update()
        #expect(canvas.accessibilityChildren()?.isEmpty == true)
        #expect(model.workspace.regions.count == 2)
    }
    @Test func acknowledgmentReevaluatesVisibilityAndClosesAHiddenViewer() async throws {
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        await model.connect(); defer { model.shutdown() }
        model.setStateVisible(.idle, false)
        model.openSession("demo-state"); await model.loadHistory(older: false)
        let result = try #require(model.history.compactMap(\.result).last)
        model.acknowledge(result, sessionID: "demo-state")
        #expect(model.acknowledgments["demo-state"]?.contains(result.id) == true)
        #expect(!model.visibleSessions.contains { $0.id == "demo-state" } && model.selectedSessionID == nil)
        model.openSession("demo-state"); #expect(model.selectedSessionID == nil)
        model.setStateVisible(.idle, true); model.openSession("demo-state")
        #expect(model.selectedSessionID == "demo-state")
        model.search = "nothing matches"; #expect(model.selectedSessionID == nil)
    }
    @Test func droppingOnAnInvisibleRegionCannotChangeMembership() async throws {
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        await model.connect(); defer { model.shutdown() }
        let session = try #require(model.workspace.sessions.first { $0.id == "demo-native" })
        let original = model.workspace.placements[session.id]
        model.setProjectVisible("research", false)
        model.moveNote(id: session.id, position: Point(630, 246), expectedRevision: session.revision)
        #expect(model.workspace.placements[session.id] == original)
        #expect(model.workspace.sessions.first { $0.id == session.id }?.projectID == "canvas")
        #expect(model.pendingSessions.isEmpty && model.errorMessage != nil)
    }
    @Test func idleTimeoutRoutesToStaleAndRestoresRememberedPlacement() throws {
        let model = fixture(); defer { model.shutdown() }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        for i in model.workspace.sessions.indices { model.workspace.sessions[i].updatedAt = now.addingTimeInterval(-3599) }
        model.updateActivityTime(now: now); model.setIdleTimeout(.oneHour)
        let original = model.workspace.placements["idle"]
        #expect(model.visibleSessions.count == 5)
        model.selectedSessionID = "idle"; model.updateActivityTime(now: now.addingTimeInterval(1))
        #expect(model.visibleSessions.count == 4 && model.selectedSessionID == nil)
        #expect(model.layerCounts[.stale] == 1 && model.layerCounts[.inactive] == 1)
        model.selectLayer(.stale); #expect(model.visibleSessions.map(\.id) == ["idle"])
        let i = try #require(model.workspace.sessions.firstIndex { $0.id == "idle" })
        model.workspace.sessions[i].execution = .running; model.updateActivityTime(now: now.addingTimeInterval(1))
        #expect(model.selectedLayer == .stale && model.visibleSessions.isEmpty)
        model.selectLayer(.active); #expect(model.workspace.placements["idle"] == original)
        model.setIdleTimeout(.never); #expect(model.layerCounts[.stale, default: 0] == 0)
    }
    @Test func archiveAndRestorePreserveIdentityGeometryAndAcknowledgment() async throws {
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        await model.connect(); defer { model.shutdown() }
        let session = try #require(model.workspace.sessions.first { $0.id == "demo-state" })
        #expect(!model.canArchive(session))
        model.openSession(session.id); await model.loadHistory(older: false)
        let result = try #require(model.history.compactMap(\.result).last)
        model.acknowledge(result, sessionID: session.id)
        let original = model.workspace.placements[session.id]
        await model.toggleArchive(session.id)
        #expect(model.workspace.placements[session.id] == nil && model.selectedSessionID == nil)
        model.selectLayer(.inactive); #expect(model.visibleSessions.contains { $0.id == session.id })
        #expect(model.workspace.project(at: try #require(model.workspace.placements[session.id]).center) == session.projectID)
        await model.toggleArchive(session.id)
        #expect(model.selectedLayer == .inactive && !model.visibleSessions.contains { $0.id == session.id })
        model.selectLayer(.active); #expect(model.workspace.placements[session.id] == original)
        #expect(model.acknowledgments[session.id]?.contains(result.id) == true)
        #expect(model.workspace.sessions.first { $0.id == session.id }?.updatedAt == session.updatedAt)
    }
    @Test func archivedUnknownSessionsStayInactiveIndependentlyOfAgeAndUnreadEvidence() {
        let model = fixture(); defer { model.shutdown() }
        model.workspace.sessions.append(Session(id: "archived", title: "Old work", execution: .unknown,
            latestResult: SessionResult(id: "unread", outcome: .stopped, text: "Stopped"), updatedAt: Date(timeIntervalSince1970: 1), isArchived: true))
        model.updateActivityTime(); model.setIdleTimeout(.oneHour)
        #expect(model.stateCounts[.unknown] == nil && model.stateCounts[.archived] == nil)
        model.selectLayer(.inactive)
        #expect(model.stateCounts[.archived] == 1 && model.stateCounts[.unknown] == 1)
        model.setStateVisible(.unknown, false); #expect(model.visibleSessions.map(\.id) == ["archived"])
        model.showAllSessions(); #expect(model.visibleSessions.count == 2 && model.selectedLayer == .inactive)
        #expect(model.visibility.idleTimeout == .oneHour)
        #expect(model.acknowledgments["archived"]?.contains("unread") != true)
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
        model.synchronizeLayers()
        return model
    }
}
