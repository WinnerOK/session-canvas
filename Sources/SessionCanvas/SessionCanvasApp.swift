import SwiftUI
import AppKit
import CanvasCore

@main
struct SessionCanvasApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) var delegate
    @StateObject private var model: ApplicationModel
    init() {
        let args = CommandLine.arguments
        let storageIndex = args.firstIndex(of: "--storage")
        let path = storageIndex.flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        _model = StateObject(wrappedValue: ApplicationModel(demo: args.contains("--demo"), storagePath: path))
    }
    var body: some Scene {
        Window("Session Canvas", id: "canvas") {
            ContentView(model: model)
                .task { delegate.model = model; await model.connect(); captureIfRequested() }
        }
        .defaultSize(width: 1420, height: 880)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appSettings) { Button("Connection Settings…") { model.showsSettings = true }.keyboardShortcut(",") }
            CommandGroup(after: .newItem) {
                Button("New Session…") { model.beginCreation(at: model.workspace.viewport.world(.init(300, 160))) }.keyboardShortcut("n")
                Button("Refresh Sessions") { model.startStatusRefresh() }.keyboardShortcut("r").disabled(!model.connected || model.isRefreshing)
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") { model.toggleSidebar() }.keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Fit to Content") { model.fitRequest += 1 }.keyboardShortcut("0")
                Button("Show All in This Layer") { model.showAllSessions() }.keyboardShortcut("1")
            }
        }
    }
    private func captureIfRequested() {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--capture"), index + 1 < args.count else { return }
        let path = args[index + 1]
        Task { @MainActor in
            if let layerIndex = args.firstIndex(of: "--layer"), layerIndex + 1 < args.count,
               let layer = CanvasLayer(rawValue: args[layerIndex + 1]) { model.selectLayer(layer) }
            if args.contains("--show-result"), model.mode == .demo {
                model.openSession("demo-state")
                await model.loadHistory(older: false)
                model.fitRequest += 1
            }
            if let index = args.firstIndex(of: "--show-session"), index + 1 < args.count {
                if args.contains("--created-session-preview") { model.revealCreatedSession(args[index + 1]) }
                else { model.openSession(args[index + 1]) }
            }
            if args.contains("--hide-sidebar") { model.toggleSidebar() }
            try? await Task.sleep(for: .seconds(2))
            guard let window = NSApp.windows.first(where: { $0.title == "Session Canvas" }), let view = window.contentView?.superview,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { NSApp.terminate(nil); return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: path)) }
            NSApp.terminate(nil)
        }
    }
}

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var model: ApplicationModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }
}
