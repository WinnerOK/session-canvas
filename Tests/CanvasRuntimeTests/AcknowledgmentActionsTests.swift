import Foundation
import Testing
import CSQLite
import CanvasCore
@testable import SessionCanvas

@Suite(.serialized) @MainActor
struct AcknowledgmentActionsTests {
    @Test func acknowledgeAllIncludesHiddenFinishedAndPreservesNewResultsAcrossRestart() async throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let database = try CanvasDatabase(path: path)
        try database.acknowledge(source: "other-source", session: "other", result: "seen")
        let model = ApplicationModel(demo: true, storagePath: path)
        defer { model.shutdown() }
        await model.connect()
        var extra = [Session(id: "unknown", title: "Unknown", latestResult: SessionResult(id: "unknown/r", outcome: .completed, text: "Old")),
                     Session(id: "archived", title: "Archived", execution: .idle, latestResult: SessionResult(id: "archived/r", outcome: .completed, text: "Old"), isArchived: true)]
        extra.append(Session(id: "no-result", title: "Idle", execution: .idle))
        model.workspace.reconcile(sessions: model.workspace.sessions + extra, projects: model.workspace.projects)
        for index in model.workspace.sessions.indices where model.workspace.sessions[index].execution == .running {
            model.workspace.sessions[index].latestResult = SessionResult(id: "active-old/" + model.workspace.sessions[index].id, outcome: .completed, text: "Earlier result")
        }
        let original = model.workspace
        let finished = original.sessions.filter { model.state($0) == .finished }
        #expect(finished.count == 3)
        #expect(model.history.isEmpty)
        model.setStateVisible(.finished, false)
        model.setProjectVisible("research", false)
        model.search = "no matching session"
        #expect(model.visibleSessions.isEmpty)
        #expect(model.acknowledgeAllCount == 3)
        model.isRefreshing = true
        model.acknowledgeAll()
        #expect(model.acknowledgments.isEmpty)
        model.isRefreshing = false
        model.acknowledgeAll()
        for session in original.sessions {
            if let result = session.latestResult {
                #expect((model.acknowledgments[session.id] ?? []).contains(result.id) == finished.contains(where: { $0.id == session.id }))
            }
        }
        #expect(model.workspace == original)
        #expect(model.acknowledgeAllCount == 0)
        #expect(!model.canAcknowledgeAll)
        let stored = model.acknowledgments
        model.acknowledgeAll()
        #expect(model.acknowledgments == stored)
        let index = try #require(model.workspace.sessions.firstIndex { $0.id == "demo-state" })
        model.workspace.sessions[index].latestResult = SessionResult(id: "newer-result", outcome: .completed, text: "Arrived after the click")
        #expect(model.state(model.workspace.sessions[index]) == .finished)
        #expect(model.acknowledgments["demo-state"]?.contains("newer-result") != true)
        model.shutdown()
        let restored = ApplicationModel(demo: true, storagePath: path)
        defer { restored.shutdown() }
        await restored.connect()
        #expect(restored.acknowledgments == stored)
        #expect(restored.workspace.sessions.first { $0.id == "demo-state" }?.state(acknowledged: stored["demo-state"] ?? []) == .finished)
        #expect(try database.acknowledgments(source: "other-source") == ["other": ["seen"]])
    }

    @Test(arguments: [NoteState.idle, .running, .waiting, .permission, .unknown, .archived, .finished])
    func markUnreadTargetsTheDisplayedResultInAnyState(state: NoteState) async throws {
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        defer { model.shutdown() }
        await model.connect()
        model.setStateVisible(.archived, true)
        model.openSession("demo-state")
        await model.loadHistory(older: false)
        let result = try #require(model.history.compactMap(\.result).last)
        model.acknowledge(result, sessionID: "demo-state")
        let index = try #require(model.workspace.sessions.firstIndex { $0.id == "demo-state" })
        switch state {
        case .running: model.workspace.sessions[index].execution = .running
        case .waiting: model.workspace.sessions[index].requests = ["input": .input]
        case .permission: model.workspace.sessions[index].requests = ["permission": .permission]
        case .unknown: model.workspace.sessions[index].execution = .unknown
        case .archived: model.workspace.sessions[index].archived = true
        case .finished: model.workspace.sessions[index].latestResult = SessionResult(id: "new", outcome: .completed, text: "Newer result")
        case .idle: break
        }
        let original = model.workspace
        #expect(model.state(model.workspace.sessions[index]) == state)
        model.isLoadingHistory = true
        #expect(!model.canMarkUnread(result, sessionID: "demo-state"))
        model.markUnread(result, sessionID: "demo-state")
        #expect(model.acknowledgments["demo-state"]?.contains(result.id) == true)
        model.isLoadingHistory = false
        #expect(model.canMarkUnread(result, sessionID: "demo-state"))
        model.markUnread(result, sessionID: "demo-state")
        #expect(model.acknowledgments["demo-state"]?.contains(result.id) == false)
        #expect(model.workspace == original)
        #expect(model.state(model.workspace.sessions[index]) == (state == .idle ? .finished : state))
        #expect(!model.canMarkUnread(result, sessionID: "demo-state"))
        model.markUnread(result, sessionID: "demo-state")
        #expect(model.acknowledgments["demo-state"]?.contains(result.id) == false)
    }

    @Test func bulkFailureRollsBackAndUnreadFailurePreservesAcknowledgment() async throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let model = ApplicationModel(demo: true, storagePath: path)
        defer { model.shutdown() }
        await model.connect()
        let last = try #require(model.workspace.sessions.last { model.state($0) == .finished })
        try executeSQL("CREATE TRIGGER reject_bulk BEFORE INSERT ON acknowledgments WHEN NEW.session='\(last.id)' BEGIN SELECT RAISE(ABORT,'fixture'); END", path: path)
        model.acknowledgeAll()
        #expect(model.acknowledgments.isEmpty)
        #expect(try CanvasDatabase(path: path).acknowledgments(source: model.sourceID).isEmpty)
        #expect(model.errorMessage != nil)
        try executeSQL("DROP TRIGGER reject_bulk", path: path)
        model.errorMessage = nil
        model.acknowledgeAll()
        #expect(model.acknowledgments.count == 3)
        model.openSession("demo-state")
        await model.loadHistory(older: false)
        let result = try #require(model.history.compactMap(\.result).last)
        try executeSQL("CREATE TRIGGER reject_unread BEFORE DELETE ON acknowledgments BEGIN SELECT RAISE(ABORT,'fixture'); END", path: path)
        model.markUnread(result, sessionID: "demo-state")
        #expect(model.acknowledgments["demo-state"]?.contains(result.id) == true)
        #expect(try CanvasDatabase(path: path).acknowledgments(source: model.sourceID)["demo-state"]?.contains(result.id) == true)
        #expect(model.errorMessage != nil)
        try executeSQL("DROP TRIGGER reject_unread", path: path)
        model.markUnread(result, sessionID: "demo-state")
        #expect(model.acknowledgments["demo-state"]?.contains(result.id) == false)
        model.shutdown()
        let restored = ApplicationModel(demo: true, storagePath: path)
        defer { restored.shutdown() }
        await restored.connect()
        #expect(restored.acknowledgments["demo-state"]?.contains(result.id) != true)
        #expect(restored.workspace.sessions.first { $0.id == "demo-state" }?.state(acknowledged: []) == .finished)
    }

    @Test func knownAcknowledgmentCanBeReversedWithoutAvailableHistory() async throws {
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        defer { model.shutdown() }
        await model.connect()
        model.acknowledgeAll()
        model.selectedSessionID = "demo-state"
        model.history = []
        model.historyError = "History unavailable"
        let result = try #require(model.selectedSession?.latestResult)
        #expect(model.canMarkUnread(result, sessionID: "demo-state"))
        let unrelated = SessionResult(id: "other", outcome: .completed, text: "Other result")
        model.acknowledgments["demo-state", default: []].insert(unrelated.id)
        #expect(!model.canMarkUnread(unrelated, sessionID: "demo-state"))
        model.markUnread(result, sessionID: "demo-state")
        #expect(model.acknowledgments["demo-state"] == [unrelated.id])
        #expect(model.state(try #require(model.selectedSession)) == .finished)
    }

    private func temporaryPath() -> String { FileManager.default.temporaryDirectory.appendingPathComponent("canvas-ack-" + UUID().uuidString + ".sqlite").path }
    private func executeSQL(_ sql: String, path: String) throws {
        var handle: OpaquePointer?
        #expect(sqlite3_open(path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        #expect(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
    }
}
