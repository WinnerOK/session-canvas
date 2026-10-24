import Foundation
import Testing
import CanvasCore
@testable import SessionCanvas

@Suite(.serialized) @MainActor
struct CanvasRuntimeTests {
    @Test func openingAndAcknowledgingPersistsOnlyExplicitReview() async throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let model = ApplicationModel(demo: true, storagePath: path)
        await model.connect()
        let session = try #require(model.workspace.sessions.first { $0.id == "demo-state" })
        #expect(model.state(session) == .finished)
        model.openSession(session.id)
        await model.loadHistory(older: false)
        #expect(model.state(session) == .finished)
        let result = try #require(model.history.compactMap(\.result).last)
        model.acknowledge(result, sessionID: session.id)
        #expect(model.state(session) == .idle)
        model.shutdown()

        let restored = ApplicationModel(demo: true, storagePath: path)
        await restored.connect()
        #expect(restored.acknowledgments[session.id]?.contains(result.id) == true)
        #expect(restored.state(try #require(restored.workspace.sessions.first { $0.id == session.id })) == .idle)
        restored.shutdown()
    }
    @Test func displayedOlderResultCannotAcknowledgeNewerResult() async throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let model = ApplicationModel(demo: true, storagePath: path)
        await model.connect()
        model.openSession("demo-state")
        await model.loadHistory(older: false)
        let displayed = try #require(model.history.compactMap(\.result).last)
        let index = try #require(model.workspace.sessions.firstIndex { $0.id == "demo-state" })
        model.workspace.sessions[index].latestResult = SessionResult(id: "new-result", outcome: .completed, text: "A newer result")
        model.acknowledge(displayed, sessionID: "demo-state")
        #expect(model.acknowledgments["demo-state"]?.contains(displayed.id) == true)
        #expect(model.acknowledgments["demo-state"]?.contains("new-result") != true)
        #expect(model.state(model.workspace.sessions[index]) == .finished)
        model.shutdown()
    }
    @Test func projectDropCommitsAfterSourceConfirmationAndPreservesExecution() async throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let model = ApplicationModel(demo: true, storagePath: path)
        await model.connect()
        let session = try #require(model.workspace.sessions.first { $0.id == "demo-native" })
        let destination = Point(630, 246)
        model.moveNote(id: session.id, position: destination, expectedRevision: session.revision)
        #expect(model.pendingSessions.contains(session.id))
        #expect(model.workspace.sessions.first { $0.id == session.id }?.projectID == "canvas")
        try await Task.sleep(for: .milliseconds(400))
        let moved = try #require(model.workspace.sessions.first { $0.id == session.id })
        #expect(moved.projectID == "research")
        #expect(moved.execution == .running)
        #expect(moved.cwd == session.cwd)
        #expect(model.workspace.placements[session.id]?.position == destination)
        #expect(!model.pendingSessions.contains(session.id))
        model.shutdown()
    }
    @Test func reconnectDuringMoveCannotApplyOldCompletionToNewWorkspace() async throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let model = ApplicationModel(demo: true, storagePath: path)
        await model.connect()
        let session = try #require(model.workspace.sessions.first { $0.id == "demo-native" })
        model.moveNote(id: session.id, position: Point(630, 246), expectedRevision: session.revision)
        await model.connect(mode: .demo)
        let positionAfterConnect = model.workspace.placements[session.id]
        try await Task.sleep(for: .milliseconds(400))
        #expect(model.workspace.placements[session.id] == positionAfterConnect)
        #expect(model.workspace.sessions.first { $0.id == session.id }?.projectID == "canvas")
        #expect(model.pendingSessions.isEmpty)
        model.shutdown()
    }
    @Test func staleDropAndInvalidRegionEditsAreRejected() async throws {
        let path = temporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let model = ApplicationModel(demo: true, storagePath: path)
        await model.connect()
        let previous = model.workspace.placements["demo-native"]
        model.moveNote(id: "demo-native", position: Point(630, 246), expectedRevision: "stale")
        #expect(model.workspace.placements["demo-native"] == previous)
        #expect(model.errorMessage != nil)
        let region = model.workspace.regions["canvas"]
        model.editRegion(id: "canvas", rect: Rect(0, 0, 1200, 500))
        #expect(model.workspace.regions["canvas"] == region)
        model.shutdown()
    }
    private func temporaryPath() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent("session-canvas-" + UUID().uuidString + ".sqlite").path
    }
}
