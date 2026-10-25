import AppKit
import Foundation
import Testing
import CanvasCore
@testable import SessionCanvas

@Suite(.serialized) @MainActor
struct ImportRegressionTests {
    @Test(arguments: [false, true])
    func cachedResultsResolveInBackgroundWithoutOpeningSessions(legacy: Bool) async throws {
        let fixture = try SourceFixture()
        defer { fixture.remove() }
        try Data().write(to: fixture.folder.appendingPathComponent("missing-all-rollouts"))
        if legacy { try Data().write(to: fixture.folder.appendingPathComponent("legacy-history")) }
        let path = fixture.folder.appendingPathComponent("canvas.sqlite").path
        let database = try CanvasDatabase(path: path)
        var cached = Workspace()
        cached.reconcile(sessions: ["normal", "named-review", "unassigned", "archived", "guardian"].map {
            Session(id: $0, title: $0, latestResult: SessionResult(id: $0 + "/last/completed", outcome: .completed, text: "Saved result"), updatedAt: Date(timeIntervalSince1970: 1), revision: "1.0", isArchived: $0 == "archived")
        }, projects: [])
        let sourceID = "codex-local:" + fixture.folder.path
        try database.save(cached, source: sourceID)
        let model = ApplicationModel(demo: false, storagePath: path)
        model.settings = fixture.settings
        defer { model.shutdown() }
        await model.connect()
        let placements = model.workspace.placements
        #expect(model.workspace.sessions.first { $0.id == "normal" }?.execution == .unknown)
        try await Task.sleep(for: .milliseconds(500))
        for _ in 0..<100 {
            if !model.isRefreshing { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let inventoryCount = try String(contentsOf: fixture.folder.appendingPathComponent("inventories"), encoding: .utf8)
        for _ in 0..<100 {
            let reads = (try? String(contentsOf: fixture.folder.appendingPathComponent("read-log"), encoding: .utf8)) ?? ""
            if reads.contains("unassigned") && ["normal", "named-review"].allSatisfy({ id in model.workspace.sessions.first { $0.id == id }?.state(acknowledged: []) == .finished }) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(model.workspace.sessions.first { $0.id == "normal" }?.state(acknowledged: []) == .finished)
        #expect(model.workspace.sessions.first { $0.id == "named-review" }?.state(acknowledged: []) == .finished)
        #expect(model.stateCounts[.finished] == 2)
        #expect(model.workspace.sessions.first { $0.id == "unassigned" }?.execution == .unknown)
        #expect(model.workspace.sessions.first { $0.id == "archived" }?.isArchived == true)
        #expect(model.selectedSessionID == nil)
        #expect(model.history.isEmpty)
        #expect(model.acknowledgments.isEmpty)
        for (id, placement) in placements { #expect(model.workspace.placements[id] == placement) }
        #expect(model.workspace.layerState?.assignments["normal"] == .active)
        #expect(model.workspace.layerState?.assignments["unassigned"] == .inactive)
        #expect(try database.acknowledgments(source: sourceID).isEmpty)
        let log = fixture.folder.appendingPathComponent("read-log")
        let reads = (try? String(contentsOf: log, encoding: .utf8).split(separator: "\n")) ?? []
        #expect(!reads.contains { $0.contains("guardian") || $0.contains("archived") })
        let records = try reads.map { try JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
        let checks = records.filter { $0["method"].string == (legacy ? "thread/read" : "thread/turns/list") }
        #expect(checks.compactMap { $0["id"].string } == ["named-review", "normal", "unassigned"])
        if !legacy { #expect(checks.allSatisfy { $0["limit"].number == 1 }) }
        let times = checks.compactMap { $0["time"].number }
        for (a, b) in zip(times, times.dropFirst()) { #expect(b - a >= 0.95) }
        #expect(try String(contentsOf: fixture.folder.appendingPathComponent("inventories"), encoding: .utf8) == inventoryCount)
        await model.refresh()
        try await Task.sleep(for: .milliseconds(1100))
        #expect(try String(contentsOf: log, encoding: .utf8).split(separator: "\n").count == records.count)
    }

    @Test func backgroundFailuresAreCachedUntilTheSourceRevisionChanges() async throws {
        let fixture = try SourceFixture()
        defer { fixture.remove() }
        try Data().write(to: fixture.folder.appendingPathComponent("missing-rollout"))
        try Data().write(to: fixture.folder.appendingPathComponent("reject-history"))
        let source = CodexSource(mode: .history, settings: fixture.settings, observeDesktop: false)
        defer { source.close() }
        source.restoreCachedResults([Session(id: "normal", title: "Cached", latestResult: SessionResult(id: "r", outcome: .completed, text: "Saved"))])
        var updates = 0
        source.onSessionObservation = { _, _ in updates += 1 }
        try await source.connect()
        _ = try await source.snapshot()
        let log = fixture.folder.appendingPathComponent("read-log")
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: log.path) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(try String(contentsOf: log, encoding: .utf8).split(separator: "\n").count == 1)
        #expect(try await source.snapshot().sessions.first { $0.id == "normal" }?.execution == .unknown)
        _ = try await source.snapshot()
        try await Task.sleep(for: .milliseconds(1100))
        #expect(try String(contentsOf: log, encoding: .utf8).split(separator: "\n").count == 1)
        #expect(updates == 0)
        try Data().write(to: fixture.folder.appendingPathComponent("active"))
        _ = try await source.snapshot()
        for _ in 0..<100 {
            if (try String(contentsOf: log, encoding: .utf8).split(separator: "\n").count) == 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(try String(contentsOf: log, encoding: .utf8).split(separator: "\n").count == 2)
    }

    @Test func backgroundRecoveryHonorsTheExplicitSessionScope() async throws {
        let fixture = try SourceFixture()
        defer { fixture.remove() }
        try Data().write(to: fixture.folder.appendingPathComponent("missing-all-rollouts"))
        let source = CodexSource(mode: .history, settings: fixture.settings, observeDesktop: false, observedSessionIDs: ["unassigned"])
        defer { source.close() }
        source.restoreCachedResults(["normal", "unassigned"].map { Session(id: $0, title: $0, latestResult: SessionResult(id: "r", outcome: .completed, text: "Saved")) })
        try await source.connect()
        _ = try await source.snapshot()
        let log = fixture.folder.appendingPathComponent("read-log")
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: log.path) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(1100))
        let records = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map { try JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
        #expect(records.compactMap { $0["id"].string } == ["unassigned"])
    }

    @Test(arguments: [false, true]) func closingSourceStopsQueuedAndInFlightRecovery(inFlight: Bool) async throws {
        let fixture = try SourceFixture()
        defer { fixture.remove() }
        try Data().write(to: fixture.folder.appendingPathComponent("missing-rollout"))
        try Data().write(to: fixture.folder.appendingPathComponent("block-history"))
        let source = CodexSource(mode: .history, settings: fixture.settings, observeDesktop: false)
        defer { source.close() }
        source.restoreCachedResults([Session(id: "normal", title: "Cached", latestResult: SessionResult(id: "r", outcome: .completed, text: "Saved"))])
        var updates = 0
        source.onSessionObservation = { _, _ in updates += 1 }
        try await source.connect()
        _ = try await source.snapshot()
        if inFlight {
            for _ in 0..<100 {
                if FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent("history-ready").path) { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent("history-ready").path))
        }
        source.close()
        try await Task.sleep(for: .milliseconds(1100))
        #expect(updates == 0)
        if !inFlight { #expect(!FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent("read-log").path)) }
    }

    @Test(arguments: [false, true])
    func latestHistoryRestoresFinishedWithoutLocalRollout(legacy: Bool) async throws {
        let fixture = try SourceFixture()
        defer { fixture.remove() }
        try Data().write(to: fixture.folder.appendingPathComponent("missing-rollout"))
        if legacy { try Data().write(to: fixture.folder.appendingPathComponent("legacy-history")) }
        let model = ApplicationModel(demo: false, storagePath: ":memory:")
        model.settings = fixture.settings
        defer { model.shutdown() }
        await model.connect()
        let before = try #require(model.workspace.sessions.first { $0.id == "normal" })
        #expect(model.state(before) == .unknown)
        model.selectLayer(.inactive)
        let placement = model.workspace.placements[before.id]
        model.openSession(before.id)
        for _ in 0..<100 {
            if model.workspace.sessions.first(where: { $0.id == before.id })?.state(acknowledged: []) == .finished { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let observed = try #require(model.workspace.sessions.first { $0.id == before.id })
        let result = try #require(observed.latestResult)
        #expect(model.state(observed) == .finished)
        #expect(observed.stateIsFromHistory)
        #expect(observed.unknownReason == nil)
        #expect(observed.updatedAt == before.updatedAt)
        #expect(model.selectedLayer == .inactive && model.selectedSessionID == nil)
        model.selectLayer(.active); model.openSession(before.id); await model.loadHistory(older: false)
        #expect(model.canAcknowledge(result, sessionID: before.id))
        await model.refresh()
        #expect(model.workspace.sessions.first { $0.id == before.id }?.state(acknowledged: []) == .finished)
        #expect(model.workspace.layerState?.layouts[.inactive]?.placements[before.id] == placement)
        #expect(model.workspace.project(at: try #require(model.workspace.placements[before.id]).center) == observed.projectID)
        model.acknowledge(result, sessionID: before.id)
        #expect(model.workspace.sessions.first { $0.id == before.id }?.state(acknowledged: [result.id]) == .idle)
        model.setIdleTimeout(.oneWeek)
        #expect(!model.visibleSessions.contains { $0.id == before.id })
        try Data().write(to: fixture.folder.appendingPathComponent("active"))
        // A debounced source refresh may already be reading the previous inventory.
        for _ in 0..<100 {
            if !model.isRefreshing { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        await model.refresh()
        #expect(model.workspace.sessions.first { $0.id == before.id }?.execution == .unknown)
    }

    @Test(arguments: [false, true])
    func historyOnlyPromotesTheLatestTerminalTurn(legacy: Bool) async throws {
        let fixture = try SourceFixture()
        defer { fixture.remove() }
        try Data().write(to: fixture.folder.appendingPathComponent("missing-rollout"))
        if legacy { try Data().write(to: fixture.folder.appendingPathComponent("legacy-history")) }
        let source = CodexSource(mode: .history, settings: fixture.settings, observeDesktop: false)
        defer { source.close() }
        try await source.connect()
        _ = try await source.snapshot()
        let path = fixture.folder.appendingPathComponent("history-turns.json")
        for status in ["inProgress", "unsupported"] {
            try "[{\"id\":\"new\",\"status\":\"\(status)\",\"items\":[]},{\"id\":\"old\",\"status\":\"completed\",\"items\":[]}]".write(to: path, atomically: true, encoding: .utf8)
            let page = try await source.history(sessionID: "normal", cursor: nil)
            #expect(page.entries.compactMap(\.result).last?.id == "normal/old/completed")
            #expect(page.sessionObservation?.execution == .unknown)
            #expect(try await source.snapshot().sessions.first { $0.id == "normal" }?.execution == .unknown)
        }
        for status in ["completed", "failed", "interrupted"] {
            try "[{\"id\":\"new\",\"status\":\"\(status)\",\"items\":[]}]".write(to: path, atomically: true, encoding: .utf8)
            let page = try await source.history(sessionID: "normal", cursor: nil)
            #expect(page.sessionObservation?.state(acknowledged: []) == .finished)
            #expect(try await source.snapshot().sessions.first { $0.id == "normal" }?.state(acknowledged: []) == .finished)
        }
        try "[]".write(to: path, atomically: true, encoding: .utf8)
        #expect(try await source.history(sessionID: "normal", cursor: nil).sessionObservation?.execution == .unknown)
        try "[{\"id\":\"old\",\"status\":\"completed\",\"items\":[]}]".write(to: path, atomically: true, encoding: .utf8)
        #expect(try await source.history(sessionID: "normal", cursor: "0").sessionObservation == nil)
        #expect(try await source.snapshot().sessions.first { $0.id == "normal" }?.execution == .unknown)
    }

    @Test func historyCannotRegressNewerMetadataOrRolloutWork() async throws {
        let fixture = try SourceFixture()
        defer { fixture.remove() }
        let source = CodexSource(mode: .history, settings: fixture.settings, observeDesktop: false)
        defer { source.close() }
        try await source.connect()
        _ = try await source.snapshot()
        try Data().write(to: fixture.folder.appendingPathComponent("change-file-on-history"))
        let stalePage = try await source.history(sessionID: "normal", cursor: nil)
        #expect(stalePage.sessionObservation?.execution == .unknown)
        try Data().write(to: fixture.folder.appendingPathComponent("active"))
        _ = try await source.snapshot()
        try Data().write(to: fixture.folder.appendingPathComponent("legacy-history"))
        let olderMetadata = try await source.history(sessionID: "normal", cursor: nil)
        #expect(olderMetadata.sessionObservation?.execution == .unknown)
        #expect(olderMetadata.sessionObservation?.revision == "2.0")
    }

    @Test func delayedHistoryCannotReplaceNewWorkInTheViewer() async throws {
        let fixture = try SourceFixture()
        defer { fixture.remove() }
        try Data().write(to: fixture.folder.appendingPathComponent("missing-rollout"))
        let model = ApplicationModel(demo: false, storagePath: ":memory:")
        model.settings = fixture.settings
        defer { model.shutdown() }
        await model.connect()
        model.selectLayer(.inactive)
        try Data().write(to: fixture.folder.appendingPathComponent("block-history"))
        model.openSession("normal")
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent("history-ready").path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent("history-ready").path))
        let index = try #require(model.workspace.sessions.firstIndex { $0.id == "normal" })
        model.workspace.sessions[index].execution = .running
        model.workspace.sessions[index].requests = ["new-approval": .permission]
        model.workspace.sessions[index].latestResult = SessionResult(id: "new-result", outcome: .completed, text: "Newer result")
        model.updateActivityTime()
        try Data().write(to: fixture.folder.appendingPathComponent("release-history"))
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.history.isEmpty && model.selectedSessionID == nil && model.selectedLayer == .inactive)
        let current = try #require(model.workspace.sessions.first { $0.id == "normal" })
        #expect(model.state(current) == .permission)
        #expect(current.latestResult?.id == "new-result")
        let displayed = SessionResult(id: "normal/last/completed", outcome: .completed, text: "Old")
        #expect(!model.canAcknowledge(displayed, sessionID: "normal"))
    }

    @Test func unloadedSessionsRecoverTerminalStateBeforeOpeningViewer() async throws {
        let fixture = try SourceFixture()
        defer { fixture.remove() }
        let source = CodexSource(mode: .history, settings: fixture.settings)
        defer { source.close() }
        try await source.connect()
        let snapshot = try await source.snapshot()
        let session = try #require(snapshot.sessions.first { $0.id == "normal" })
        #expect(session.state(acknowledged: []) == .finished)
        #expect(session.latestResult?.id == "normal/last/completed")
        #expect(session.state(acknowledged: ["normal/last/completed"]) == .idle)
        #expect(snapshot.sessions.first { $0.id == "unassigned" }?.execution == .unknown)
        _ = try await source.snapshot()
        #expect(!FileManager.default.fileExists(atPath: fixture.folder.appendingPathComponent("reads").path))
        try Data().write(to: fixture.folder.appendingPathComponent("file-only"))
        let changedFile = try await source.snapshot()
        #expect(changedFile.sessions.first { $0.id == "normal" }?.execution == .unknown)
        #expect(changedFile.sessions.first { $0.id == "normal" }?.revision == session.revision)
        try Data().write(to: fixture.folder.appendingPathComponent("active"))
        let next = try await source.snapshot()
        #expect(next.sessions.first { $0.id == "normal" }?.execution == .unknown)
    }
    @Test func inventoryHidesInternalAgentsAndImportsExactProjectMembership() async throws {
        let fixture = try SourceFixture()
        defer { fixture.remove() }
        let source = CodexSource(mode: .history, settings: fixture.settings)
        defer { source.close() }
        try await source.connect()
        let snapshot = try await source.snapshot()
        #expect(Set(snapshot.sessions.map(\.id)) == ["normal", "named-review", "unassigned", "archived"])
        #expect(snapshot.projects == [Project(id: "p", name: "Existing project"), Project(id: "empty", name: "Empty project")])
        #expect(snapshot.sessions.first { $0.id == "normal" }?.projectID == "p")
        // Same directory and even a Guardian title do not imply membership or an internal agent.
        #expect(snapshot.sessions.first { $0.id == "named-review" }?.projectID == nil)
        #expect(snapshot.sessions.first { $0.id == "unassigned" }?.projectID == nil)
        #expect(!source.canAssignProject)
    }

    @Test func refreshRemovesPreviouslyCachedGuardianNotes() async throws {
        let fixture = try SourceFixture()
        defer { fixture.remove() }
        let path = fixture.folder.appendingPathComponent("canvas.sqlite").path
        let database = try CanvasDatabase(path: path)
        var cached = Workspace()
        cached.reconcile(sessions: [Session(id: "guardian", title: "Guardian review")], projects: [])
        try database.save(cached, source: "codex-local:" + fixture.folder.path)
        let model = ApplicationModel(demo: false, storagePath: path)
        model.settings = fixture.settings
        await model.connect()
        #expect(model.connected)
        #expect(!model.workspace.sessions.contains { $0.id == "guardian" })
        #expect(model.workspace.placements["guardian"] == nil)
        #expect(model.workspace.projects.count == 2)
        let retained = model.workspace
        try Data("{".utf8).write(to: fixture.folder.appendingPathComponent(".codex-global-state.json"))
        await model.refresh()
        var stale = retained
        for i in stale.sessions.indices { stale.sessions[i].execution = .unknown }
        #expect(model.workspace.sessions == stale.sessions && model.workspace.projects == stale.projects)
        #expect(model.workspace.layerState?.assignments.values.allSatisfy { $0 == .inactive } == true)
        #expect(model.errorMessage != nil)
        model.shutdown()
        #expect(!(try database.load(source: model.sourceID)).sessions.contains { $0.id == "guardian" })
    }

    @Test func refreshReflectsSavedProjectRenamesAndExplicitUnassignment() async throws {
        let fixture = try SourceFixture()
        defer { fixture.remove() }
        let source = CodexSource(mode: .history, settings: fixture.settings)
        defer { source.close() }
        try await source.connect()
        _ = try await source.snapshot()
        try #"{"local-projects":{"p":{"id":"p","name":"Renamed"}},"thread-project-assignments":{},"projectless-thread-ids":["normal"]}"#
            .write(to: fixture.folder.appendingPathComponent(".codex-global-state.json"), atomically: true, encoding: .utf8)
        let snapshot = try await source.snapshot()
        #expect(snapshot.projects == [Project(id: "p", name: "Renamed")])
        #expect(snapshot.sessions.first { $0.id == "normal" }?.projectID == nil)
    }

    @Test func sourceArchiveRoundTripAndFailureKeepTheSameSession() async throws {
        let fixture = try SourceFixture()
        defer { fixture.remove() }
        let source = CodexSource(mode: .history, settings: fixture.settings)
        defer { source.close() }
        try await source.connect()
        let before = try #require(try await source.snapshot().sessions.first { $0.id == "normal" })
        try await source.setArchived(sessionID: "normal", archived: true)
        let archived = try #require(try await source.snapshot().sessions.first { $0.id == "normal" })
        #expect(archived.isArchived)
        #expect(archived.updatedAt == before.updatedAt)
        #expect(archived.projectID == before.projectID)
        try Data().write(to: fixture.folder.appendingPathComponent("legacy-history"))
        _ = try await source.history(sessionID: "normal", cursor: nil)
        try Data().write(to: fixture.folder.appendingPathComponent("omit-archived"))
        #expect(try await source.snapshot().sessions.first { $0.id == "normal" }?.state(acknowledged: []) == .archived)
        try await source.setArchived(sessionID: "normal", archived: false)
        #expect(try await source.snapshot().sessions.first { $0.id == "normal" }?.isArchived == false)
        try Data().write(to: fixture.folder.appendingPathComponent("reject-archive"))
        await #expect(throws: (any Error).self) { try await source.setArchived(sessionID: "normal", archived: true) }
        #expect(try await source.snapshot().sessions.first { $0.id == "normal" }?.isArchived == false)
    }

    @Test func cachedArchiveSurvivesHistoryMetadataForAnOmittedSession() async throws {
        let fixture = try SourceFixture()
        defer { fixture.remove() }
        let path = fixture.folder.appendingPathComponent("canvas.sqlite").path
        let database = try CanvasDatabase(path: path)
        var cached = Workspace()
        cached.reconcile(sessions: [Session(id: "cached", title: "Cached archive", isArchived: true)], projects: [])
        try database.save(cached, source: "codex-local:" + fixture.folder.path)
        let model = ApplicationModel(demo: false, storagePath: path)
        model.settings = fixture.settings
        defer { model.shutdown() }
        await model.connect()
        model.selectLayer(.inactive)
        model.setStateVisible(.archived, true)
        try Data().write(to: fixture.folder.appendingPathComponent("legacy-history"))
        model.openSession("cached")
        await model.loadHistory(older: false)
        await model.refresh()
        let restored = try #require(model.workspace.sessions.first { $0.id == "cached" })
        #expect(restored.isArchived)
        #expect(model.state(restored) == .archived)
        #expect(model.workspace.placements[restored.id] == cached.placements[restored.id])
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SESSION_CANVAS_TEST_REAL_SOURCE"] == "1"))
    func installedCodexInventoryAndDesktopProjects() async throws {
        let source = CodexSource(mode: .history, settings: .defaults, observeDesktop: false)
        defer { source.close() }
        try await source.connect()
        let snapshot = try await source.snapshot()
        #expect(!snapshot.sessions.isEmpty)
        #expect(!snapshot.projects.isEmpty)
        #expect(!source.hiddenSessionIDs.isEmpty)
        #expect(Set(snapshot.sessions.map(\.id)).isDisjoint(with: source.hiddenSessionIDs))
        #expect(snapshot.sessions.contains { $0.projectID != nil })
        #expect(snapshot.sessions.contains { $0.stateIsFromHistory && $0.execution == .idle })
        print("Verified installed source: \(snapshot.sessions.count) sessions, \(source.hiddenSessionIDs.count) hidden internal sessions, \(snapshot.projects.count) projects, \(snapshot.sessions.filter { $0.projectID != nil }.count) assigned sessions.")
        print("Saved terminal/empty state: \(snapshot.sessions.filter { $0.stateIsFromHistory && $0.execution == .idle }.count); Unknown: \(snapshot.sessions.filter { $0.execution == .unknown }.count); archived: \(snapshot.sessions.filter(\.isArchived).count).")
        print("Unavailable local history: \(snapshot.sessions.filter { $0.unknownReason == .historyMissing }.count); incomplete evidence: \(snapshot.sessions.filter { $0.unknownReason == .incompleteHistory }.count).")
    }

    @Test(arguments: [-60.0, 130.0])
    func canvasRenderingStaysInsideItsFrameWhenPanned(noteY: Double) throws {
        _ = NSApplication.shared
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        model.workspace.viewport = Viewport(origin: Point(0, 0))
        let parent = CanvasTestBackground(frame: NSRect(x: 0, y: 0, width: 400, height: 320))
        let canvas = CanvasNSView(model: model)
        canvas.frame = NSRect(x: 0, y: 80, width: 400, height: 180)
        parent.addSubview(canvas)
        let baseline = try capture(parent)
        model.workspace.sessions = [Session(id: "s", title: "Overflowing note", execution: .idle)]
        model.workspace.placements["s"] = Placement(Point(40, noteY))
        canvas.update()
        let panned = try capture(parent)
        // Inspect the header above and footer below the actual canvas, including note shadows.
        var changedOutsideCanvas = 0
        var changedInsideCanvas = 0
        for y in 0..<panned.pixelsHigh {
            let viewY = Double(y) * parent.bounds.height / Double(panned.pixelsHigh)
            for x in 0..<panned.pixelsWide {
                if baseline.colorAt(x: x, y: y) != panned.colorAt(x: x, y: y) {
                    if viewY < 75 || viewY >= 265 { changedOutsideCanvas += 1 }
                    if viewY >= 85 && viewY < 255 { changedInsideCanvas += 1 }
                }
            }
        }
        #expect(changedOutsideCanvas == 0)
        #expect(changedInsideCanvas > 0)
    }

    private func capture(_ view: NSView) throws -> NSBitmapImageRep {
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }
}

@MainActor private final class CanvasTestBackground: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) { NSColor.systemRed.setFill(); bounds.fill() }
}

private struct SourceFixture {
    let folder: URL
    let settings: ConnectionSettings
    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("canvas-import-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let executable = folder.appendingPathComponent("codex-fixture")
        settings = ConnectionSettings(executable: executable.path, socket: "", nativeURLTemplate: "codex://threads/{id}")
        let script = #"""
        #!/usr/bin/python3
        import json, pathlib, sys, time
        home = pathlib.Path(__file__).parent
        archived_ids = {"archived"}
        reads = 0
        inventories = 0
        for line in sys.stdin:
            request = json.loads(line)
            if "id" not in request:
                continue
            method = request["method"]
            if method == "initialize":
                result = {"codexHome": str(home)}
            elif method == "thread/list":
                inventories += 1
                (home / "inventories").write_text(str(inventories))
                def session(ident, source, **extra):
                    path = home / "sessions" / (ident + ".jsonl")
                    path.parent.mkdir(exist_ok=True)
                    active = ident == "unassigned" or ident == "normal" and ((home / "active").exists() or (home / "file-only").exists())
                    records = [{"type":"session_meta", "payload":{"id":ident}}, {"type":"event_msg", "payload":{"type":"task_started" if active else "task_complete", "turn_id":"last"}}]
                    content = "".join(json.dumps(v) + "\n" for v in records)
                    if not path.exists() or path.read_text() != content: path.write_text(content)
                    listed_path = home / "sessions" / "unavailable.jsonl" if (home / "missing-all-rollouts").exists() or ident == "normal" and (home / "missing-rollout").exists() else path
                    return dict(id=ident, name="Guardian review" if ident != "normal" else "My work", source=source, cwd="/Projects/existing", path=str(listed_path), updatedAt=2 if ident == "normal" and (home / "active").exists() else 1, **extra)
                if request.get("params", {}).get("archived"):
                    result = {"data": [] if (home / "omit-archived").exists() else [session(ident, "cli") for ident in archived_ids], "nextCursor": None}
                elif request.get("params", {}).get("cursor"):
                    result = {"data": [session("child", "appServer", parentThreadId="normal"), session("unassigned", "cli")], "nextCursor": None}
                else:
                    result = {"data": [s for s in [session("normal", "cli"), session("guardian", {"subAgent": {"other": "guardian"}}), session("review", {"subAgent": "review"}), session("named-review", "appServer")] if s["id"] not in archived_ids], "nextCursor": "page2"}
            elif method == "thread/turns/list":
                with (home / "read-log").open("a") as log:
                    log.write(json.dumps({"id": request["params"]["threadId"], "limit": request["params"]["limit"], "time": time.monotonic(), "method": method}) + "\n")
                if (home / "reject-history").exists():
                    print(json.dumps({"id": request["id"], "error": {"code": -32000}}), flush=True)
                    continue
                if (home / "legacy-history").exists():
                    print(json.dumps({"id": request["id"], "error": {"code": -32601}}), flush=True)
                    continue
                reads += 1
                (home / "reads").write_text(str(reads))
                ident = request["params"]["threadId"]
                if (home / "block-history").exists():
                    (home / "history-ready").touch()
                    deadline = time.monotonic() + 2
                    while not (home / "release-history").exists() and time.monotonic() < deadline:
                        time.sleep(.01)
                if (home / "change-file-on-history").exists():
                    with (home / "sessions" / (ident + ".jsonl")).open("a") as f:
                        f.write(json.dumps({"type":"event_msg", "payload":{"type":"task_started", "turn_id":"newer"}}) + "\n")
                turns = json.loads((home / "history-turns.json").read_text()) if (home / "history-turns.json").exists() else [{"id":"last", "status":"inProgress" if ident == "unassigned" or ident == "normal" and (home / "active").exists() else "completed", "items":[]}]
                result = {"data": turns, "nextCursor": None}
            elif method == "thread/read":
                with (home / "read-log").open("a") as log:
                    log.write(json.dumps({"id": request["params"]["threadId"], "time": time.monotonic(), "method": method}) + "\n")
                ident = request["params"]["threadId"]
                turns = list(reversed(json.loads((home / "history-turns.json").read_text()))) if (home / "history-turns.json").exists() else [{"id":"last", "status":"inProgress" if ident == "unassigned" or ident == "normal" and (home / "active").exists() else "completed", "items":[]}]
                result = {"thread":{"id":request["params"]["threadId"], "name":"My work", "cwd":"/Projects/existing", "updatedAt":1, "status":{"type":"notLoaded"}, "turns":turns}}
            elif method in ["thread/archive", "thread/unarchive"]:
                if (home / "reject-archive").exists():
                    print(json.dumps({"id": request["id"], "error": {"code": -32600}}), flush=True)
                    continue
                ident = request["params"]["threadId"]
                if method == "thread/archive": archived_ids.add(ident)
                else: archived_ids.discard(ident)
                result = {}
            else:
                result = {}
            print(json.dumps({"id": request["id"], "result": result}), flush=True)
        """#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try #"""
        {"local-projects":{"p":{"id":"p","name":"Existing project","rootPaths":["/Projects/existing"]},"empty":{"id":"empty","name":"Empty project","rootPaths":["/Projects/empty"]}},"project-order":["p","empty"],"thread-project-assignments":{"normal":{"projectKind":"local","projectId":"p"},"unassigned":{"projectKind":"local","projectId":"p"}},"projectless-thread-ids":["unassigned"]}
        """#.write(to: folder.appendingPathComponent(".codex-global-state.json"), atomically: true, encoding: .utf8)
    }
    func remove() { try? FileManager.default.removeItem(at: folder) }
}
