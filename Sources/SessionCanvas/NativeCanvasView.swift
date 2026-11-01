import AppKit
import SwiftUI
import CanvasCore

extension NoteState {
    var color: NSColor {
        switch self {
        case .running: return .systemBlue
        case .waiting: return .systemOrange
        case .permission: return .systemPurple
        case .finished: return .systemGreen
        case .idle: return .secondaryLabelColor
        case .archived: return .systemBrown
        case .unknown: return .systemGray
        }
    }
}

struct NativeCanvas: NSViewRepresentable {
    @ObservedObject var model: ApplicationModel
    func makeNSView(context: Context) -> CanvasNSView { CanvasNSView(model: model) }
    func updateNSView(_ view: CanvasNSView, context: Context) { view.update() }
}

@MainActor
final class CanvasNSView: NSView {
    private unowned let model: ApplicationModel
    private var fitVersion = -1
    private var focusVersion = -1
    private var localViewport: Viewport?
    private var drag: Drag?
    private var mouseDownPoint = Point(0, 0)
    private var moved = false
    private var contextPoint = Point(0, 0)
    private var contextSession: String?
    private enum Focus: Equatable { case session(String), project(String) }
    private var focusedItem: Focus?
    private var contextProject: String?
    private var spaceDown = false
    private var regionHover: String?
    private var tracking: NSTrackingArea?
    private var dragGeneration: Int?
    private var dragLayer: CanvasLayer?
    private var displayedLayer: CanvasLayer?
    private enum Drag {
        case note(id: String, position: Point, revision: String)
        case region(id: String, bounds: Rect, zoomOnClick: Bool)
        case resize(id: String, bounds: Rect)
        case pan(origin: Point)
    }
    init(model: ApplicationModel) {
        self.model = model
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        setAccessibilityRole(.group)
        setAccessibilityLabel("Session canvas")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isFlipped: Bool { true }
    override var wantsDefaultClipping: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    private var viewport: Viewport { localViewport ?? model.workspace.viewport }
    override func setFrameSize(_ newSize: NSSize) {
        let oldSize = bounds.size
        super.setFrameSize(newSize)
        guard oldSize.width > 0, oldSize.height > 0, newSize != oldSize, localViewport == nil,
              let id = model.revealedCreationID, model.selectedSessionID == id, model.focusedSessionID == id,
              let placement = model.workspace.placements[id] else { return }
        let center = viewport.screen(placement.center)
        // SwiftUI can size the viewer after the initial focus request. Preserve
        // that center through layout, but don't undo a subsequent user pan.
        guard abs(center.x - oldSize.width / 2) < 0.5, abs(center.y - oldSize.height / 2) < 0.5 else { return }
        var next = viewport
        next.origin = next.origin + Point((newSize.width - oldSize.width) / 2, (newSize.height - oldSize.height) / 2)
        model.setViewport(next)
    }
    private var showsProjectOverview: Bool { CanvasOverview.sessionContentLayout(at: viewport.zoom) == nil }
    private var renderedSessions: [Session] {
        model.visibleSessions.filter { !showsProjectOverview || $0.projectID == nil }
    }
    private var projectOverviews: [ProjectOverview] {
        model.visibleProjects.compactMap { project in
            guard let region = renderedRegion(project.id) else { return nil }
            let rect = screen(region)
            guard rect.intersects(bounds) else { return nil }
            let members = model.visibleSessions.filter { $0.projectID == project.id }
            let states = Set(members.map { model.state($0) })
            let state = [NoteState.permission, .waiting, .running, .finished, .archived, .unknown, .idle].first { states.contains($0) } ?? .idle
            return ProjectOverview(project: project, region: rect, count: members.count, state: state)
        }
    }
    func update() {
        if displayedLayer != model.selectedLayer {
            displayedLayer = model.selectedLayer; focusedItem = nil; localViewport = nil
        }
        if drag != nil && (dragGeneration != model.geometryGeneration || dragLayer != model.selectedLayer) {
            drag = nil; localViewport = nil; regionHover = nil; focusedItem = nil
        }
        if fitVersion != model.fitRequest && bounds.width > 0 {
            fitVersion = model.fitRequest
            if fitVersion > 0 { fitContent() }
        }
        if focusVersion != model.focusRequest, let id = model.focusedProjectID, let rect = model.visibleRegions[id], bounds.width > 0 {
            focusVersion = model.focusRequest
            let width = Double(bounds.width), height = Double(bounds.height)
            let scale = max(0.75, min(1, min((width - 80) / rect.width, (height - 80) / rect.height)))
            let top = rect.height * scale > height - 80 ? 40 : (height - rect.height * scale) / 2
            model.setViewport(Viewport(origin: Point((width - rect.width * scale) / 2 - rect.x * scale, top - rect.y * scale), zoom: scale))
        } else if focusVersion != model.focusRequest, let id = model.focusedSessionID,
                  let placement = model.workspace.placements[id], bounds.width > 0 {
            focusVersion = model.focusRequest
            let scale = max(0.75, min(1, viewport.zoom))
            model.setViewport(Viewport(origin: Point(bounds.width / 2 - placement.center.x * scale,
                bounds.height / 2 - placement.center.y * scale), zoom: scale))
        }
        needsDisplay = true
        rebuildAccessibility()
    }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
        super.updateTrackingAreas()
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    private func point(_ event: NSEvent) -> Point {
        let p = convert(event.locationInWindow, from: nil)
        return Point(p.x, p.y)
    }
    private func screen(_ rect: Rect) -> NSRect {
        let p = viewport.screen(Point(rect.x, rect.y))
        return NSRect(x: p.x, y: p.y, width: rect.width * viewport.zoom, height: rect.height * viewport.zoom)
    }
    private func text(_ string: String, in rect: NSRect, font: NSFont, color: NSColor, lines: NSLineBreakMode = .byTruncatingTail) {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = lines
        (string as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill(); bounds.fill()
        drawGrid()
        let scale = viewport.zoom
        for project in model.visibleProjects {
            guard let region = renderedRegion(project.id) else { continue }
            let rect = screen(region)
            guard rect.intersects(bounds) else { continue }
            let highlighted = regionHover == project.id
            NSColor.controlAccentColor.withAlphaComponent(highlighted ? 0.10 : 0.035).setFill()
            let path = NSBezierPath(roundedRect: rect, xRadius: 18 * scale, yRadius: 18 * scale); path.fill()
            NSColor.controlAccentColor.withAlphaComponent(highlighted ? 0.7 : 0.18).setStroke()
            path.lineWidth = highlighted ? 2 : 1; path.stroke()
            if !showsProjectOverview {
                let count = model.visibleSessions.filter { $0.projectID == project.id }.count
                let titleFont = NSFont.systemFont(ofSize: max(12, 14 * scale), weight: .semibold)
                let countFont = NSFont.systemFont(ofSize: max(10, 11 * scale))
                let countText = "\(count) sessions"
                let countWidth = ceil((countText as NSString).size(withAttributes: [.font: countFont]).width)
                let inset = max(10, 20 * scale)
                text(project.name, in: NSRect(x: rect.minX + inset, y: rect.minY + 12 * scale, width: max(0, rect.width - inset * 3 - countWidth), height: lineHeight(titleFont)), font: titleFont, color: .labelColor)
                text(countText, in: NSRect(x: rect.maxX - inset - countWidth, y: rect.minY + 14 * scale, width: countWidth + 1, height: lineHeight(countFont)), font: countFont, color: .secondaryLabelColor)
                let grip = NSBezierPath()
                for i in 0..<3 {
                    let inset = Double(i) * 4 + 8
                    grip.move(to: NSPoint(x: rect.maxX - inset * scale, y: rect.maxY - 5 * scale))
                    grip.line(to: NSPoint(x: rect.maxX - 5 * scale, y: rect.maxY - inset * scale))
                }
                NSColor.tertiaryLabelColor.setStroke(); grip.lineWidth = 1; grip.stroke()
            }
        }
        for session in renderedSessions {
            guard var placement = model.workspace.placements[session.id] else { continue }
            if case .note(let id, let original, _) = drag, id == session.id, moved { placement.position = original + dragDelta }
            if case .region(let id, _, _) = drag, session.projectID == id, moved { placement.position = placement.position + dragDelta }
            let rect = screen(placement.rect)
            guard rect.intersects(bounds.insetBy(dx: -20, dy: -20)) else { continue }
            drawNote(session, rect: rect, scale: scale)
        }
        if showsProjectOverview {
            for item in projectOverviews { drawOverview(item) }
        }
    }
    private func lineHeight(_ font: NSFont) -> CGFloat { ceil(font.ascender - font.descender + font.leading) + 2 }
    private func drawOverview(_ item: ProjectOverview) {
        let rect = item.region
        if focusedItem == .project(item.project.id) {
            let path = NSBezierPath(roundedRect: rect, xRadius: 18 * viewport.zoom, yRadius: 18 * viewport.zoom)
            NSColor.controlAccentColor.setStroke(); path.lineWidth = 2; path.stroke()
        }
        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        guard let titleFrame = CanvasOverview.titleFrame(for: item.project.name, in: rect, font: font) else { return }
        text(item.project.name, in: titleFrame, font: font, color: .labelColor)
        let countFont = NSFont.systemFont(ofSize: 11)
        let count = "\(item.count) \(item.count == 1 ? "session" : "sessions")"
        let countFrame = NSRect(x: titleFrame.minX + 14, y: titleFrame.maxY + 4, width: titleFrame.width - 14, height: lineHeight(countFont))
        guard countFrame.maxY <= rect.maxY - 8,
              countFrame.width >= ceil((count as NSString).size(withAttributes: [.font: countFont]).width) else { return }
        item.state.color.setFill()
        NSBezierPath(ovalIn: NSRect(x: titleFrame.minX, y: countFrame.midY - 3, width: 6, height: 6)).fill()
        text(count, in: countFrame, font: countFont, color: .secondaryLabelColor)
    }
    private func drawGrid() {
        let step = 28 * viewport.zoom
        guard step >= 7 else { return }
        let xStart = viewport.origin.x.truncatingRemainder(dividingBy: step), yStart = viewport.origin.y.truncatingRemainder(dividingBy: step)
        NSColor.quaternaryLabelColor.withAlphaComponent(0.45).setFill()
        for x in stride(from: xStart, through: Double(bounds.width), by: step) {
            for y in stride(from: yStart, through: Double(bounds.height), by: step) {
                NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 1.5, height: 1.5)).fill()
            }
        }
    }
    private func drawNote(_ session: Session, rect: NSRect, scale: Double) {
        let state = model.state(session)
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let base = dark ? NSColor(calibratedWhite: 0.16, alpha: 1) : .white
        let fill = base.blended(withFraction: dark ? 0.14 : 0.10, of: state.color) ?? base
        let path = NSBezierPath(roundedRect: rect, xRadius: 12 * scale, yRadius: 12 * scale)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.18 : 0.07)
        shadow.shadowBlurRadius = 12 * scale; shadow.shadowOffset = NSSize(width: 0, height: -3 * scale); shadow.set()
        fill.setFill(); path.fill()
        NSGraphicsContext.restoreGraphicsState()
        let selected = model.selectedSessionID == session.id || focusedItem == .session(session.id)
        (selected ? NSColor.controlAccentColor : state.color.withAlphaComponent(0.22)).setStroke()
        path.lineWidth = selected ? 2 : 1; path.stroke()
        guard let content = CanvasOverview.sessionContentLayout(at: scale) else { return }
        if scale < 0.85 {
            let (inset, titleFont, titleHeight) = content
            text(session.title, in: NSRect(x: rect.minX + inset, y: rect.minY + inset, width: rect.width - inset * 2, height: titleHeight), font: titleFont, color: .labelColor, lines: .byWordWrapping)
            let stateFont = NSFont.systemFont(ofSize: 10)
            text(state.label + " · " + (model.lastKnownLabel(session) ?? model.activityLabel(session)), in: NSRect(x: rect.minX + inset, y: rect.maxY - inset - lineHeight(stateFont), width: rect.width - inset * 2, height: lineHeight(stateFont)), font: stateFont, color: state.color)
            return
        }
        let inset = 16 * scale
        NSColor.labelColor.setFill()
        text(session.title, in: NSRect(x: rect.minX + inset, y: rect.minY + 17 * scale, width: rect.width - inset * 2, height: 48 * scale), font: .systemFont(ofSize: max(9, 14 * scale), weight: .semibold), color: .labelColor, lines: .byWordWrapping)
        let iconRect = NSRect(x: rect.minX + inset, y: rect.minY + 77 * scale, width: 13 * scale, height: 13 * scale)
        let configuration = NSImage.SymbolConfiguration(pointSize: 13 * scale, weight: .medium).applying(.init(paletteColors: [state.color]))
        NSImage(systemSymbolName: state.symbol, accessibilityDescription: state.label)?.withSymbolConfiguration(configuration)?.draw(in: iconRect)
        text(state.label, in: NSRect(x: rect.minX + 36 * scale, y: rect.minY + 75 * scale, width: rect.width - 48 * scale, height: 22 * scale), font: .systemFont(ofSize: max(8, 11 * scale), weight: .medium), color: state.color)
        let footer: String
        if model.pendingSessions.contains(session.id) { footer = "Moving to project…" }
        else if let label = model.lastKnownLabel(session) { footer = label }
        else if let result = session.latestResult {
            let seen = (model.acknowledgments[session.id] ?? []).contains(result.id)
            footer = state == .archived ? result.outcome.label : seen ? "Result acknowledged" : "\(result.outcome.label) · review result"
        } else if !session.cwd.isEmpty { footer = URL(fileURLWithPath: session.cwd).lastPathComponent }
        else { footer = model.mode == .demo ? "Demo session" : "Codex session" }
        text(footer, in: NSRect(x: rect.minX + inset, y: rect.minY + 100 * scale, width: rect.width - inset * 2, height: 18 * scale), font: .systemFont(ofSize: max(8, 10 * scale)), color: .secondaryLabelColor)
        text(model.activityLabel(session), in: NSRect(x: rect.minX + inset, y: rect.maxY - 25 * scale, width: rect.width - inset * 2 - 18 * scale, height: 18 * scale), font: .systemFont(ofSize: max(8, 10 * scale)), color: .secondaryLabelColor)
        if state == .finished {
            text("↗", in: NSRect(x: rect.maxX - 32 * scale, y: rect.maxY - 32 * scale, width: 16 * scale, height: 16 * scale), font: .systemFont(ofSize: 13 * scale), color: state.color)
        }
    }
    private var currentPoint = Point(0, 0)
    private var dragDelta: Point { Point((currentPoint.x - mouseDownPoint.x) / viewport.zoom, (currentPoint.y - mouseDownPoint.y) / viewport.zoom) }
    private func previewRegion(_ rect: Rect) -> Rect { rect.translated(dragDelta) }
    private func previewResize(_ rect: Rect) -> Rect { Rect(rect.x, rect.y, max(300, rect.width + dragDelta.x), max(240, rect.height + dragDelta.y)) }
    private func renderedRegion(_ id: String) -> Rect? {
        guard let rect = model.workspace.regions[id] else { return nil }
        if moved {
            if case .region(let selected, let original, _) = drag, selected == id { return previewRegion(original) }
            if case .resize(let selected, let original) = drag, selected == id { return previewResize(original) }
        }
        return rect
    }
    private func hitNote(_ point: Point) -> Session? {
        renderedSessions.reversed().first { model.workspace.placements[$0.id]?.rect.contains(point) == true }
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        mouseDownPoint = point(event); currentPoint = mouseDownPoint; moved = false
        dragGeneration = model.geometryGeneration; dragLayer = model.selectedLayer
        let world = viewport.world(mouseDownPoint)
        if !spaceDown, showsProjectOverview, let item = projectOverviews.reversed().first(where: { $0.frame.contains(NSPoint(x: mouseDownPoint.x, y: mouseDownPoint.y)) }) {
            focusedItem = .project(item.project.id)
            if let rect = model.workspace.regions[item.project.id] { drag = .region(id: item.project.id, bounds: rect, zoomOnClick: true) }
        } else if !spaceDown, let session = hitNote(world), let placement = model.workspace.placements[session.id] {
            focusedItem = .session(session.id)
            drag = .note(id: session.id, position: placement.position, revision: session.revision)
        } else if !spaceDown, !showsProjectOverview, let id = model.visibleProject(at: world), let rect = model.workspace.regions[id], world.x > rect.x + rect.width - 24 && world.y > rect.y + rect.height - 24 {
            drag = .resize(id: id, bounds: rect)
        } else if !spaceDown, !showsProjectOverview, let id = model.visibleProject(at: world), let rect = model.workspace.regions[id], world.y < rect.y + 48 {
            drag = .region(id: id, bounds: rect, zoomOnClick: false)
        } else { drag = .pan(origin: viewport.origin) }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        currentPoint = point(event)
        if hypot(currentPoint.x - mouseDownPoint.x, currentPoint.y - mouseDownPoint.y) > 4 { moved = true }
        switch drag {
        case .pan(let origin):
            var value = viewport; value.origin = origin + (currentPoint - mouseDownPoint)
            localViewport = value
        case .note(_, let original, _):
            regionHover = model.visibleProject(at: Placement(original + dragDelta).center)
        default: break
        }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard dragGeneration == model.geometryGeneration, dragLayer == model.selectedLayer else {
            drag = nil; localViewport = nil; regionHover = nil; needsDisplay = true; return
        }
        currentPoint = point(event)
        switch drag {
        case .note(let id, let original, let revision):
            if moved { model.moveNote(id: id, position: original + dragDelta, expectedRevision: revision) }
            else { model.openSession(id) }
        case .region(let id, let original, let zoomOnClick):
            if moved { model.editRegion(id: id, rect: previewRegion(original)) }
            else if zoomOnClick { focusProject(id) }
        case .resize(let id, let original): if moved { model.editRegion(id: id, rect: previewResize(original)) }
        case .pan: if let value = localViewport { model.setViewport(value) }
        case nil: break
        }
        drag = nil; localViewport = nil; regionHover = nil; needsDisplay = true
    }
    override func scrollWheel(with event: NSEvent) {
        guard drag == nil else { return }
        var value = viewport
        if event.modifierFlags.contains(.command) { value.zoom(to: value.zoom * exp(-event.scrollingDeltaY * 0.012), around: point(event)) }
        else {
            let factor = event.hasPreciseScrollingDeltas ? 1.0 : 14.0
            value.origin = value.origin + Point(event.scrollingDeltaX * factor, event.scrollingDeltaY * factor)
        }
        model.setViewport(value); needsDisplay = true
    }
    override func magnify(with event: NSEvent) {
        var value = viewport; value.zoom(to: value.zoom * (1 + event.magnification), around: point(event))
        model.setViewport(value); needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: drag = nil; localViewport = nil; regionHover = nil; needsDisplay = true
        case 49: spaceDown = true; NSCursor.openHand.set()
        case 36, 76:
            switch focusedItem {
            case .session(let id): model.openSession(id)
            case .project(let id): focusProject(id)
            case nil: break
            }
        case 48:
            let items = (showsProjectOverview ? projectOverviews.map { Focus.project($0.project.id) } : []) + renderedSessions.map { Focus.session($0.id) }
            guard !items.isEmpty else { return }
            let step = event.modifierFlags.contains(.shift) ? -1 : 1
            let current = items.firstIndex(where: { $0 == focusedItem }) ?? (step > 0 ? -1 : 0)
            focusedItem = items[(current + step + items.count) % items.count]
            needsDisplay = true
        default: super.keyDown(with: event)
        }
    }
    override func keyUp(with event: NSEvent) { if event.keyCode == 49 { spaceDown = false } else { super.keyUp(with: event) } }
    override func menu(for event: NSEvent) -> NSMenu? {
        contextPoint = viewport.world(point(event)); contextSession = hitNote(contextPoint)?.id
        let location = point(event)
        contextProject = showsProjectOverview ? projectOverviews.reversed().first { $0.frame.contains(NSPoint(x: location.x, y: location.y)) }?.project.id : (contextSession == nil ? model.visibleProject(at: contextPoint) : nil)
        let menu = NSMenu()
        menu.autoenablesItems = false
        if contextProject != nil {
            let create = NSMenuItem(title: "New session in project…", action: #selector(createContext), keyEquivalent: "")
            create.target = self; menu.addItem(create)
            menu.addItem(.separator())
            let zoom = NSMenuItem(title: "Zoom into project", action: #selector(zoomContextProject), keyEquivalent: "")
            zoom.target = self; menu.addItem(zoom)
            let hide = NSMenuItem(title: "Hide project", action: #selector(hideContextProject), keyEquivalent: "")
            hide.target = self; menu.addItem(hide)
        } else if let id = contextSession {
            if model.mode != .demo {
                let native = NSMenuItem(title: "Open in Codex", action: #selector(openNativeContext), keyEquivalent: ""); native.target = self; native.representedObject = id; menu.addItem(native)
            }
            if let session = model.workspace.sessions.first(where: { $0.id == id }) {
                let archive = NSMenuItem(title: session.isArchived ? "Unarchive session" : "Archive session", action: #selector(archiveContext), keyEquivalent: "")
                archive.target = self; archive.isEnabled = model.canArchive(session); menu.addItem(archive)
            }
            let move = NSMenu(title: "Move to project")
            move.autoenablesItems = false
            let canMove = model.canAssignProject && !model.pendingSessions.contains(id) && !model.isRefreshing
            for project in model.workspace.projects {
                let item = NSMenuItem(title: project.name, action: #selector(moveContext(_:)), keyEquivalent: "")
                item.representedObject = project.id; item.target = self; item.isEnabled = canMove; move.addItem(item)
            }
            let remove = NSMenuItem(title: "Remove from project", action: #selector(moveContext(_:)), keyEquivalent: "")
            remove.target = self; remove.isEnabled = canMove; move.addItem(remove)
            let parent = NSMenuItem(title: "Move to project", action: nil, keyEquivalent: ""); parent.submenu = move; menu.addItem(parent)
        } else {
            let create = NSMenuItem(title: "New session here…", action: #selector(createContext), keyEquivalent: ""); create.target = self; menu.addItem(create)
            let fit = NSMenuItem(title: "Fit to content", action: #selector(fitAction), keyEquivalent: ""); fit.target = self; menu.addItem(fit)
        }
        return menu
    }
    @objc private func moveContext(_ sender: NSMenuItem) { if let id = contextSession { model.moveToProject(id: id, projectID: sender.representedObject as? String) } }
    @objc private func openNativeContext() { if let session = model.workspace.sessions.first(where: { $0.id == contextSession }) { model.openInCodex(session) } }
    @objc private func archiveContext() { if let id = contextSession { Task { await model.toggleArchive(id) } } }
    @objc private func createContext() { model.beginCreation(at: contextPoint) }
    @objc private func fitAction() { fitContent() }
    @objc private func zoomContextProject() { if let id = contextProject { focusProject(id) } }
    @objc private func hideContextProject() { if let id = contextProject { model.setProjectVisible(id, false) } }
    private func focusProject(_ id: String) {
        guard model.visibleProjects.contains(where: { $0.id == id }) else { return }
        model.focusedProjectID = id
        model.focusRequest += 1
        update()
    }
    func fitContent() {
        let rects = model.visibleSessions.compactMap { model.workspace.placements[$0.id]?.rect } + Array(model.visibleRegions.values)
        guard let first = rects.first, bounds.width > 0, bounds.height > 0 else { return }
        let minX = rects.map(\.x).min() ?? first.x, minY = rects.map(\.y).min() ?? first.y
        let maxX = rects.map { $0.x + $0.width }.max() ?? first.x + first.width
        let maxY = rects.map { $0.y + $0.height }.max() ?? first.y + first.height
        let scale = min(1.2, min((bounds.width - 88) / max(1, maxX - minX), (bounds.height - 88) / max(1, maxY - minY)))
        model.setViewport(Viewport(origin: Point((bounds.width - (maxX - minX) * scale) / 2 - minX * scale,
                                                (bounds.height - (maxY - minY) * scale) / 2 - minY * scale), zoom: max(0.001, scale)))
        needsDisplay = true
    }
    private func rebuildAccessibility() {
        var elements: [CanvasAccessibilityElement] = []
        if showsProjectOverview {
            elements = projectOverviews.map { item in
                let element = CanvasAccessibilityElement()
                element.setAccessibilityRole(.button)
                element.setAccessibilityParent(self)
                element.setAccessibilityLabel("\(item.project.name), \(item.count) sessions, zoom into project")
                if let window { element.setAccessibilityFrame(window.convertToScreen(convert(item.frame, to: nil))) }
                element.press = { [weak self] in self?.focusProject(item.project.id) }
                return element
            }
        }
        elements += renderedSessions.compactMap { session -> CanvasAccessibilityElement? in
            guard let placement = model.workspace.placements[session.id] else { return nil }
            let element = CanvasAccessibilityElement()
            element.setAccessibilityRole(.button)
            element.setAccessibilityParent(self)
            element.setAccessibilityLabel(session.title + ", " + model.state(session).label + (model.lastKnownLabel(session).map { ", " + $0 } ?? "") + ", last activity " + model.activityLabel(session))
            if let window {
                let local = screen(placement.rect)
                element.setAccessibilityFrame(window.convertToScreen(convert(local, to: nil)))
            }
            element.press = { [weak model] in model?.openSession(session.id) }
            return element
        }
        setAccessibilityChildren(elements)
    }
}

@MainActor
final class CanvasAccessibilityElement: NSAccessibilityElement {
    var press: (() -> Void)?
    override func accessibilityPerformPress() -> Bool { press?(); return true }
}
