import SwiftUI
import AppKit
import CanvasCore

struct ContentView: View {
    @ObservedObject var model: ApplicationModel
    var body: some View {
        HSplitView {
            sidebar.frame(minWidth: 215, idealWidth: 225, maxWidth: 270)
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.stateFilter?.label ?? "Your workspace").font(.title2.weight(.semibold))
                        Text("A little space for everything in flight.").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.mode == .demo {
                        Text("DEMO").font(.caption2.weight(.bold)).tracking(1.3).padding(.horizontal, 10).padding(.vertical, 5).background(.orange.opacity(0.12), in: Capsule()).foregroundStyle(.orange)
                    }
                    Button { model.fitRequest += 1 } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }.help("Fit to content (⌘0)")
                    Button { model.beginCreation(at: model.workspace.viewport.world(Point(300, 160))) } label: { Label("New session", systemImage: "plus") }.keyboardShortcut("n")
                }.padding(.horizontal, 26).padding(.vertical, 21)
                Divider()
                ZStack {
                    NativeCanvas(model: model)
                    if model.workspace.sessions.isEmpty && !model.isRefreshing {
                        VStack(spacing: 16) {
                            Image(systemName: "square.grid.3x3.square").font(.system(size: 40, weight: .ultraLight)).foregroundStyle(.tertiary)
                            Text(model.connected ? "A clear canvas" : "Make room for your sessions").font(.title2.weight(.medium))
                            Text(model.connected ? "Sessions from your connected source will appear here." : "Connect to saved Codex sessions or explore the native canvas with demo data.")
                                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 340)
                            HStack {
                                Button("Connection settings…") { model.showsSettings = true }
                                Button("Explore demo") { Task { await model.connect(mode: .demo) } }.buttonStyle(.borderedProminent)
                            }
                        }.padding(30).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    }
                    if model.isRefreshing && model.workspace.sessions.isEmpty { ProgressView("Finding sessions…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                HStack(spacing: 14) {
                    Image(systemName: "hand.draw").foregroundStyle(.tertiary)
                    Text("Scroll to pan · Pinch to zoom · Right-click to create").font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text("\(model.visibleSessions.count) sessions").font(.caption).foregroundStyle(.secondary)
                    Divider().frame(height: 14)
                    Text("\(Int(model.workspace.viewport.zoom * 100))%").font(.caption.monospacedDigit()).frame(width: 38)
                }.padding(.horizontal, 20).padding(.vertical, 11)
            }.frame(minWidth: 530)
            if model.selectedSessionID != nil { SessionViewer(model: model).frame(minWidth: 330, idealWidth: 400, maxWidth: 560) }
        }
        .frame(minWidth: 960, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .navigation) { Image(systemName: "square.stack.3d.up.fill").foregroundStyle(.tint) }
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Circle().fill(model.connected ? Color.green : Color.orange).frame(width: 6, height: 6)
                    Text(model.connectionStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                TextField("Find a session", text: $model.search).textFieldStyle(.roundedBorder).frame(width: 190)
                Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }.disabled(!model.connected || model.isRefreshing).help("Refresh sessions")
                Button { model.showsSettings = true } label: { Image(systemName: "slider.horizontal.3") }.help("Connection settings")
            }
        }
        .sheet(isPresented: $model.showsSettings) { ConnectionView(model: model) }
        .sheet(item: $model.creation) { context in NewSessionView(model: model, context: context) }
        .alert("Couldn’t complete that action", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Text("SESSION CANVAS").font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(2.2).foregroundStyle(.secondary)
                Text("A place to think.").font(.system(size: 21, weight: .medium, design: .serif))
            }.padding(.horizontal, 20).padding(.top, 29).padding(.bottom, 27)
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    sidebarRow("All sessions", symbol: "square.grid.2x2", count: model.workspace.sessions.count, selected: model.stateFilter == nil) { model.stateFilter = nil }
                    Text("ATTENTION").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(.tertiary).padding(.top, 24).padding(.bottom, 8).padding(.leading, 10)
                    ForEach([NoteState.running, .waiting, .permission, .finished, .idle, .unknown], id: \.rawValue) { state in
                        sidebarRow(state.label, symbol: state.symbol, count: model.workspace.sessions.filter { model.state($0) == state }.count, selected: model.stateFilter == state, color: Color(nsColor: state.color)) { model.stateFilter = state }
                    }
                    HStack {
                        Text("PROJECTS").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(.tertiary)
                        Spacer()
                        Text("\(model.workspace.projects.count)").font(.caption2).foregroundStyle(.tertiary)
                    }.padding(.top, 25).padding(.bottom, 8).padding(.horizontal, 10)
                    if model.workspace.projects.isEmpty {
                        Text("Project membership isn’t exposed by this Codex connection.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 10).padding(.bottom, 8)
                    }
                    ForEach(model.workspace.projects) { project in
                        sidebarRow(project.name, symbol: "folder", count: model.workspace.sessions.filter { $0.projectID == project.id }.count, selected: false) {
                            model.stateFilter = nil; model.focusedProjectID = project.id; model.focusRequest += 1
                        }
                    }
                }.padding(.horizontal, 10)
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 10) {
                if model.unreviewedCount > 0 {
                    Label("\(model.unreviewedCount) results to review", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
                }
                Menu {
                    ForEach(SourceMode.allCases) { mode in Button(mode.title) { Task { await model.connect(mode: mode) } } }
                } label: { Label(model.mode.title, systemImage: model.mode == .demo ? "play.square" : "externaldrive.connected.to.line.below") }.menuStyle(.borderlessButton)
                Text(model.sourceExplanation).font(.system(size: 10)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }.padding(18)
        }.background(.thinMaterial)
    }
    private func sidebarRow(_ label: String, symbol: String, count: Int, selected: Bool, color: Color = .secondary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 18).foregroundStyle(selected ? Color.accentColor : color)
                Text(label).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.font(.system(size: 12)).padding(.horizontal, 10).padding(.vertical, 9)
                .background(selected ? Color.accentColor.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct SessionViewer: View {
    @ObservedObject var model: ApplicationModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let session = model.selectedSession {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SESSION").font(.system(size: 9, weight: .semibold)).tracking(1.8).foregroundStyle(.tertiary)
                        Text(session.title).font(.title3.weight(.semibold)).textSelection(.enabled)
                        Label(model.state(session).label, systemImage: model.state(session).symbol).font(.caption).foregroundStyle(Color(nsColor: model.state(session).color))
                    }
                    Spacer()
                    Button { model.selectedSessionID = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(.secondary).help("Close viewer")
                }.padding(22)
                if model.mode == .history {
                    Label("Saved history · current execution is unknown", systemImage: "clock.arrow.circlepath").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.bottom, 16)
                }
                Divider()
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            if model.nextHistoryCursor != nil { Button("Load older history") { Task { await model.loadHistory(older: true) } }.disabled(model.isLoadingHistory).frame(maxWidth: .infinity) }
                            ForEach(model.history) { entry in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Image(systemName: entry.result == nil ? (entry.role == "You" ? "person.crop.circle" : "sparkle") : "checkmark.circle")
                                        Text(entry.role.uppercased()).tracking(1.3)
                                        Spacer()
                                    }.font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                                    Text(entry.text).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                    if let result = entry.result {
                                        if (model.acknowledgments[session.id] ?? []).contains(result.id) {
                                            Label("Acknowledged", systemImage: "checkmark.seal.fill").font(.caption).foregroundStyle(.green).padding(.top, 5)
                                        } else {
                                            Button { model.acknowledge(result, sessionID: session.id) } label: { Label("Acknowledge result", systemImage: "checkmark") }.buttonStyle(.borderedProminent).controlSize(.small).padding(.top, 5)
                                        }
                                    }
                                }.padding(16).background(entry.result != nil ? Color.green.opacity(0.045) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                                    .id(entry.id)
                            }
                            if model.isLoadingHistory { ProgressView().frame(maxWidth: .infinity).padding() }
                            if let error = model.historyError {
                                Text(error).font(.caption).foregroundStyle(.secondary)
                                Button("Retry history") { Task { await model.loadHistory(older: false) } }
                            }
                            if !model.isLoadingHistory && model.history.isEmpty && model.historyError == nil {
                                Text("No messages have been recorded yet.").foregroundStyle(.secondary).font(.callout).padding(.vertical)
                            }
                        }.padding(18)
                    }
                    .onChange(of: model.selectedSessionID) { _, _ in if let last = model.history.last { reader.scrollTo(last.id, anchor: .bottom) } }
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    if let latest = session.latestResult, !model.history.contains(where: { $0.result?.id == latest.id }) {
                        Button("View latest result") { Task { await model.loadHistory(older: false) } }.font(.caption)
                    }
                    HStack {
                        Button { Task { await model.loadHistory(older: false) } } label: { Image(systemName: "arrow.clockwise") }.help("Load latest history").disabled(model.isLoadingHistory)
                        Spacer()
                        Button { model.openInCodex(session) } label: { Label("Open in Codex", systemImage: "arrow.up.forward.app") }.disabled(model.mode == .demo)
                    }
                    Text("Opening never acknowledges a result. Continue work and answer requests in Codex.").font(.system(size: 10)).foregroundStyle(.tertiary)
                }.padding(18)
            }
        }.background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ConnectionView: View {
    @ObservedObject var model: ApplicationModel
    @Environment(\.dismiss) var dismiss
    @StateObject private var form = SessionFormState()
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Connect your workspace").font(.title2.weight(.semibold))
            Text("Session Canvas keeps its own layout and acknowledgments. Your Codex conversations stay where they are.").foregroundStyle(.secondary).font(.callout)
            Form {
                Picker("Source", selection: $form.mode) { ForEach(SourceMode.allCases) { Text($0.title).tag($0) } }
                TextField("Codex executable", text: $form.connection.executable)
                if form.mode == .shared { TextField("Control socket (optional)", text: $form.connection.socket) }
                TextField("Native URL template", text: $form.connection.nativeURLTemplate)
            }.formStyle(.grouped)
            Text(form.mode == .history ? "Saved sessions reads history through the installed Codex CLI. It does not resume turns or infer live state. Desktop project changes and session creation are unavailable." : form.mode == .shared ? "Connects through codex app-server proxy. The desktop app must expose a reachable shared control socket. Project membership and desktop session creation are not part of the verified protocol." : "An isolated sample workspace for exploring every canvas interaction. It never starts real Codex work.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Connect") { model.settings = form.connection; model.saveSettings(); dismiss(); Task { await model.connect(mode: form.mode) } }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 540).onAppear { form.mode = model.mode; form.connection = model.settings }
    }
}

