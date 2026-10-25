import Foundation
import Testing
@testable import CanvasCore

@Suite struct CanvasRearrangerTests {
    @Test func projectsPrecedeUnassignedAndNotesSortByStateActivityAndIdentity() throws {
        var workspace = Workspace()
        workspace.projects = [Project(id: "p", name: "First"), Project(id: "q", name: "Second")]
        workspace.regions = ["p": Rect(5000, 7000, 760, 580), "q": Rect(-4000, -8000, 760, 580)]
        workspace.sessions = [note("idle", execution: .idle, age: 900), note("run-old", execution: .running, age: 100),
                              note("run-new", execution: .running, age: 900), note("run-tie-b", execution: .running, age: 500),
                              note("run-tie-a", execution: .running, age: 500), note("unknown", age: 1000),
                              note("p-idle", project: "p", execution: .idle, age: 1000), note("p-run", project: "p", execution: .running),
                              note("q-run", project: "q", execution: .running)]
        for (i, session) in workspace.sessions.enumerated() { workspace.placements[session.id] = Placement(Point(Double(i) * 300, 20000)) }
        workspace.viewport = Viewport(origin: Point(700, -900), zoom: 0.03)
        let result = try CanvasRearranger.arrange(workspace, visibleSessionIDs: Set(workspace.sessions.map(\.id)))
        #expect(result.sessions == workspace.sessions)
        #expect(result.projects == workspace.projects)
        #expect(result.viewport == workspace.viewport)
        #expect(result.regions["p"]!.x < result.regions["q"]!.x)
        let bottom = result.regions.values.map { $0.y + $0.height }.max()!
        for session in result.sessions where session.projectID == nil { #expect(result.placements[session.id]!.position.y > bottom) }
        #expect(orderedIDs(result, project: nil) == ["run-new", "run-tie-a", "run-tie-b", "run-old", "idle", "unknown"])
        #expect(orderedIDs(result, project: "p") == ["p-run", "p-idle"])
        try verify(result, moving: Set(workspace.sessions.map(\.id)))
        #expect(try CanvasRearranger.arrange(result, visibleSessionIDs: Set(workspace.sessions.map(\.id))) == result)
    }

    @Test func hiddenNotesStayFixedAndVisibleOverlapsAreRepaired() throws {
        var workspace = Workspace()
        workspace.projects = [Project(id: "p", name: "Pinned"), Project(id: "q", name: "Movable")]
        workspace.regions = ["p": Rect(0, 0, 760, 580), "q": Rect(5000, 0, 760, 580)]
        workspace.sessions = [note("p-hidden", project: "p"), note("p-visible", project: "p", execution: .running),
                              note("q-visible", project: "q", execution: .running), note("hidden"), note("visible", execution: .running)]
        workspace.placements = ["p-hidden": Placement(Point(16, 64)), "p-visible": Placement(Point(16, 64)),
                                "q-visible": Placement(Point(5100, 100)), "hidden": Placement(Point(0, 700)), "visible": Placement(Point(0, 700))]
        let moving: Set<String> = ["p-visible", "q-visible", "visible"]
        let result = try CanvasRearranger.arrange(workspace, visibleSessionIDs: moving)
        #expect(result.placements["p-hidden"] == workspace.placements["p-hidden"])
        #expect(result.placements["hidden"] == workspace.placements["hidden"])
        #expect(result.regions["p"]!.x == workspace.regions["p"]!.x)
        #expect(result.regions["p"]!.y == workspace.regions["p"]!.y)
        #expect(result.placements["p-visible"] != workspace.placements["p-visible"])
        try verify(result, moving: moving)
        #expect(try CanvasRearranger.arrange(result, visibleSessionIDs: moving) == result)
    }

    @Test func obstacleJumpsHandleTallHiddenRegionsWithoutScanningEveryRow() throws {
        var workspace = Workspace()
        workspace.projects = [Project(id: "hidden-project", name: "Hidden")]
        workspace.regions = ["hidden-project": Rect(-10, -10, 1600, 10000000)]
        workspace.sessions = (0..<300).map { note("s\($0)", execution: .running, age: Double($0)) }
        let ids = Set(workspace.sessions.map(\.id))
        let result = try CanvasRearranger.arrange(workspace, visibleSessionIDs: ids)
        #expect(result.placements.values.allSatisfy { $0.position.y >= 9999990 })
        try verify(result, moving: ids)
    }

    @Test func noVisibleSessionsDoesNotChangeGeometry() throws {
        var workspace = Workspace()
        workspace.sessions = [note("hidden")]
        workspace.placements["hidden"] = Placement(Point(-300, 500))
        #expect(try CanvasRearranger.arrange(workspace, visibleSessionIDs: []) == workspace)
    }

    @Test func everyAttentionStateAndAcknowledgmentAffectsGrouping() throws {
        var workspace = Workspace()
        workspace.sessions = NoteState.allCases.map { state in
            var session = note(state.rawValue, execution: .idle)
            switch state {
            case .running: session.execution = .running
            case .waiting: session.requests = ["q": .input]
            case .permission: session.requests = ["p": .permission]
            case .finished:
                session.latestResult = SessionResult(id: "r", outcome: .completed, text: "Done")
                session.updatedAt = Date(timeIntervalSince1970: 0.5)
            case .unknown: session.execution = .unknown
            case .archived: session.archived = true
            case .idle: break
            }
            return session
        }
        let ids = Set(workspace.sessions.map(\.id))
        let result = try CanvasRearranger.arrange(workspace, visibleSessionIDs: ids)
        #expect(orderedIDs(result, project: nil) == NoteState.allCases.map(\.rawValue))
        let reviewed = try CanvasRearranger.arrange(workspace, visibleSessionIDs: ids, acknowledgments: ["finished": ["r"]])
        #expect(orderedIDs(reviewed, project: nil) == ["running", "waiting", "permission", "idle", "finished", "archived", "unknown"])
        #expect(reviewed.sessions == workspace.sessions)
    }

    @Test func blockedPinnedProjectsAndInvalidGeometryFailWithoutMutatingInput() throws {
        var workspace = Workspace()
        workspace.projects = [Project(id: "p", name: "Pinned")]
        workspace.regions = ["p": Rect(0, 0, 300, 240), "below": Rect(0, 240, 300, 240), "right": Rect(300, 0, 300, 240)]
        workspace.sessions = [note("hidden", project: "p"), note("visible", project: "p", execution: .running)]
        workspace.placements = ["hidden": Placement(Point(16, 64)), "visible": Placement(Point(16, 64))]
        let original = workspace
        #expect(throws: (any Error).self) { try CanvasRearranger.arrange(workspace, visibleSessionIDs: ["visible"]) }
        #expect(workspace == original)
        workspace.placements["visible"] = Placement(Point(.nan, 0))
        #expect(throws: (any Error).self) { try CanvasRearranger.arrange(workspace, visibleSessionIDs: ["visible"]) }
    }

    private func note(_ id: String, project: String? = nil, execution: Execution = .unknown, age: Double = 1) -> Session {
        Session(id: id, title: id, projectID: project, execution: execution, updatedAt: Date(timeIntervalSince1970: age))
    }
    private func orderedIDs(_ workspace: Workspace, project: String?) -> [String] {
        workspace.sessions.filter { $0.projectID == project }.sorted {
            let a = workspace.placements[$0.id]!.position, b = workspace.placements[$1.id]!.position
            return a.y == b.y ? a.x < b.x : a.y < b.y
        }.map(\.id)
    }
    private func verify(_ workspace: Workspace, moving: Set<String>) throws {
        for session in workspace.sessions {
            guard let placement = workspace.placements[session.id] else { continue }
            #expect(workspace.project(at: placement.center) == session.projectID)
            if moving.contains(session.id) {
                #expect(workspace.placements.allSatisfy { $0.key == session.id || !placement.rect.intersects($0.value.rect) })
            }
        }
    }
}
