import Foundation
import Testing
import CSQLite
import CanvasCore

@Suite struct SessionLayerTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    @Test func classificationIsExclusiveAndExhaustive() {
        let result = SessionResult(id: "r", outcome: .completed, text: "Done")
        let sessions = [Session(id: "running", title: "Run", execution: .running),
                        Session(id: "waiting", title: "Wait", execution: .running, requests: ["q": .input]),
                        Session(id: "permission", title: "Permit", execution: .running, requests: ["p": .permission]),
                        Session(id: "finished", title: "Result", execution: .idle, latestResult: result),
                        Session(id: "idle", title: "Idle", execution: .idle, updatedAt: now),
                        Session(id: "stale", title: "Old", execution: .idle, updatedAt: now.addingTimeInterval(-3600)),
                        Session(id: "archived", title: "Archive", execution: .running, latestResult: result, isArchived: true),
                        Session(id: "unknown", title: "Unknown", requests: ["p": .permission], latestResult: result)]
        let layers = sessions.map { CanvasLayer.classify($0, acknowledged: [], timeout: .oneHour, now: now) }
        #expect(layers == [.active, .active, .active, .active, .active, .stale, .inactive, .inactive])
    }
    @Test func allCutoffsAndProtections() {
        for timeout in IdleTimeout.allCases {
            var session = Session(id: "s", title: "Idle", execution: .idle, updatedAt: now.addingTimeInterval(-(timeout.seconds ?? 86400)))
            #expect(CanvasLayer.classify(session, acknowledged: [], timeout: timeout, now: now) == (timeout == .never ? .active : .stale))
            session.updatedAt = now.addingTimeInterval(-(timeout.seconds ?? 86400) + 1)
            #expect(CanvasLayer.classify(session, acknowledged: [], timeout: timeout, now: now) == .active)
            for date in [Date(timeIntervalSince1970: 0), now.addingTimeInterval(100)] {
                session.updatedAt = date
                #expect(CanvasLayer.classify(session, acknowledged: [], timeout: timeout, now: now) == .active)
            }
            session.updatedAt = now.addingTimeInterval(-3_000_000)
            session.latestResult = SessionResult(id: "r", outcome: .failed, text: "")
            #expect(CanvasLayer.classify(session, acknowledged: [], timeout: timeout, now: now) == .active)
            #expect(CanvasLayer.classify(session, acknowledged: ["r"], timeout: timeout, now: now) == (timeout == .never ? .active : .stale))
            for kind in [RequestKind.input, .permission] {
                session.requests = ["q": kind]
                #expect(CanvasLayer.classify(session, acknowledged: ["r"], timeout: timeout, now: now) == .active)
            }
        }
    }
    @Test func independentBoundsAndDormantPositions() throws {
        var value = fixture()
        value.reconcileLayers(acknowledgments: [:], now: now)
        #expect(value.geometrySessions.map(\.id) == ["a"])
        value.regions["p"] = Rect(-1000, 0, 760, 580)
        value.placements["a"] = Placement(Point(-980, 64))
        value.reconcileLayers(acknowledgments: [:], now: now, selecting: .inactive)
        #expect(value.placements["u"] != nil)
        #expect(value.regions["p"] == Rect(0, 0, 760, 580))
        value.regions["p"] = Rect(2000, 100, 400, 300)
        value.placements["u"] = Placement(Point(2020, 164))
        value.reconcileLayers(acknowledgments: [:], now: now, selecting: .active)
        #expect(value.regions["p"] == Rect(-1000, 0, 760, 580))
        #expect(value.placements["a"]?.position == Point(-980, 64))
        let archived = try #require(value.sessions.firstIndex { $0.id == "a" })
        value.sessions[archived].archived = true
        value.reconcileLayers(acknowledgments: [:], now: now)
        #expect(value.placements.isEmpty && value.regions.isEmpty)
        #expect(value.layerState?.layouts[.active]?.remembered["a"] != nil)
        value.sessions[archived].archived = false
        value.reconcileLayers(acknowledgments: [:], now: now)
        #expect(value.placements["a"]?.position == Point(-980, 64))
    }
    @Test func transitionRetainsProjectAndFindsVacancyAfterSlotReuse() throws {
        var value = fixture()
        value.reconcileLayers(acknowledgments: [:], now: now)
        value.sessions[0].archived = true
        value.reconcileLayers(acknowledgments: [:], now: now)
        value.sessions.append(Session(id: "new", title: "Replacement", projectID: "p", execution: .idle))
        value.reconcileLayers(acknowledgments: [:], now: now)
        let replacement = try #require(value.placements["new"])
        value.sessions[0].archived = false
        value.reconcileLayers(acknowledgments: [:], now: now)
        let returned = try #require(value.placements["a"])
        #expect(value.project(at: returned.center) == "p")
        #expect(!replacement.rect.intersects(returned.rect))
        #expect(value.placements["new"] == replacement)
        value.sessions[0].projectID = nil
        value.reconcileLayers(acknowledgments: [:], now: now)
        #expect(value.project(at: try #require(value.placements["a"]).center) == nil)
    }
    @Test func legacyMigrationAndVersionedRoundTrip() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let database = try CanvasDatabase(path: path)
        let legacy = fixture()
        try database.save(legacy, source: "one")
        var visibility = CanvasVisibility(); visibility.hiddenStates = [.archived, .unknown]; visibility.idleTimeout = .oneHour
        try database.saveVisibility(visibility, source: "one")
        try database.acknowledge(source: "one", session: "u", result: "r")
        var migrated = try database.loadLayered(source: "one", now: now)
        #expect(migrated.selectedLayer == .active)
        #expect(migrated.placements["a"] == legacy.placements["a"])
        #expect(migrated.layerState?.idleTimeout == .oneHour)
        #expect(migrated.layerState?.filters[.inactive]?.hiddenStates == [.archived, .unknown])
        migrated.reconcileLayers(acknowledgments: [:], now: now, selecting: .inactive)
        migrated.regions["p"] = Rect(-800, 0, 760, 580)
        migrated.placements["u"] = Placement(Point(-780, 64))
        migrated.rememberLayerLayout()
        try database.save(migrated, source: "one")
        #expect(try database.loadLayered(source: "one", now: now) == migrated)
        #expect(try database.acknowledgments(source: "one")["u"] == ["r"])
        #expect(try database.loadLayered(source: "two", now: now).selectedVisibility.hiddenStates.isEmpty)
        var state = try #require(migrated.layerState); state.version = 99; migrated.layerState = state
        let encoded = try JSONEncoder().encode(migrated)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Workspace.self, from: encoded) }
    }
    private func fixture() -> Workspace {
        var value = Workspace()
        value.sessions = [Session(id: "a", title: "Active", projectID: "p", execution: .idle, updatedAt: now),
                          Session(id: "u", title: "Unknown", projectID: "p")]
        value.projects = [Project(id: "p", name: "Project")]
        value.regions["p"] = Rect(0, 0, 760, 580)
        value.placements = ["a": Placement(Point(20, 64)), "u": Placement(Point(270, 64))]
        return value
    }
    @Test func externalMembershipInvalidatesRememberedProjectAcrossLayers() throws {
        var value = fixture()
        value.projects.append(Project(id: "q", name: "Destination"))
        value.reconcileLayers(acknowledgments: [:], now: now)
        value.sessions[0].archived = true; value.reconcileLayers(acknowledgments: [:], now: now)
        value.sessions[0].projectID = "q"; value.reconcileLayers(acknowledgments: [:], now: now, selecting: .inactive)
        #expect(value.project(at: try #require(value.placements["a"]).center) == "q")
        value.sessions[0].archived = false; value.reconcileLayers(acknowledgments: [:], now: now, selecting: .active)
        #expect(value.project(at: try #require(value.placements["a"]).center) == "q")
        #expect(value.layerState?.layouts[.active]?.remembered["a"]?.projectID == "q")
        let encoded = try JSONEncoder().encode(value)
        value = try JSONDecoder().decode(Workspace.self, from: encoded)
        value.reconcileLayers(acknowledgments: [:], now: now)
        #expect(value.project(at: try #require(value.placements["a"]).center) == "q")
    }

    @Test func migrationFailureIsAtomicAndRetainsOriginalBackup() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let database = try CanvasDatabase(path: path), original = fixture()
        try database.save(original, source: "source")
        var db: OpaquePointer?; #expect(sqlite3_open(path, &db) == SQLITE_OK); defer { sqlite3_close(db) }
        #expect(sqlite3_exec(db, "CREATE TRIGGER reject_migration BEFORE UPDATE ON workspace BEGIN SELECT RAISE(ABORT,'fixture'); END", nil, nil, nil) == SQLITE_OK)
        #expect(throws: (any Error).self) { try database.loadLayered(source: "source", now: now) }
        #expect(try database.load(source: "source") == original)
        var stmt: OpaquePointer?
        #expect(sqlite3_prepare_v2(db, "SELECT count(*) FROM layer_migration_backup", -1, &stmt, nil) == SQLITE_OK)
        #expect(sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_int(stmt, 0) == 0); sqlite3_finalize(stmt)
        #expect(sqlite3_exec(db, "DROP TRIGGER reject_migration", nil, nil, nil) == SQLITE_OK)
        _ = try database.loadLayered(source: "source", now: now)
        #expect(sqlite3_prepare_v2(db, "SELECT workspace FROM layer_migration_backup WHERE source='source'", -1, &stmt, nil) == SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        #expect(sqlite3_step(stmt) == SQLITE_ROW)
        let bytes = try #require(sqlite3_column_blob(stmt, 0))
        let backup = try JSONDecoder().decode(Workspace.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0))))
        #expect(backup == original)
    }
    @Test func crowdedArrivalTranslatesOnlyDestinationProjectAndRestoresRelativeMemory() throws {
        var value = fixture()
        value.sessions[1].execution = .idle
        value.sessions.append(Session(id: "b", title: "Neighbor", projectID: "q", execution: .idle))
        value.projects.append(Project(id: "q", name: "Neighbor"))
        value.regions = ["p": Rect(0, 0, 300, 240), "q": Rect(0, 250, 300, 240)]
        value.placements = ["a": Placement(Point(20, 64)), "b": Placement(Point(20, 314))]
        value.sessions[1].archived = true
        value.reconcileLayers(acknowledgments: [:], now: now)
        let neighbor = value.placements["b"], oldProject = value.regions["p"]
        value.sessions[1].archived = false
        value.reconcileLayers(acknowledgments: [:], now: now)
        #expect(value.regions["p"] != oldProject)
        #expect(value.placements["b"] == neighbor)
        for id in ["a", "u"] { #expect(value.project(at: try #require(value.placements[id]).center) == "p") }
        #expect(!value.regions["p"]!.intersects(value.regions["q"]!))
        #expect(!value.placements["a"]!.rect.intersects(value.placements["u"]!.rect))
        let offset = value.placements["a"]!.position - Point(value.regions["p"]!.x, value.regions["p"]!.y)
        value.sessions[0].archived = true; value.reconcileLayers(acknowledgments: [:], now: now)
        let delta = Point(100, 100)
        value.regions["p"] = value.regions["p"]!.translated(delta)
        value.placements["u"] = Placement(value.placements["u"]!.position + delta)
        value.sessions[0].archived = false; value.reconcileLayers(acknowledgments: [:], now: now)
        #expect(value.placements["a"]!.position == offset + Point(value.regions["p"]!.x, value.regions["p"]!.y))
    }
}
