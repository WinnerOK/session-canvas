import SwiftUI
import AppKit
import CanvasCore

struct ContentView: View {
    @ObservedObject var model: ApplicationModel
    var body: some View {
        NavigationSplitView(columnVisibility: $model.sidebarVisibility) {
            sidebar.navigationSplitViewColumnWidth(min: 215, ideal: 225, max: 270)
        } detail: {
            HSplitView {
                VStack(spacing: 0) {
                    ZStack {
                        NativeCanvas(model: model)
                        if !model.workspace.sessions.isEmpty && model.visibleSessions.isEmpty && !model.isRefreshing {
                            VStack(spacing: 14) {
                                Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 32)).foregroundStyle(.secondary)
                                Text("No sessions to show").font(.title2.weight(.medium))
                                Text("Change attention or project visibility, or clear your search.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                Button("Show all sessions") { model.showAllSessions() }.buttonStyle(.borderedProminent)
                            }.frame(maxWidth: 360).padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                        }
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
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
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
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Circle().fill(model.connected && model.hasLiveState ? Color.green : Color.orange).frame(width: 6, height: 6)
                    Text(model.connectionStatus).font(.caption).foregroundStyle(.secondary)
                    if model.mode == .demo { Text("DEMO").font(.caption2.weight(.bold)).foregroundStyle(.orange) }
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.beginCreation(at: model.workspace.viewport.world(Point(300, 160))) } label: { Label("New session", systemImage: "plus") }
                    .help("New session (⌘N)")
                Button { model.fitRequest += 1 } label: { Label("Fit to content", systemImage: "viewfinder") }
                    .help("Fit to content (⌘0)")
                Button { model.toggleFullScreen() } label: { Label("Toggle full screen", systemImage: "arrow.up.left.and.arrow.down.right") }
                    .help("Toggle full screen (⌃⌘F)")
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
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    sidebarRow("All sessions", symbol: "square.grid.2x2", count: model.workspace.sessions.count, selected: !model.visibility.isFiltered && model.search.isEmpty) { model.showAllSessions() }
                    HStack {
                        Text("ATTENTION").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(.tertiary)
                        Spacer()
                        if !model.visibility.hiddenStates.isEmpty {
                            Button("Show all") { model.showAllAttentionStates() }.buttonStyle(.link).font(.caption2)
                        }
                    }.padding(.top, 24).padding(.bottom, 8).padding(.horizontal, 10)
                    ForEach([NoteState.running, .waiting, .permission, .finished, .idle, .unknown], id: \.rawValue) { state in
                        attentionRow(state, count: model.stateCounts[state, default: 0])
                    }
                    HStack {
                        Text("PROJECTS").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(.tertiary)
                        Spacer()
                        Text("\(model.visibleProjects.count)").font(.caption2).foregroundStyle(.tertiary)
                    }.padding(.top, 25).padding(.bottom, 8).padding(.horizontal, 10)
                    if !model.hiddenProjects.isEmpty {
                        Menu {
                            ForEach(model.hiddenProjects) { project in
                                Button("Show \(project.name)") { model.setProjectVisible(project.id, true) }
                            }
                            Divider()
                            Button("Show all projects") { model.showAllProjects() }
                        } label: { Label("Hidden projects (\(model.hiddenProjects.count))", systemImage: "eye.slash") }
                            .menuStyle(.borderlessButton).font(.caption).padding(.horizontal, 10).padding(.bottom, 5)
                    }
                    if model.workspace.projects.isEmpty {
                        Text("No saved local projects found.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 10).padding(.bottom, 8)
                    } else if model.visibleProjects.isEmpty {
                        Text("No projects with visible sessions.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.horizontal, 10).padding(.bottom, 8)
                    }
                    ForEach(model.visibleProjects) { project in projectRow(project) }
                }.padding(.horizontal, 10).padding(.top, 12)
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
    private func attentionRow(_ state: NoteState, count: Int) -> some View {
        Toggle(isOn: Binding(get: { !model.visibility.hiddenStates.contains(state) }, set: { model.setStateVisible(state, $0) })) {
            HStack(spacing: 8) {
                Image(systemName: state.symbol).frame(width: 18).foregroundStyle(Color(nsColor: state.color))
                Text(state.label).lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }.font(.system(size: 12))
        }.toggleStyle(.checkbox).controlSize(.small).padding(.horizontal, 10).padding(.vertical, 7)
            .accessibilityLabel("Show \(state.label) sessions")
    }
    private func projectRow(_ project: Project) -> some View {
        HStack(spacing: 0) {
            sidebarRow(project.name, symbol: "folder", count: model.visibleSessions.filter { $0.projectID == project.id }.count, selected: false) {
                model.focusedProjectID = project.id; model.focusRequest += 1
            }.help(project.name)
            Button { model.setProjectVisible(project.id, false) } label: { Image(systemName: "eye").font(.system(size: 11)) }
                .buttonStyle(.borderless).padding(.trailing, 7).help("Hide \(project.name)").accessibilityLabel("Hide project \(project.name)")
        }
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
                if model.revealedCreationID == session.id {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Session created", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Continue in Codex to send your first instruction. Use Open in Codex to return there. Empty sessions may not appear in Codex’s list yet.")
                        if model.creationIsOutsideFilters {
                            Text("This new session is shown despite your current filters.")
                            Button("Apply filters") { model.applyFiltersToCreation() }.buttonStyle(.link)
                        }
                    }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.bottom, 16)
                }
                if model.mode == .history {
                    Label(session.execution == .unknown ? "Saved history · session is not loaded in Codex" : "Live state from Codex desktop", systemImage: session.execution == .unknown ? "clock.arrow.circlepath" : "waveform").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.bottom, 16)
                }
                VStack(alignment: .leading, spacing: 10) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { acknowledgeButton(session); openInCodexButton(session); reloadButton }
                        VStack(alignment: .leading, spacing: 8) {
                            acknowledgeButton(session)
                            HStack(spacing: 8) { openInCodexButton(session); reloadButton }
                        }
                    }
                    if let latest = session.latestResult, !model.history.contains(where: { $0.result?.id == latest.id }) {
                        Button("View latest result") { Task { await model.loadHistory(older: false) } }
                            .buttonStyle(.link).font(.caption).disabled(model.isLoadingHistory)
                    }
                    if model.nextHistoryCursor != nil {
                        Button("Load older history") { Task { await model.loadHistory(older: true) } }
                            .buttonStyle(.link).font(.caption).disabled(model.isLoadingHistory)
                    }
                    if let error = model.historyError {
                        Text(error).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.controlSize(.small).padding(.horizontal, 22).padding(.bottom, 16)
                Divider()
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(model.history.reversed()) { entry in
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
                                        }
                                    }
                                }.padding(16).background(entry.result != nil ? Color.green.opacity(0.045) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                                    .id(entry.id)
                            }
                            if model.isLoadingHistory { ProgressView().frame(maxWidth: .infinity).padding() }
                            if !model.isLoadingHistory && model.history.isEmpty && model.historyError == nil {
                                Text("No messages have been recorded yet.").foregroundStyle(.secondary).font(.callout).padding(.vertical)
                            }
                        }.padding(18)
                    }
                    .onChange(of: model.history.last?.id) { _, latestID in
                        if let latestID { reader.scrollTo(latestID, anchor: .top) }
                    }
                }.id(session.id)
            }
        }.background(Color(nsColor: .windowBackgroundColor))
    }

    private var displayedResult: SessionResult? { model.history.last { $0.result != nil }?.result }

    private func acknowledgeButton(_ session: Session) -> some View {
        let result = displayedResult
        let acknowledged = result.map { (model.acknowledgments[session.id] ?? []).contains($0.id) } ?? false
        let available = result.map { model.canAcknowledge($0, sessionID: session.id) } ?? false
        return Button {
            if let result { model.acknowledge(result, sessionID: session.id) }
        } label: {
            Label(acknowledged ? "Acknowledged" : "Acknowledge result", systemImage: acknowledged ? "checkmark.seal.fill" : "checkmark")
        }.buttonStyle(.borderedProminent).fixedSize().disabled(!available)
            .help("Available only for Finished sessions with a loaded, unacknowledged result")
    }

    private func openInCodexButton(_ session: Session) -> some View {
        Button { model.openInCodex(session) } label: { Label("Open in Codex", systemImage: "arrow.up.forward.app") }
            .fixedSize().disabled(model.mode == .demo)
    }

    private var reloadButton: some View {
        Button { Task { await model.loadHistory(older: false) } } label: { Label("Reload history", systemImage: "arrow.clockwise") }
            .fixedSize().disabled(model.isLoadingHistory)
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
            Text(form.mode == .history ? "Reads saved sessions and local projects, and automatically follows live state from the running Codex desktop. If Codex is closed, saved history remains available. The desktop-bundled executable also creates sessions ready to open in Codex. Move existing sessions between projects in Codex." : form.mode == .shared ? "Connects through codex app-server proxy to a reachable shared control socket, and reads saved local projects. Change project membership and create sessions in Codex." : "An isolated sample workspace for exploring every canvas interaction. It never starts real Codex work.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
                Group {
                    TextField("Session name (optional)", text: $form.title).textFieldStyle(.roundedBorder)
                    Picker("Project", selection: $form.projectID) {
                        Text("No project").tag("")
                        ForEach(model.workspace.projects) { Text($0.name).tag($0.id) }
                    }
                    if model.mode == .demo {
                        TextEditor(text: $form.prompt).font(.body).frame(height: 150).padding(6).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                        Text("Demo mode: the session will run briefly and produce a sample result.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        if form.projectID.isEmpty {
                            HStack {
                                TextField("Working folder (optional)", text: $form.directory).textFieldStyle(.roundedBorder)
                                Button("Choose…") {
                                    let panel = NSOpenPanel()
                                    panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
                                    if panel.runModal() == .OK, let url = panel.url { form.directory = url.path }
                                }
                            }
                            Text("Leave blank to create a separate working folder in Session Canvas’s application data.").font(.caption).foregroundStyle(.secondary)
                        } else if !form.directory.isEmpty {
                            Text(form.directory).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Text("Creates a saved session and opens it in Codex. Enter your first instruction there. A blank name becomes New session.").font(.callout).foregroundStyle(.secondary)
                    }
                }.disabled(model.isCreating)
            } else {
                Label("Session creation is unavailable", systemImage: "link.badge.plus").font(.headline)
                Text(model.creationUnavailableReason).font(.callout).foregroundStyle(.secondary)
            }
            if let error = model.creationError {
                Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("creation-error")
            }
            HStack {
                Spacer()
                Button(model.canCreate ? "Cancel" : "Close", role: .cancel) { dismiss() }.disabled(model.isCreating)
                if model.canCreate {
                    Button(model.isCreating ? "Creating…" : model.mode == .demo ? "Start session" : "Create session") {
                        Task { await model.create(title: form.title, prompt: form.prompt, projectID: form.projectID.isEmpty ? nil : form.projectID, cwd: model.mode == .demo ? "Demo workspace" : form.directory) }
                    }.buttonStyle(.borderedProminent).disabled(model.isCreating || (model.mode == .demo && form.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)).keyboardShortcut(.defaultAction)
                }
            }
        }.padding(28).frame(width: 500).onAppear {
            form.projectID = context.projectID ?? ""
            form.directory = model.creationDirectory(projectID: form.projectID) ?? ""
        }
        .onChange(of: form.projectID) { _, id in form.directory = model.creationDirectory(projectID: id) ?? "" }
        .interactiveDismissDisabled(model.isCreating)
    }
}

@MainActor
final class SessionFormState: ObservableObject {
    @Published var mode = SourceMode.history
    @Published var title = ""
    @Published var prompt = ""
    @Published var projectID = ""
    @Published var directory = ""
    @Published var connection = ConnectionSettings.defaults
}