struct NewSessionView: View {
    @ObservedObject var model: ApplicationModel
    let context: ApplicationModel.CreationContext
    @Environment(\.dismiss) var dismiss
    @StateObject private var form = SessionFormState()
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Start something new").font(.title2.weight(.semibold))
            if model.canCreate {
                TextField("Session name (optional)", text: $form.title).textFieldStyle(.roundedBorder)
                Picker("Project", selection: $form.projectID) {
                    Text("No project").tag("")
                    ForEach(model.workspace.projects) { Text($0.name).tag($0.id) }
                }
                TextEditor(text: $form.prompt).font(.body).frame(height: 150).padding(6).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                Text("Demo mode: the session will run briefly and produce a sample result.").font(.caption).foregroundStyle(.secondary)
            } else {
                Label("Desktop session creation is unavailable", systemImage: "link.badge.plus").font(.headline)
                Text("This connection can browse existing conversations, but cannot create a session in the running desktop source. Start it in Codex and refresh, or use Demo workspace to try creation at this canvas position.").font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button(model.canCreate ? "Cancel" : "Close", role: .cancel) { dismiss() }.disabled(model.isCreating)
                if model.canCreate {
                    Button(model.isCreating ? "Starting…" : "Start session") {
                        Task { await model.create(title: form.title, prompt: form.prompt, projectID: form.projectID.isEmpty ? nil : form.projectID, cwd: "Demo workspace") }
                    }.buttonStyle(.borderedProminent).disabled(model.isCreating || form.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).keyboardShortcut(.defaultAction)
                }
            }
        }.padding(28).frame(width: 500).onAppear { form.projectID = context.projectID ?? "" }
        .interactiveDismissDisabled(model.isCreating)
    }
}

@MainActor
final class SessionFormState: ObservableObject {
    @Published var mode = SourceMode.history
    @Published var title = ""
    @Published var prompt = ""
    @Published var projectID = ""
    @Published var connection = ConnectionSettings.defaults
}
