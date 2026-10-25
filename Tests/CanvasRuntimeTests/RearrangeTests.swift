import Foundation
import Testing
import CSQLite
import CanvasCore
@testable import SessionCanvas

@Suite(.serialized) @MainActor
struct RearrangeTests {
    @Test func squareRearrangePersistsSeparateProjectAndUnassignedBlocks() async throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let model = ApplicationModel(demo: true, storagePath: path)
        defer { model.shutdown() }
        await model.connect()
        var fixture = Workspace()
        let groups: [(String?, Int)] = [("canvas", 12), ("research", 6), (nil, 6)]
        let now = Date()
        let sessions = groups.flatMap { project, count in
            (0..<count).map { index in
                Session(id: "\(project ?? "free")-\(index)", title: "\(project == nil ? "Independent session" : "Project session") \(index + 1)",
                        projectID: project, execution: .running, updatedAt: now.addingTimeInterval(Double(index)))
            }
        }
        fixture.reconcile(sessions: sessions, projects: model.workspace.projects)
        fixture.viewport = Viewport(origin: Point(30, 30), zoom: 0.5)
        model.workspace = fixture
        model.rearrange()
        #expect(model.errorMessage == nil)
        let arranged = model.workspace
        #expect(arranged.sessions == sessions)
        #expect(arranged.viewport == fixture.viewport)
        let free = sessions.filter { $0.projectID == nil }.map { arranged.placements[$0.id]!.rect }
        #expect(Set(free.map(\.x)).count == 2)
        #expect(Set(free.map(\.y)).count == 3)
        let projectBottom = arranged.regions.values.map { $0.y + $0.height }.max()!
        #expect(free.allSatisfy { $0.y > projectBottom })
        let project = arranged.regions["canvas"]!
        #expect(max(project.width / project.height, project.height / project.width) < 1.1)
        #expect(try CanvasDatabase(path: path).load(source: model.sourceID) == arranged)
        model.rearrange()
        #expect(model.workspace == arranged)
        model.shutdown()
        let restored = ApplicationModel(demo: true, storagePath: path)
        defer { restored.shutdown() }
        await restored.connect()
        #expect(restored.workspace.placements == arranged.placements)
        #expect(restored.workspace.regions == arranged.regions)
        #expect(restored.workspace.viewport == arranged.viewport)
    }

    @Test func rearrangeUsesVisibleProjectionAndPersistsWithoutChangingSourceFactsOrViewport() async throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let model = ApplicationModel(demo: true, storagePath: path)
        defer { model.shutdown() }
        await model.connect()
        let now = Date(timeIntervalSince1970: 2000000000)
        for index in model.workspace.sessions.indices where model.workspace.sessions[index].projectID == "canvas" {
            model.workspace.sessions[index].title = "Visible " + model.workspace.sessions[index].title
        }
        let extra = [Session(id: "free", title: "Visible free", execution: .running, updatedAt: now),
                     Session(id: "search-hidden", title: "Search hidden", execution: .running),
                     Session(id: "expired", title: "Visible expired", execution: .idle, updatedAt: Date(timeIntervalSince1970: 1))]
        model.workspace.reconcile(sessions: model.workspace.sessions + extra, projects: model.workspace.projects)
        model.workspace.placements["demo-native"] = model.workspace.placements["demo-state"]
        model.workspace.placements["free"] = Placement(Point(0, 700))
        model.workspace.placements["search-hidden"] = Placement(Point(0, 700))
        model.workspace.placements["expired"] = Placement(Point(-700, 900))
        let projectDelta = Point(3000, 4000)
        model.workspace.regions["canvas"] = model.workspace.regions["canvas"]!.translated(projectDelta)
        for session in model.workspace.sessions where session.projectID == "canvas" {
            model.workspace.placements[session.id] = Placement(model.workspace.placements[session.id]!.position + projectDelta)
        }
        model.workspace.viewport = Viewport(origin: Point(13, -93), zoom: 0.42)
        model.updateActivityTime(now: now)
        model.setStateVisible(.finished, false)
        model.setProjectVisible("research", false)
        model.setIdleTimeout(.oneHour)
        model.search = "Visible"
        model.openSession("demo-native")
        await model.loadHistory(older: false)
        let visible = Set(model.visibleSessions.map(\.id))
        #expect(visible == ["demo-native", "demo-access", "free"])
        let original = model.workspace, visibility = model.visibility, history = model.history
        model.isRefreshing = true
        model.rearrange()
        #expect(model.workspace == original)
        model.isRefreshing = false
        model.pendingSessions.insert("demo-native")
        model.rearrange()
        #expect(model.workspace == original)
        model.pendingSessions = []
        model.rearrange()
        #expect(model.errorMessage == nil)
        #expect(model.workspace.sessions == original.sessions)
        #expect(model.workspace.projects == original.projects)
        #expect(model.workspace.viewport == original.viewport)
        #expect(model.visibility == visibility)
        #expect(model.search == "Visible")
        #expect(model.acknowledgments.isEmpty)
        #expect(model.selectedSessionID == "demo-native")
        #expect(model.history == history)
        #expect(model.workspace.regions["research"] == original.regions["research"])
        let carriedDelta = Point(model.workspace.regions["canvas"]!.x - original.regions["canvas"]!.x,
                                 model.workspace.regions["canvas"]!.y - original.regions["canvas"]!.y)
        #expect(carriedDelta != Point(0, 0))
        for (id, placement) in original.placements where !visible.contains(id) {
            let isCarried = original.sessions.first { $0.id == id }?.projectID == "canvas"
            #expect(model.workspace.placements[id]?.position == placement.position + (isCarried ? carriedDelta : Point(0, 0)))
        }
        for id in visible {
            let placement = try #require(model.workspace.placements[id])
            #expect(model.workspace.placements.allSatisfy { $0.key == id || !placement.rect.intersects($0.value.rect) })
        }
        let arranged = model.workspace
        model.rearrange()
        #expect(model.workspace == arranged)
        model.shutdown()
        let restored = ApplicationModel(demo: true, storagePath: path)
        defer { restored.shutdown() }
        await restored.connect()
        #expect(restored.workspace.placements == arranged.placements)
        #expect(restored.workspace.regions == arranged.regions)
        #expect(restored.workspace.viewport == arranged.viewport)
        #expect(Dictionary(uniqueKeysWithValues: restored.workspace.sessions.map { ($0.id, $0) }) == Dictionary(uniqueKeysWithValues: arranged.sessions.map { ($0.id, $0) }))
        #expect(restored.visibility == visibility)
    }

    @Test func layoutSaveFailureKeepsTheOriginalWorkspaceAndEmptyProjectionIsDisabled() async throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let model = ApplicationModel(demo: true, storagePath: path)
        defer { model.shutdown() }
        await model.connect()
        let delta = Point(70000, 90000)
        model.workspace.regions["canvas"] = model.workspace.regions["canvas"]!.translated(delta)
        for session in model.workspace.sessions where session.projectID == "canvas" {
            model.workspace.placements[session.id] = Placement(model.workspace.placements[session.id]!.position + delta)
        }
        model.persist()
        let original = model.workspace
        var handle: OpaquePointer?
        #expect(sqlite3_open(path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        #expect(sqlite3_exec(handle, "CREATE TRIGGER reject_layout BEFORE UPDATE ON workspace BEGIN SELECT RAISE(ABORT,'fixture'); END", nil, nil, nil) == SQLITE_OK)
        model.rearrange()
        #expect(model.workspace == original)
        #expect(model.errorMessage != nil)
        #expect(try CanvasDatabase(path: path).load(source: model.sourceID) == original)
        #expect(sqlite3_exec(handle, "DROP TRIGGER reject_layout", nil, nil, nil) == SQLITE_OK)
        model.errorMessage = nil
        model.rearrange()
        #expect(model.errorMessage == nil)
        #expect(model.workspace != original)
        model.search = "absent"
        #expect(!model.canRearrange)
        let hidden = model.workspace
        model.rearrange()
        #expect(model.workspace == hidden)
    }

    private func temporaryPath() -> String { FileManager.default.temporaryDirectory.appendingPathComponent("canvas-rearrange-" + UUID().uuidString + ".sqlite").path }
}
