import Foundation
import Testing
import CanvasCore

@Suite struct DownwardGrowthTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func discoveryKeepsTargetAnchoredAndPushesOnlyTheBlockingChain() throws {
        var value = fixture()
        let original = value
        let arrival = Session(id: "new", title: "Arrival", projectID: "p", execution: .running, updatedAt: now)
        value.reconcile(sessions: value.sessions + [arrival], projects: value.projects)

        #expect(value.regions["p"] == Rect(0, 0, 300, 410))
        #expect(value.placements["a"] == original.placements["a"])
        #expect(value.placements["new"]?.position == Point(20, 236))
        for (project, member) in [("q", "b"), ("r", "c")] {
            let before = try #require(original.regions[project]), after = try #require(value.regions[project])
            let offset = Point(after.x - before.x, after.y - before.y)
            #expect(offset.x == 0 && offset.y > 0)
            #expect(after.width == before.width && after.height == before.height)
            #expect(value.placements[member]?.position == original.placements[member]!.position + offset)
        }
        #expect(value.placements["free"]!.position.y > original.placements["free"]!.position.y)
        #expect(value.placements["free"]!.position.x == original.placements["free"]!.position.x)
        #expect(value.regions["side"] == original.regions["side"])
        #expect(value.placements["side"] == original.placements["side"])
        #expect(value.viewport == original.viewport)
        #expect(value.sessions == original.sessions + [arrival])
        try expectValid(value)
    }

    @Test func protrudingProjectMembersTravelWithTheirRegion() throws {
        var value = fixture()
        value.projects = value.projects.filter { $0.id == "p" || $0.id == "q" }
        value.sessions = value.sessions.filter { $0.id == "a" || $0.id == "b" }
        value.regions = ["p": Rect(0, 0, 300, 240), "q": Rect(330, 250, 300, 240)]
        value.placements = ["a": Placement(Point(20, 64)), "b": Placement(Point(220, 314))]
        let original = value
        value.reconcile(sessions: value.sessions + [Session(id: "new", title: "New", projectID: "p")], projects: value.projects)

        let delta = value.regions["q"]!.y - original.regions["q"]!.y
        #expect(delta > 0)
        #expect(value.regions["q"]!.x == 330)
        #expect(value.placements["b"]?.position == original.placements["b"]!.position + Point(0, delta))
        try expectValid(value)
    }

    @Test func layeredBatchArrivalIncludesFilteredObstaclesAndSurvivesReopening() throws {
        var value = fixture()
        value.sessions.append(Session(id: "inactive", title: "Other layer", projectID: "p", isArchived: true))
        value.placements["inactive"] = Placement(Point(20, 64))
        value.reconcileLayers(acknowledgments: [:], now: now)
        var visibility = value.selectedVisibility
        visibility.hiddenProjectIDs = ["q"]
        visibility.hiddenStates = [.idle]
        value.setLayerVisibility(visibility)
        let original = value
        let arrivals = (0..<4).map { Session(id: "new\($0)", title: "New", projectID: "p", execution: .running, updatedAt: now) }
        value.reconcile(sessions: value.sessions + arrivals, projects: value.projects)
        value.reconcileLayers(acknowledgments: [:], now: now)

        #expect(value.regions["p"]!.x == 0 && value.regions["p"]!.y == 0)
        #expect(value.placements["a"] == original.placements["a"])
        #expect(value.regions["q"]!.y > original.regions["q"]!.y)
        #expect(value.layerState?.layouts[.inactive] == original.layerState?.layouts[.inactive])
        #expect(value.selectedVisibility == visibility)
        #expect(value.viewport == original.viewport)
        try expectValid(value.geometryProjection)

        let settled = value
        value.reconcileLayers(acknowledgments: [:], now: now)
        #expect(value == settled)
        let database = try CanvasDatabase(path: ":memory:")
        try database.save(value, source: "fixture")
        var reopened = try database.loadLayered(source: "fixture", now: now)
        reopened.reconcileLayers(acknowledgments: [:], now: now)
        #expect(reopened == value)

        value.sessions.removeAll { $0.id.hasPrefix("new") }
        value.reconcileLayers(acknowledgments: [:], now: now)
        #expect(value.regions == settled.regions)
        #expect(value.placements["b"] == settled.placements["b"])
    }

    @Test func simultaneousArrivalOrderDoesNotChangeThePlan() {
        var forward = fixture()
        forward.reconcileLayers(acknowledgments: [:], now: now)
        var reverse = forward
        let arrivals = (0..<6).map { Session(id: "new\($0)", title: "New", projectID: "p", execution: .idle, updatedAt: now) }
        forward.reconcile(sessions: forward.sessions + arrivals, projects: forward.projects)
        reverse.reconcile(sessions: Array((reverse.sessions + arrivals).reversed()), projects: reverse.projects)
        forward.reconcileLayers(acknowledgments: [:], now: now)
        reverse.reconcileLayers(acknowledgments: [:], now: now)
        #expect(forward.placements == reverse.placements)
        #expect(forward.regions == reverse.regions)
    }

    @Test func aPushedFreeNoteCanPushAHorizontallyOffsetProject() throws {
        var value = fixture()
        value.projects = value.projects.filter { $0.id == "p" || $0.id == "q" }
        value.sessions = value.sessions.filter { ["a", "b", "free"].contains($0.id) }
        value.regions = ["p": Rect(0, 0, 300, 240), "q": Rect(400, 500, 300, 240)]
        value.placements = ["a": Placement(Point(20, 64)), "b": Placement(Point(420, 564)), "free": Placement(Point(250, 250))]
        value.reconcile(sessions: value.sessions + [Session(id: "new", title: "New", projectID: "p")], projects: value.projects)
        #expect(value.regions["p"] == Rect(0, 0, 300, 410))
        #expect(value.placements["free"]?.position == Point(250, 434))
        #expect(value.regions["q"] == Rect(400, 608, 300, 240))
        #expect(value.placements["b"]?.position == Point(420, 672))
        try expectValid(value)
    }

    @Test func dormantProjectAndNoteRecordsDoNotJoinTheCascade() throws {
        var value = fixture()
        value.reconcileLayers(acknowledgments: [:], now: now)
        for index in value.sessions.indices where ["b", "free"].contains(value.sessions[index].id) {
            value.sessions[index].archived = true
        }
        value.reconcileLayers(acknowledgments: [:], now: now)
        let dormantRegion = value.layerState?.layouts[.active]?.regions["q"]
        let inactive = value.layerState?.layouts[.inactive]
        let nextProject = value.regions["r"]
        value.sessions.append(Session(id: "new", title: "New", projectID: "p", execution: .running, updatedAt: now))
        value.reconcileLayers(acknowledgments: [:], now: now)
        #expect(value.regions["p"] == Rect(0, 0, 300, 410))
        #expect(value.regions["q"] == nil && value.placements["free"] == nil)
        #expect(value.regions["r"] == nextProject)
        #expect(value.layerState?.layouts[.active]?.regions["q"] == dormantRegion)
        #expect(value.layerState?.layouts[.inactive] == inactive)
        try expectValid(value.geometryProjection)
    }

    private func fixture() -> Workspace {
        var value = Workspace()
        value.projects = ["p", "q", "r", "side"].map { Project(id: $0, name: $0) }
        value.sessions = [("a", "p"), ("b", "q"), ("c", "r"), ("side", "side")].map {
            Session(id: $0.0, title: $0.0, projectID: $0.1, execution: .idle, updatedAt: now)
        } + [Session(id: "free", title: "Free", execution: .idle, updatedAt: now)]
        value.regions = ["p": Rect(0, 0, 300, 240), "q": Rect(0, 250, 300, 240),
                         "r": Rect(0, 500, 300, 240), "side": Rect(400, 250, 300, 240)]
        value.placements = ["a": Placement(Point(20, 64)), "b": Placement(Point(20, 314)),
                            "c": Placement(Point(20, 564)), "side": Placement(Point(420, 314)),
                            "free": Placement(Point(20, 755))]
        value.viewport = Viewport(origin: Point(-100, 80), zoom: 0.7)
        return value
    }

    private func expectValid(_ value: Workspace) throws {
        for (id, rect) in value.regions {
            #expect(value.validateRegion(id: id, rect: rect, memberPositions: [:]))
        }
        for session in value.sessions {
            let placement = try #require(value.placements[session.id])
            #expect(value.project(at: placement.center) == session.projectID)
            #expect(value.placements.allSatisfy { $0.key == session.id || !placement.rect.intersects($0.value.rect) })
        }
    }
}
