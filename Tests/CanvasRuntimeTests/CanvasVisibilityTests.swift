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
        model.setIdleTimeout(.oneWeek)
        model.setHideUnknown(false)
        model.setStateVisible(.archived, true)
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
        var all = CanvasVisibility(); all.hiddenStates = []
        #expect(try database.visibility(source: restored.sourceID) == all)
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

    @Test func idleTimeoutReevaluatesWithTimeAndNewActivityWithoutMovingNotes() {
        let model = fixture()
        defer { model.shutdown() }
        let now = Date(timeIntervalSince1970: 10000000)
        for i in model.workspace.sessions.indices { model.workspace.sessions[i].updatedAt = now.addingTimeInterval(-3599) }
        let original = model.workspace
        model.updateActivityTime(now: now)
        model.setIdleTimeout(.oneHour)
        #expect(model.visibleSessions.count == 6)
        model.selectedSessionID = "idle"
        model.updateActivityTime(now: now.addingTimeInterval(1))
        #expect(!model.visibleSessions.contains { $0.id == "idle" })
        #expect(model.selectedSessionID == nil)
        #expect(model.visibleSessions.count == 4)
        #expect(!model.visibleSessions.contains { $0.id == "unknown" })
        #expect(model.workspace == original)
        let i = model.workspace.sessions.firstIndex { $0.id == "idle" }!
        model.workspace.sessions[i].updatedAt = now
        #expect(model.visibleSessions.contains { $0.id == "idle" })
        model.workspace.sessions[i].execution = .running
        model.workspace.sessions[i].updatedAt = now.addingTimeInterval(-86400)
        #expect(model.visibleSessions.contains { $0.id == "idle" })
    }

    @Test func archiveAndRestorePreserveIdentityGeometryAndAcknowledgment() async throws {
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        await model.connect()
        defer { model.shutdown() }
        let session = try #require(model.workspace.sessions.first { $0.id == "demo-state" })
        #expect(!model.canArchive(session))
        await model.toggleArchive(session.id)
        #expect(model.workspace.sessions.first { $0.id == session.id }?.isArchived == false)
        model.openSession(session.id)
        await model.loadHistory(older: false)
        let result = try #require(model.history.compactMap(\.result).last)
        model.acknowledge(result, sessionID: session.id)
        let original = model.workspace
        await model.toggleArchive(session.id)
        #expect(model.workspace.sessions.first { $0.id == session.id }?.isArchived == true)
        #expect(model.state(try #require(model.workspace.sessions.first { $0.id == session.id })) == .archived)
        #expect(!model.visibleSessions.contains { $0.id == session.id })
        #expect(model.workspace.placements == original.placements)
        #expect(model.workspace.regions == original.regions)
        #expect(model.selectedSessionID == nil)
        model.setStateVisible(.archived, true)
        #expect(model.visibleSessions.contains { $0.id == session.id })
        await model.toggleArchive(session.id)
        #expect(model.workspace.sessions.first { $0.id == session.id }?.isArchived == false)
        #expect(model.acknowledgments[session.id]?.contains(result.id) == true)
        #expect(model.workspace.sessions.first { $0.id == session.id }?.updatedAt == session.updatedAt)
        #expect(!model.canArchive(try #require(model.workspace.sessions.first { $0.id == "demo-native" })))
    }

    @Test func archivedUnknownSessionsUseTheirOwnAttentionFilterAndPreserveResults() {
        let model = fixture()
        defer { model.shutdown() }
        var archived = Session(id: "archived", title: "Old work", execution: .unknown,
                               latestResult: SessionResult(id: "unread", outcome: .stopped, text: "Stopped"),
                               updatedAt: Date(timeIntervalSince1970: 1), isArchived: true)
        archived.unknownReason = .historyMissing
        model.workspace.sessions.append(archived)
        model.workspace.placements[archived.id] = Placement(Point(-850, 0))
        let original = model.workspace
        #expect(model.state(archived) == .archived)
        #expect(model.stateCounts[.archived] == 1)
        #expect(model.stateCounts[.unknown] == 1)
        #expect(!model.visibleSessions.contains { $0.id == archived.id })
        model.setStateVisible(.unknown, false)
        model.setIdleTimeout(.oneHour)
        model.setStateVisible(.archived, true)
        #expect(model.visibleSessions.contains { $0.id == archived.id })
        #expect(!model.visibleSessions.contains { $0.id == "unknown" })
        model.openSession(archived.id)
        model.setStateVisible(.archived, false)
        #expect(model.selectedSessionID == nil)
        model.showAllAttentionStates()
        #expect(model.visibleSessions.contains { $0.id == archived.id })
        #expect(model.workspace == original)
        #expect(model.acknowledgments[archived.id]?.contains("unread") != true)
        let index = model.workspace.sessions.firstIndex { $0.id == archived.id }!
        model.workspace.sessions[index].archived = false
        #expect(model.state(model.workspace.sessions[index]) == .unknown)
        model.workspace.sessions[index].execution = .idle
        #expect(model.state(model.workspace.sessions[index]) == .finished)
    }

    @Test func hideUnknownUsesIdleAgeAndRestoresTheSameNoteAndProject() {
        let model = fixture()
        defer { model.shutdown() }
        let now = Date(timeIntervalSince1970: 2000000000)
        let index = model.workspace.sessions.firstIndex { $0.id == "unknown" }!
        model.workspace.sessions[index].updatedAt = now.addingTimeInterval(-3600)
        model.workspace.sessions[index].projectID = "old"
        model.workspace.projects.append(Project(id: "old", name: "Old sessions"))
        model.workspace.regions["old"] = Rect(-1000, -1000, 760, 580)
        model.workspace.placements["unknown"] = Placement(Point(-980, -936))
        model.updateActivityTime(now: now)
        let original = model.workspace
        model.setIdleTimeout(.oneHour)
        #expect(model.visibility.hideUnknown)
        #expect(!model.visibleSessions.contains { $0.id == "unknown" })
        #expect(!model.visibleProjects.contains { $0.id == "old" })
        model.setHideUnknown(false)
        #expect(model.visibleSessions.contains { $0.id == "unknown" })
        #expect(model.visibleProjects.contains { $0.id == "old" })
        model.openSession("unknown")
        model.setHideUnknown(true)
        #expect(model.selectedSessionID == nil)
        #expect(model.workspace == original)
        model.workspace.sessions[index].execution = .running
        #expect(model.visibleSessions.contains { $0.id == "unknown" })
        model.workspace.sessions[index].execution = .unknown
        model.workspace.sessions[index].latestResult = SessionResult(id: "result", outcome: .completed, text: "Done")
        #expect(model.visibleSessions.contains { $0.id == "unknown" })
        model.acknowledgments["unknown"] = ["result"]
        #expect(!model.visibleSessions.contains { $0.id == "unknown" })
        model.showAllSessions()
        #expect(model.visibleSessions.contains { $0.id == "unknown" })
        #expect(model.workspace.placements == original.placements)
        #expect(model.workspace.regions == original.regions)
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
