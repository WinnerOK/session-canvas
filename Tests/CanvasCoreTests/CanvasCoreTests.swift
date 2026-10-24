import Testing
import Foundation
@testable import CanvasCore

@Suite
struct CanvasCoreTests {
    @Test func testAttentionPriorityAndUnknownEvidence() {
        var session = Session(id: "s", title: "State", execution: .running, requests: ["q": .input, "p": .permission], latestResult: result("a"))
        expectEqual(session.state(acknowledged: []), .permission)
        session.requests.removeValue(forKey: "p")
        expectEqual(session.state(acknowledged: []), .waiting)
        session.requests.removeAll()
        expectEqual(session.state(acknowledged: []), .running)
        session.execution = .idle
        expectEqual(session.state(acknowledged: []), .finished)
        expectEqual(session.state(acknowledged: ["a"]), .idle)
        session.execution = .unknown
        expectEqual(session.state(acknowledged: ["a"]), .unknown)
    }
    @Test func testAcknowledgingOlderResultDoesNotDismissNewerOne() {
        let session = Session(id: "s", title: "Race", execution: .idle, latestResult: result("b"))
        expectEqual(session.state(acknowledged: ["a"]), .finished)
        expectEqual(session.state(acknowledged: ["a", "b"]), .idle)
    }
    @Test func testAcknowledgmentCannotClearNewExecutionOrPermission() {
        var session = Session(id: "s", title: "Race", execution: .running, latestResult: result("a"))
        expectEqual(session.state(acknowledged: ["a"]), .running)
        session.requests["p"] = .permission
        expectEqual(session.state(acknowledged: ["a"]), .permission)
    }
    @Test func testEachFailureAndStopNeedsReview() {
        for outcome in [Outcome.completed, .failed, .stopped] {
            let session = Session(id: "s", title: "Outcome", execution: .idle, latestResult: SessionResult(id: "r", outcome: outcome, text: ""))
            expectEqual(session.state(acknowledged: []), .finished)
        }
    }
    @Test func testFreshSessionIsIdleAndEmptyTitleHasFallback() {
        let session = Session(id: "s", title: "", execution: .idle)
        expectEqual(session.title, "Untitled session")
        expectEqual(session.state(acknowledged: []), .idle)
    }
    @Test func testZoomPreservesPointUnderCursor() {
        var viewport = Viewport(origin: Point(-230, 120), zoom: 0.7)
        let pointer = Point(480, 290), before = viewport.world(Point(480, 290))
        viewport.zoom(to: 1.8, around: pointer)
        expectEqual(viewport.world(pointer).x, before.x, accuracy: 0.000001)
        expectEqual(viewport.world(pointer).y, before.y, accuracy: 0.000001)
    }
    @Test func testViewportRoundTripSupportsNegativeCoordinates() {
        let viewport = Viewport(origin: Point(100, -80), zoom: 1.3), world = Point(-500, -320)
        let roundTrip = viewport.world(viewport.screen(world))
        expectEqual(roundTrip.x, world.x, accuracy: 0.000001)
        expectEqual(roundTrip.y, world.y, accuracy: 0.000001)
    }
    @Test func testRegionBordersAreUnassigned() {
        var workspace = Workspace()
        workspace.regions["a"] = Rect(0, 0, 760, 580)
        expectEqual(workspace.project(at: Point(200, 200)), "a")
        for point in [Point(0, 200), Point(760, 200), Point(200, 0), Point(200, 580)] { expectNil(workspace.project(at: point)) }
    }
    @Test func testPartialOverlapDoesNotChooseProject() {
        var workspace = Workspace(); workspace.regions["a"] = Rect(0, 0, 760, 580)
        let placement = Placement(Point(-150, 100))
        expectTrue(placement.rect.intersects(workspace.regions["a"]!))
        expectNil(workspace.project(at: placement.center))
    }
    @Test func testRegionMoveMustNotSweepNonmembersOrOverlap() {
        var workspace = Workspace()
        workspace.sessions = [Session(id: "m", title: "Member", projectID: "a"), Session(id: "u", title: "Other")]
        workspace.regions = ["a": Rect(0, 0, 760, 580), "b": Rect(900, 0, 760, 580)]
        workspace.placements = ["m": Placement(Point(20, 64)), "u": Placement(Point(20, 700))]
        expectFalse(workspace.validateRegion(id: "a", rect: Rect(0, 0, 760, 1000), memberPositions: [:]))
        expectFalse(workspace.validateRegion(id: "a", rect: Rect(600, 0, 760, 580), memberPositions: ["m": Placement(Point(620, 64))]))
        expectTrue(workspace.validateRegion(id: "a", rect: Rect(-800, 0, 760, 580), memberPositions: ["m": Placement(Point(-780, 64))]))
    }
    @Test func testRegionCannotShrinkPastMemberOrMinimum() {
        var workspace = Workspace()
        workspace.sessions = [Session(id: "m", title: "Member", projectID: "a")]
        workspace.regions["a"] = Rect(0, 0, 760, 580)
        workspace.placements["m"] = Placement(Point(480, 350))
        expectFalse(workspace.validateRegion(id: "a", rect: Rect(0, 0, 320, 240), memberPositions: [:]))
        expectFalse(workspace.validateRegion(id: "a", rect: Rect(0, 0, 200, 100), memberPositions: [:]))
    }
    @Test func testDiscoveryDoesNotMoveExistingNotesOrMergeSameTitles() {
        var workspace = Workspace()
        let a = Session(id: "a", title: "Same"), b = Session(id: "b", title: "Same")
        workspace.reconcile(sessions: [a], projects: [])
        let original = workspace.placements["a"]
        workspace.reconcile(sessions: [a, b], projects: [])
        expectEqual(workspace.placements["a"], original)
        expectEqual(workspace.placements.count, 2)
        expectFalse(workspace.placements["a"]!.rect.intersects(workspace.placements["b"]!.rect))
    }
    @Test func testExternalMembershipChangeRelocatesOnlyAffectedNote() {
        var workspace = Workspace()
        var a = Session(id: "a", title: "A", projectID: "p"), b = Session(id: "b", title: "B")
        let projects = [Project(id: "p", name: "Project")]
        workspace.reconcile(sessions: [a, b], projects: projects)
        let bPosition = workspace.placements["b"]
        a.projectID = nil
        workspace.reconcile(sessions: [a, b], projects: projects)
        expectNil(workspace.project(at: workspace.placements["a"]!.center))
        expectEqual(workspace.placements["b"], bPosition)
    }
    @Test func testLargeProjectGrowsWithoutMisclassifyingMembers() {
        var workspace = Workspace()
        let projects = [Project(id: "p", name: "Project")]
        workspace.reconcile(sessions: [Session(id: "u", title: "Unassigned")], projects: projects)
        let members = (0..<24).map { Session(id: "m\($0)", title: "Member", projectID: "p") }
        workspace.reconcile(sessions: workspace.sessions + members, projects: projects)
        for member in members { expectEqual(workspace.project(at: workspace.placements[member.id]!.center), "p") }
        expectNil(workspace.project(at: workspace.placements["u"]!.center))
    }
    @Test func testDatabaseRestoresWorkspaceAndIsolatesSources() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        var workspace = Workspace(); workspace.placements["s"] = Placement(Point(-123, 940))
        workspace.viewport = Viewport(origin: Point(44, -99), zoom: 0.8)
        do {
            let db = try CanvasDatabase(path: path)
            try db.save(workspace, source: "real")
            try db.acknowledge(source: "real", session: "s", result: "a")
            try db.acknowledge(source: "real", session: "s", result: "a")
        }
        let db = try CanvasDatabase(path: path)
        expectEqual(try db.load(source: "real"), workspace)
        expectEqual(try db.acknowledgments(source: "real")["s"], ["a"])
        expectTrue(try db.load(source: "demo").placements.isEmpty)
        expectTrue(try db.acknowledgments(source: "demo").isEmpty)
    }
    @Test func testReadOnlyStorageFailureIsNotReportedAsAcknowledged() throws {
        let db = try CanvasDatabase(path: ":memory:")
        expectNoThrow(try db.acknowledge(source: "s", session: "s", result: "r"))
        expectThrows(try CanvasDatabase(path: "/nonexistent-session-canvas-folder/canvas.sqlite"))
    }
    @Test func testWireNeverTreatsUnloadedAsIdle() throws {
        let value = try json(#"{"id":"s","name":"Session","status":{"type":"notLoaded"},"turns":[]}"#)
        expectEqual(try CodexWire.session(value, live: true).execution, .unknown)
    }
    @Test func testHistoryConnectionNeverClaimsLiveState() throws {
        let value = try json(#"{"id":"s","status":{"type":"active","activeFlags":["waitingOnApproval"]},"turns":[]}"#)
        expectEqual(try CodexWire.session(value, live: false).state(acknowledged: []), .unknown)
        expectEqual(try CodexWire.session(value, live: true).state(acknowledged: []), .permission)
    }
    @Test func testCompletedQuestionIsNotBlockingInput() throws {
        let value = try json(#"{"id":"s","status":{"type":"idle"},"turns":[{"id":"t","status":"completed","items":[{"id":"m","type":"agentMessage","text":"What do you think?"}]}]}"#)
        let session = try CodexWire.session(value, live: true)
        expectTrue(session.requests.isEmpty)
        expectEqual(session.state(acknowledged: []), .finished)
        expectEqual(session.latestResult?.id, "s/t/completed")
    }
    @Test func testWireTerminalResultsAreStableAndInProgressIsNotFinished() throws {
        let turn = try json(#"{"id":"t","status":"failed","error":{"message":"Failure"},"items":[]}"#)
        expectEqual(CodexWire.result(turn, sessionID: "s"), CodexWire.result(turn, sessionID: "s"))
        expectEqual(CodexWire.result(turn, sessionID: "s")?.outcome, .failed)
        expectNil(CodexWire.result(try json(#"{"id":"t","status":"inProgress","items":[]}"#), sessionID: "s"))
    }
    @Test func testHistoryExcludesToolPayloadsAndRetainsResultIdentity() throws {
        let turn = try json(#"{"id":"t","status":"completed","items":[{"id":"u","type":"userMessage","content":[{"type":"text","text":"Hello"}]},{"id":"tool","type":"commandExecution","aggregatedOutput":"private tool data"},{"id":"a","type":"agentMessage","text":"Done"}]}"#)
        let entries = CodexWire.history([turn], sessionID: "s")
        expectEqual(entries.count, 3)
        expectFalse(entries.contains { $0.text.contains("private tool data") })
        expectEqual(entries.last?.result?.id, "s/t/completed")
    }
    private func result(_ id: String) -> SessionResult { SessionResult(id: id, outcome: .completed, text: "Done") }
    private func json(_ value: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(value.utf8)) }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(actual == expected, sourceLocation: sourceLocation)
}
private func expectEqual(_ actual: Double, _ expected: Double, accuracy: Double, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(abs(actual - expected) <= accuracy, sourceLocation: sourceLocation)
}
private func expectTrue(_ condition: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(condition, sourceLocation: sourceLocation)
}
private func expectFalse(_ condition: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(!condition, sourceLocation: sourceLocation)
}
private func expectNil<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(value == nil, sourceLocation: sourceLocation)
}
private func expectNoThrow(_ expression: @autoclosure () throws -> Void, sourceLocation: SourceLocation = #_sourceLocation) {
    do { try expression() } catch { Issue.record("Unexpected error: \(error)", sourceLocation: sourceLocation) }
}
private func expectThrows<T>(_ expression: @autoclosure () throws -> T, sourceLocation: SourceLocation = #_sourceLocation) {
    do { _ = try expression(); Issue.record("Expected an error", sourceLocation: sourceLocation) } catch {}
}
