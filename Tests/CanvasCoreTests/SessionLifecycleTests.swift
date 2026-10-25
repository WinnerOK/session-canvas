import Foundation
import Testing
import CanvasCore

@Suite struct SessionLifecycleTests {
    @Test func confirmedArchiveIsTheStateEvenWhenExecutionAndHistoryAreUnknown() {
        for execution in [Execution.unknown, .idle, .running] {
            var session = Session(id: "archived", title: "Archived work", execution: execution,
                                  latestResult: SessionResult(id: "unread", outcome: .stopped, text: "Stopped"), isArchived: true)
            session.unknownReason = .historyMissing
            session.requests = ["old-request": .permission]
            #expect(session.state(acknowledged: []).label == "Archived")
            #expect(session.state(acknowledged: ["unread"]).symbol == "archivebox")
        }
    }
    @Test func activityUsesOnlyLargestUnitAndCapsAtOneMonth() {
        let now = Date(timeIntervalSince1970: 2000000000)
        for (seconds, expected) in [(0.0, "0m ago"), (59, "0m ago"), (60, "1m ago"), (900, "15m ago"),
                                    (3599, "59m ago"), (3600, "1h ago"), (4500, "1h ago"),
                                    (86399, "23h ago"), (86400, "1d ago"), (2591999, "29d ago"),
                                    (2592000, "1 month ago"), (31536000, "1 month ago"), (-60, "0m ago")] {
            #expect(ActivityTime.label(now.addingTimeInterval(-seconds), now: now) == expected)
        }
        #expect(ActivityTime.label(Date(timeIntervalSince1970: 0), now: now) == "Activity unavailable")
    }

    @Test func lifecycleHidingRequiresKnownIdleAndAcknowledgedResult() {
        let now = Date(timeIntervalSince1970: 10000000), old = now.addingTimeInterval(-86400)
        var visibility = CanvasVisibility(); visibility.idleTimeout = .oneHour; visibility.hideUnknown = false
        let result = SessionResult(id: "r", outcome: .completed, text: "Done")
        for execution in [Execution.running, .unknown, .idle] {
            var session = Session(id: "s", title: "Work", execution: execution, latestResult: result, updatedAt: old)
            #expect(visibility.includesLifecycle(session, acknowledged: [], now: now))
            #expect(visibility.includesLifecycle(session, acknowledged: ["r"], now: now) == (execution != .idle))
            session.requests = ["p": .permission]
            #expect(visibility.includesLifecycle(session, acknowledged: ["r"], now: now))
            session.requests = ["q": .input]
            #expect(visibility.includesLifecycle(session, acknowledged: ["r"], now: now))
        }
        var session = Session(id: "s", title: "Work", execution: .idle, updatedAt: now.addingTimeInterval(-3599))
        #expect(visibility.includesLifecycle(session, acknowledged: [], now: now))
        session.updatedAt = now.addingTimeInterval(-3600)
        #expect(!visibility.includesLifecycle(session, acknowledged: [], now: now))
        session.updatedAt = Date(timeIntervalSince1970: 0)
        #expect(visibility.includesLifecycle(session, acknowledged: [], now: now))
        session.updatedAt = old; session.unknownReason = .historyMissing
        #expect(visibility.includesLifecycle(session, acknowledged: [], now: now))
    }

    @Test func olderSavedPayloadsKeepLayoutAndDefaultVisibility() throws {
        let legacy = Data(#"{"hiddenStates":["unknown"],"hiddenProjectIDs":["p"]}"#.utf8)
        let visibility = try JSONDecoder().decode(CanvasVisibility.self, from: legacy)
        #expect(visibility.hiddenStates.contains(.archived))
        #expect(visibility.idleTimeout == .never)
        #expect(visibility.hideUnknown)
        #expect(visibility.hiddenStates == [.unknown, .archived])
        #expect(visibility.hiddenProjectIDs == ["p"])
        let session = Session(id: "s", title: "Old", execution: .idle)
        var payload = try JSONEncoder().encode(session)
        var object = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        object.removeValue(forKey: "archived"); object.removeValue(forKey: "savedState")
        payload = try JSONSerialization.data(withJSONObject: object)
        let restored = try JSONDecoder().decode(Session.self, from: payload)
        #expect(!restored.isArchived && !restored.stateIsFromHistory)
    }

    @Test func archiveVisibilityMigratesAndRoundTripsWithoutASecondSetting() throws {
        for hidden in [false, true] {
            let legacy = Data("{\"hiddenStates\":[\"unknown\"],\"hiddenProjectIDs\":[\"p\"],\"hideArchived\":\(hidden),\"idleTimeout\":\"oneDay\"}".utf8)
            let visibility = try JSONDecoder().decode(CanvasVisibility.self, from: legacy)
            #expect(visibility.hiddenStates.contains(.archived) == hidden)
            #expect(visibility.hiddenStates.contains(.unknown))
            #expect(visibility.hiddenProjectIDs == ["p"])
            #expect(visibility.idleTimeout == .oneDay)
            #expect(try JSONDecoder().decode(CanvasVisibility.self, from: JSONEncoder().encode(visibility)) == visibility)
        }
        var all = CanvasVisibility(); all.hiddenStates = []
        #expect(try JSONDecoder().decode(CanvasVisibility.self, from: JSONEncoder().encode(all)).hiddenStates.isEmpty)
        #expect(NoteState.allCases.suffix(2) == [.archived, .unknown])
    }

    @Test func unknownAgeHidingDefaultsOnAndPreservesWorkAndUnreviewedResults() throws {
        let now = Date(timeIntervalSince1970: 2000000000)
        var visibility = CanvasVisibility(); visibility.idleTimeout = .oneHour
        var session = Session(id: "unknown", title: "Old session", updatedAt: now.addingTimeInterval(-3600))
        session.unknownReason = .historyMissing
        #expect(visibility.hideUnknown)
        #expect(!visibility.includesLifecycle(session, acknowledged: [], now: now))
        session.updatedAt = now.addingTimeInterval(-3599)
        #expect(visibility.includesLifecycle(session, acknowledged: [], now: now))
        session.updatedAt = now.addingTimeInterval(-86400)
        visibility.hideUnknown = false
        #expect(visibility.includesLifecycle(session, acknowledged: [], now: now))
        #expect(try JSONDecoder().decode(CanvasVisibility.self, from: JSONEncoder().encode(visibility)).hideUnknown == false)
        visibility.hideUnknown = true
        session.requests = ["approval": .permission]
        #expect(visibility.includesLifecycle(session, acknowledged: [], now: now))
        session.requests = ["input": .input]
        #expect(visibility.includesLifecycle(session, acknowledged: [], now: now))
        session.requests = [:]; session.execution = .running
        #expect(visibility.includesLifecycle(session, acknowledged: [], now: now))
        session.execution = .unknown
        session.latestResult = SessionResult(id: "unread", outcome: .completed, text: "Done")
        #expect(visibility.includesLifecycle(session, acknowledged: [], now: now))
        #expect(!visibility.includesLifecycle(session, acknowledged: ["unread"], now: now))
        session.latestResult = nil; session.updatedAt = Date(timeIntervalSince1970: 0)
        #expect(visibility.includesLifecycle(session, acknowledged: [], now: now))
        session.updatedAt = now.addingTimeInterval(60)
        #expect(visibility.includesLifecycle(session, acknowledged: [], now: now))
        session.updatedAt = now.addingTimeInterval(-86400); visibility.idleTimeout = .never
        #expect(visibility.includesLifecycle(session, acknowledged: [], now: now))
    }
}
