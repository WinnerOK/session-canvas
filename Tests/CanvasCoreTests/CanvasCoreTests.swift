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
    @Test func testZoomPreservesPointUnderCursor() {
        var viewport = Viewport(origin: Point(-230, 120), zoom: 0.7)
        let pointer = Point(480, 290), before = viewport.world(Point(480, 290))
        viewport.zoom(to: 1.8, around: pointer)
        expectEqual(viewport.world(pointer).x, before.x, accuracy: 0.000001)
        expectEqual(viewport.world(pointer).y, before.y, accuracy: 0.000001)
    }
    @Test func testRegionBordersAreUnassigned() {
        var workspace = Workspace()
        workspace.regions["a"] = Rect(0, 0, 760, 580)
        expectEqual(workspace.project(at: Point(200, 200)), "a")
        for point in [Point(0, 200), Point(760, 200), Point(200, 0), Point(200, 580)] { expectNil(workspace.project(at: point)) }
    }
    @Test func testNearestPlacementKeepsMembershipAtProjectBoundaries() {
        var workspace = Workspace()
        workspace.regions["p"] = Rect(0, 0, 760, 580)
        let unassigned = workspace.vacantPlacement(projectID: nil, near: Point(0, 0))
        expectEqual(unassigned.position, Point(0, -75))
        expectNil(workspace.project(at: unassigned.center))
        let member = workspace.vacantPlacement(projectID: "p", near: Point(700, 100))
        expectEqual(member.position, Point(643, 100))
        expectEqual(workspace.project(at: member.center), "p")
    }
    @Test func testNearestPlacementAvoidsMultipleObstaclesWithoutMovingThem() {
        var workspace = Workspace()
        workspace.placements = ["a": Placement(Point(-8080, -4530)), "b": Placement(Point(-8200, -4380))]
        let original = workspace.placements
        let placement = workspace.vacantPlacement(projectID: nil, near: Point(-8000, -4500))
        expectEqual(placement.position, Point(-7968, -4380))
        expectFalse(workspace.placements.values.contains { $0.rect.intersects(placement.rect) })
        expectEqual(workspace.placements, original)
    }
    @Test func testHistoryConnectionNeverClaimsLiveState() throws {
        let value = try json(#"{"id":"s","status":{"type":"active","activeFlags":["waitingOnApproval"]},"turns":[]}"#)
        expectEqual(try CodexWire.session(value, live: false).state(acknowledged: []), .unknown)
        expectEqual(try CodexWire.session(value, live: true).state(acknowledged: []), .permission)
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
private func expectFalse(_ condition: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(!condition, sourceLocation: sourceLocation)
}
private func expectNil<T>(_ value: T?, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(value == nil, sourceLocation: sourceLocation)
}
