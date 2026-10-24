import Foundation
import Testing
import CanvasCore

@Suite struct SessionLifecycleTests {
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
        var visibility = CanvasVisibility(); visibility.idleTimeout = .oneHour
        let result = SessionResult(id: "r", outcome: .completed, text: "Done")
        for execution in [Execution.running, .unknown, .idle] {
            var session = Session(id: "s", title: "Work", execution: execution, latestResult: result, updatedAt: old, isArchived: true)
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
        #expect(visibility.hideArchived)
        #expect(visibility.idleTimeout == .never)
        #expect(visibility.hiddenStates == [.unknown])
        #expect(visibility.hiddenProjectIDs == ["p"])
        let session = Session(id: "s", title: "Old", execution: .idle)
        var payload = try JSONEncoder().encode(session)
        var object = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        object.removeValue(forKey: "archived"); object.removeValue(forKey: "savedState")
        payload = try JSONSerialization.data(withJSONObject: object)
        let restored = try JSONDecoder().decode(Session.self, from: payload)
        #expect(!restored.isArchived && !restored.stateIsFromHistory)
    }
}
