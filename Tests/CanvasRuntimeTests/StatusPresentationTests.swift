import AppKit
import SwiftUI
import Testing
import CanvasCore
@testable import SessionCanvas

@Suite(.serialized) @MainActor
struct StatusPresentationTests {
    @Test func unknownApprovalIsVisibleOnNoteViewerAndAccessibility() throws {
        _ = NSApplication.shared
        let model = ApplicationModel(demo: false, storagePath: ":memory:")
        defer { model.shutdown() }
        var session = Session(id: "pending", title: "Review service changes", execution: .running,
                              requests: ["approval-42": .permission])
        session.invalidateExecution()
        session.unknownReason = .historyMissing
        model.workspace.reconcile(sessions: [session], projects: [])
        model.synchronizeLayers(); model.selectLayer(.inactive)
        model.workspace.placements[session.id] = Placement(Point(30, 30))
        model.workspace.viewport = Viewport(origin: Point(0, 0), zoom: 1)
        model.selectedSessionID = session.id
        let canvas = CanvasNSView(model: model)
        canvas.frame = NSRect(x: 0, y: 0, width: 500, height: 380)
        let canvasWindow = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        canvasWindow.contentView = canvas
        canvas.update()
        let element = try #require(canvas.accessibilityChildren()?.first as? NSAccessibilityElement)
        #expect(element.accessibilityLabel()?.contains("Unknown, Last known: Permission required") == true)
        try capture(HStack(spacing: 0) {
            NativeCanvas(model: model).frame(width: 500, height: 500)
            Divider()
            SessionViewer(model: model).frame(width: 400, height: 500)
        }, size: NSSize(width: 901, height: 500), name: "unknown-approval")
        #expect(model.state(session) == .unknown && model.acknowledgments.isEmpty)
    }

    @Test func progressAndFinalSummaryRenderWithoutAConnectedSource() throws {
        _ = NSApplication.shared
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        defer { model.shutdown() }
        var progress = StatusRefreshProgress()
        progress.total = 448; progress.completed = 229; progress.failed = 1; progress.unresolved = 2
        model.statusRefreshProgress = progress
        try capture(StatusRefreshView(model: model), size: NSSize(width: 470, height: 300), name: "status-progress")
        progress.completed = 448; progress.isComplete = true
        model.statusRefreshProgress = progress
        try capture(StatusRefreshView(model: model), size: NSSize(width: 470, height: 300), name: "status-summary")
    }

    private func capture<V: View>(_ view: V, size: NSSize, name: String) throws {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: "/private/tmp/session-canvas-\(name).png"))
    }
}
