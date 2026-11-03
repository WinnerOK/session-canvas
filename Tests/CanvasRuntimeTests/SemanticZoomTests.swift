import AppKit
import Testing
import Vision
import CanvasCore
@testable import SessionCanvas

@Suite(.serialized) @MainActor
struct SemanticZoomTests {
    @Test(arguments: [0.24, 0.25, 0.30, 0.31, 0.32, 0.33, 0.34, 0.35, 0.42, 0.54, 0.55, 0.60, 0.85, 1.0])
    func projectMembersDisappearExactlyWhenSessionContentDoes(zoom: Double) throws {
        _ = NSApplication.shared
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        model.workspace.projects = [Project(id: "p", name: "Project")]
        model.workspace.regions = ["p": Rect(0, 0, 360, 290)]
        model.workspace.sessions = [Session(id: "member", title: "Member session", projectID: "p", execution: .idle),
                                    Session(id: "unassigned", title: "Unassigned session", execution: .idle)]
        model.workspace.placements = ["member": Placement(Point(20, 64)), "unassigned": Placement(Point(400, 64))]
        let viewport = Viewport(origin: Point(40, 40), zoom: zoom)
        model.workspace.viewport = viewport
        let canvas = CanvasNSView(model: model)
        canvas.frame = NSRect(x: 0, y: 0, width: 800, height: 450)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        canvas.update()
        let elements = try #require(canvas.accessibilityChildren() as? [NSAccessibilityElement])
        let memberIsAccessible = elements.contains { $0.accessibilityLabel()?.hasPrefix("Member session,") == true }
        let projectIsAccessible = elements.contains { $0.accessibilityLabel()?.contains("zoom into project") == true }
        let original = try pixels(canvas)
        model.workspace.sessions[1].title = "Changed unassigned title"
        canvas.update()
        let unassignedChanged = try pixels(canvas)
        let sessionContentIsVisible = unassignedChanged != original
        model.workspace.sessions[0].title = "Changed member title"
        canvas.update()
        let memberContentIsVisible = try pixels(canvas) != unassignedChanged
        #expect(memberContentIsVisible == sessionContentIsVisible,
                "Project members and unassigned notes must retain text at the same zoom: \(zoom)")
        #expect(memberIsAccessible == sessionContentIsVisible)
        #expect(projectIsAccessible != sessionContentIsVisible)
        #expect(model.workspace.viewport == viewport)
        #expect(model.workspace.placements["member"] == Placement(Point(20, 64)))
        let center = viewport.screen(Point(20 + Placement.width / 2, 64 + Placement.height / 2))
        canvas.mouseDown(with: try mouse(.leftMouseDown, at: center, in: canvas))
        canvas.mouseUp(with: try mouse(.leftMouseUp, at: center, in: canvas))
        #expect(model.selectedSessionID == (sessionContentIsVisible ? "member" : nil))
        #expect(model.focusRequest == (sessionContentIsVisible ? 0 : 1))
    }

    @Test(arguments: [0.25, 0.10, 0.03, 0.01])
    func draggingAnOverviewMovesTheProjectAndAllMembersWithoutPanning(zoom: Double) throws {
        _ = NSApplication.shared
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        model.workspace.projects = [Project(id: "p", name: "Movable project")]
        let original = Rect(0, 0, 760, 580)
        model.workspace.regions["p"] = original
        model.workspace.sessions = [Session(id: "visible", title: "Running", projectID: "p", execution: .running),
                                    Session(id: "hidden", title: "Idle", projectID: "p", execution: .idle)]
        model.workspace.placements = ["visible": Placement(Point(20, 64)), "hidden": Placement(Point(20, 244))]
        model.setStateVisible(.idle, false)
        let initialViewport = Viewport(origin: Point(40, 60), zoom: zoom)
        model.workspace.viewport = initialViewport
        let canvas = CanvasNSView(model: model)
        canvas.frame = NSRect(x: 0, y: 0, width: 1400, height: 700)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        canvas.update()
        let start = initialViewport.screen(Point(380, 290))
        let displacement = Point(60, 40)
        let end = start + displacement
        let worldDelta = Point(displacement.x / zoom, displacement.y / zoom)
        let sessions = model.workspace.sessions
        canvas.mouseDown(with: try mouse(.leftMouseDown, at: start, in: canvas))
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, at: end, in: canvas))
        canvas.update()
        // The outline, label, and accessible hit area follow the same preview while dragging.
        let element = try #require(canvas.accessibilityChildren()?.first as? NSAccessibilityElement)
        let preview = canvas.convert(window.convertFromScreen(element.accessibilityFrame()), from: nil)
        #expect(abs(preview.minX - (40 + displacement.x)) < 0.001)
        #expect(abs(preview.minY - (60 + displacement.y)) < 0.001)
        #expect(model.workspace.regions["p"] == original, "The layout commits only on release")
        canvas.mouseUp(with: try mouse(.leftMouseUp, at: end, in: canvas))
        #expect(model.workspace.viewport == initialViewport)
        let region = try #require(model.workspace.regions["p"])
        #expect(abs(region.x - worldDelta.x) < 0.000001 && abs(region.y - worldDelta.y) < 0.000001)
        #expect(region.width == original.width && region.height == original.height)
        for (id, start) in [("visible", Point(20, 64)), ("hidden", Point(20, 244))] {
            let position = try #require(model.workspace.placements[id]?.position)
            #expect(abs(position.x - start.x - worldDelta.x) < 0.000001)
            #expect(abs(position.y - start.y - worldDelta.y) < 0.000001)
        }
        #expect(model.workspace.sessions == sessions)
        #expect(model.focusRequest == 0, "Dragging must not zoom into the project")
        #expect(model.errorMessage == nil)
    }

    private func mouse(_ type: NSEvent.EventType, at point: Point, in canvas: NSView) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: canvas.convert(NSPoint(x: point.x, y: point.y), to: nil),
                                       modifierFlags: [], timestamp: 0, windowNumber: canvas.window?.windowNumber ?? 0,
                                       context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
    }

    @Test(arguments: ["click", "escape", "space", "collision"])
    func overviewProjectGesturesRetainNavigationCancellationAndCollisionRules(gesture: String) throws {
        _ = NSApplication.shared
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        model.workspace.projects = [Project(id: "p", name: "Project"), Project(id: "q", name: "Neighbor")]
        model.workspace.regions = ["p": Rect(0, 0, 760, 580), "q": Rect(1000, 0, 760, 580)]
        model.workspace.sessions = [Session(id: "p", title: "First", projectID: "p", execution: .idle), Session(id: "q", title: "Second", projectID: "q", execution: .idle)]
        model.workspace.placements = ["p": Placement(Point(20, 64)), "q": Placement(Point(1020, 64))]
        model.workspace.viewport = Viewport(origin: Point(40, 60), zoom: 0.25)
        let original = model.workspace
        let canvas = CanvasNSView(model: model)
        canvas.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        canvas.update()
        let start = original.viewport.screen(Point(380, 290))
        let end = start + (gesture == "collision" ? Point(250, 0) : Point(40, 20))
        if gesture == "space" { canvas.keyDown(with: try key(49, characters: " ")) }
        canvas.mouseDown(with: try mouse(.leftMouseDown, at: start, in: canvas))
        if gesture != "click" { canvas.mouseDragged(with: try mouse(.leftMouseDragged, at: end, in: canvas)) }
        if gesture == "escape" { canvas.keyDown(with: try key(53, characters: "\u{1b}")) }
        canvas.mouseUp(with: try mouse(.leftMouseUp, at: gesture == "click" ? start : end, in: canvas))
        #expect(model.workspace.regions == original.regions)
        #expect(model.workspace.placements == original.placements)
        #expect(model.workspace.sessions == original.sessions)
        if gesture == "click" {
            #expect(model.focusRequest == 1)
            #expect(model.workspace.viewport.zoom >= 0.75)
        } else if gesture == "space" {
            #expect(model.workspace.viewport == Viewport(origin: Point(80, 80), zoom: 0.25))
        } else {
            #expect(model.workspace.viewport == original.viewport)
            #expect(model.focusRequest == 0)
        }
        #expect((model.errorMessage != nil) == (gesture == "collision"))
    }

    private func key(_ code: UInt16, characters: String) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                     windowNumber: 0, context: nil, characters: characters,
                                     charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }

    @Test func projectAreasFollowViewportWithoutReflowOrEdgeClamping() throws {
        _ = NSApplication.shared
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        for index in 0..<3 {
            let id = "p\(index)"
            model.workspace.projects.append(Project(id: id, name: "Project \(index)"))
            model.workspace.regions[id] = Rect(Double(index) * 820, 0, 760, 580)
            model.workspace.sessions.append(Session(id: id, title: "Session", projectID: id, execution: .idle))
        }
        let canvas = CanvasNSView(model: model)
        canvas.frame = NSRect(x: 0, y: 0, width: 1400, height: 700)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        for zoom in [0.30, 0.25, 0.1, 0.03, 0.01] {
            for origin in [Point(40, 60), Point(-50, 15)] {
                model.workspace.viewport = Viewport(origin: origin, zoom: zoom)
                canvas.update()
                let elements = try #require(canvas.accessibilityChildren() as? [NSAccessibilityElement])
                for project in model.workspace.projects {
                    let region = try #require(model.workspace.regions[project.id])
                    let point = model.workspace.viewport.screen(Point(region.x, region.y))
                    let expected = NSRect(x: point.x, y: point.y, width: region.width * zoom, height: region.height * zoom)
                    guard expected.intersects(canvas.bounds) else { continue }
                    let element = try #require(elements.first { $0.accessibilityLabel()?.hasPrefix(project.name + ",") == true })
                    let actual = canvas.convert(window.convertFromScreen(element.accessibilityFrame()), from: nil)
                    #expect(abs(actual.minX - expected.minX) < 0.001)
                    #expect(abs(actual.minY - expected.minY) < 0.001)
                    #expect(abs(actual.width - expected.width) < 0.001)
                    #expect(abs(actual.height - expected.height) < 0.001)
                }
            }
        }
    }

    @Test(arguments: [Rect(0, 0, 60, 600), Rect(0, 0, 600, 40)])
    func projectsTooSmallForATruncatedNameShowOnlyTheirArea(region: Rect) throws {
        _ = NSApplication.shared
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        model.workspace.projects = [Project(id: "p", name: "Project without enough label space")]
        model.workspace.regions["p"] = region
        model.workspace.sessions = [Session(id: "s", title: "Session", projectID: "p", execution: .idle)]
        model.workspace.viewport = Viewport(origin: Point(40, 40), zoom: 0.25)
        let canvas = CanvasNSView(model: model)
        canvas.frame = NSRect(x: 0, y: 0, width: 800, height: 400)
        canvas.update()
        let original = try pixels(canvas)
        model.workspace.projects[0].name = ""
        model.workspace.sessions.append(Session(id: "extra", title: "Another session", projectID: "p", execution: .idle))
        canvas.update()
        #expect(try pixels(canvas) == original, "Names and counts must not change a text-free project area")
        let element = try #require(canvas.accessibilityChildren()?.first as? NSAccessibilityElement)
        #expect(element.accessibilityLabel()?.contains("2 sessions") == true)
    }

    @Test func overviewProjectActivationRevealsSessionsInTallRegions() throws {
        _ = NSApplication.shared
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        model.workspace.projects = [Project(id: "p", name: "Large project")]
        model.workspace.regions["p"] = Rect(0, 0, 760, 9000)
        model.workspace.sessions = [Session(id: "s", title: "Review service changes", projectID: "p", execution: .idle)]
        model.workspace.placements["s"] = Placement(Point(20, 64))
        model.workspace.viewport = Viewport(origin: Point(40, 40), zoom: 0.05)
        let canvas = CanvasNSView(model: model)
        canvas.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)
        canvas.update()
        let project = try #require(canvas.accessibilityChildren()?.first as? NSAccessibilityElement)
        #expect(project.accessibilityLabel()?.contains("Large project") == true)
        #expect(project.accessibilityPerformPress())
        #expect(model.workspace.viewport.zoom >= 0.75)
        #expect(model.selectedSessionID == nil)
        let session = try #require(canvas.accessibilityChildren()?.first as? NSAccessibilityElement)
        #expect(session.accessibilityLabel()?.contains("Review service changes") == true)
        #expect(session.accessibilityPerformPress())
        #expect(model.selectedSessionID == "s")
    }

    @Test func distantProjectsShowWhatNeedsAttention() throws {
        _ = NSApplication.shared
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        model.workspace.projects = ["Radio", "Home", "Tools"].enumerated().map { Project(id: "p\($0.offset)", name: $0.element) }
        let members: [[Session]] = [
            [Session(id: "a", title: "A", projectID: "p0", execution: .idle, requests: ["r": .input]),
             Session(id: "b", title: "B", projectID: "p0", execution: .idle, requests: ["r": .input]),
             Session(id: "c", title: "C", projectID: "p0", execution: .running)],
            [Session(id: "d", title: "D", projectID: "p1", execution: .idle, requests: ["r": .permission])],
            [Session(id: "e", title: "E", projectID: "p2", execution: .idle)],
        ]
        for (index, project) in model.workspace.projects.enumerated() {
            let x = Double(index) * 820
            model.workspace.regions[project.id] = Rect(x, 0, 760, 580)
            for (n, session) in members[index].enumerated() {
                model.workspace.sessions.append(session)
                model.workspace.placements[session.id] = Placement(Point(x + 20 + Double(n) * 240, 64))
            }
        }
        model.workspace.viewport = Viewport(origin: Point(40, 60), zoom: 0.1)
        let canvas = CanvasNSView(model: model)
        canvas.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        canvas.update()
        _ = try recognize(canvas, artifact: "attention-10")
        let labels = (canvas.accessibilityChildren() as? [NSAccessibilityElement] ?? []).compactMap { $0.accessibilityLabel() }
        #expect(labels.contains { $0.hasPrefix("Radio,") && $0.contains("2 Waiting for you") && $0.contains("1 Running") }, "\(labels)")
        #expect(labels.contains { $0.hasPrefix("Home,") && $0.contains("1 Permission required") }, "\(labels)")
        #expect(labels.contains { $0.hasPrefix("Tools,") && !$0.contains("Running") }, "\(labels)")
    }

    @Test(arguments: [0.30, 0.25, 0.10, 0.03, 0.01])
    func projectLabelsUseAvailableSpaceAtEachZoom(zoom: Double) throws {
        _ = NSApplication.shared
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        let names = ["Session Canvas", "Research", "Product catalog", "Balance", "Support", "Infrastructure", "Billing", "Payments", "Accounts", "Operations", "Analytics", "Invoices", "Contracts", "Documentation", "Engineering", "Resources", "Workflows", "Experiments"]
        model.workspace.projects = names.prefix(zoom == 0.01 ? names.count : 3).enumerated().map { Project(id: "p\($0.offset)", name: $0.element) }
        for (index, project) in model.workspace.projects.enumerated() {
            let x = Double(index) * 820
            model.workspace.regions[project.id] = Rect(x, 0, 760, 580)
            let session = Session(id: project.id + "-session", title: "Verify the implementation", projectID: project.id, execution: .idle)
            model.workspace.sessions.append(session)
            model.workspace.placements[session.id] = Placement(Point(x + 20, 64))
        }
        model.workspace.viewport = Viewport(origin: Point(40, 60), zoom: zoom)
        let canvas = CanvasNSView(model: model)
        canvas.frame = NSRect(x: 0, y: 0, width: 1400, height: 700)
        let window = NSWindow(contentRect: canvas.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = canvas
        canvas.update()
        let recognized = try recognize(canvas, artifact: "zoom-\(Int(zoom * 100))")
        if zoom <= 0.03 {
            let original = try pixels(canvas)
            for index in model.workspace.projects.indices { model.workspace.projects[index].name = "" }
            for project in model.workspace.projects {
                model.workspace.sessions.append(Session(id: project.id + "-extra", title: "Another session", projectID: project.id, execution: .idle))
            }
            canvas.update()
            #expect(try pixels(canvas) == original, "Names and counts must not change distant project areas")
            return
        }
        if zoom == 0.1 {
            #expect(!recognized.contains { $0.contains("session canvas") || $0.contains("product catalog") })
            #expect(recognized.contains { $0.contains("research") }, "A short name should still fit: \(recognized)")
            return
        }
        for project in model.workspace.projects {
            var found = recognized.contains { $0.contains(project.name.lowercased()) }
            if !found, let label = (canvas.accessibilityChildren() as? [NSAccessibilityElement])?.first(where: { $0.accessibilityLabel()?.hasPrefix(project.name + ",") == true }) {
                // OCR can skip columns in a dense map. Inspect the actual rendered label on its own.
                let local = canvas.convert(window.convertFromScreen(label.accessibilityFrame()), from: nil)
                found = try recognize(canvas, artifact: "label", crop: local).contains { $0.contains(project.name.lowercased()) }
            }
            #expect(found, "Project name missing or clipped at \(Int(zoom * 100))%: \(project.name); OCR: \(recognized)")
        }
    }

    private func pixels(_ canvas: CanvasNSView) throws -> Data {
        let bitmap = try #require(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds))
        canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        return Data(bytes: try #require(bitmap.bitmapData), count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }

    @Test(arguments: [0.6, 0.8, 1.0])
    func sessionTextUsesWholeLinesAtCloserZoom(zoom: Double) throws {
        _ = NSApplication.shared
        let model = ApplicationModel(demo: true, storagePath: ":memory:")
        model.workspace.sessions = [Session(id: "s", title: "Deploy pending changes", execution: .running, requests: ["q": .input])]
        model.workspace.placements["s"] = Placement(Point(0, 0))
        model.workspace.viewport = Viewport(origin: Point(40, 40), zoom: zoom)
        let canvas = CanvasNSView(model: model)
        canvas.frame = NSRect(x: 0, y: 0, width: 700, height: 400)
        canvas.update()
        let recognized = try recognize(canvas, artifact: "note-\(Int(zoom * 100))").joined(separator: " ")
        #expect(recognized.contains("deploy pending changes"), "Session title clipped: \(recognized)")
        #expect(recognized.contains("waiting for you"), "Session state clipped: \(recognized)")
    }

    private func recognize(_ canvas: CanvasNSView, artifact: String, crop: NSRect? = nil) throws -> [String] {
        // Keep OCR input at Retina density even on hosted runners with a 1x display.
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(canvas.bounds.width * 2)), pixelsHigh: Int(ceil(canvas.bounds.height * 2)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = canvas.bounds.size
        canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
        if crop == nil { try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/private/tmp/session-canvas-\(artifact).png")) }
        var cgImage = try #require(bitmap.cgImage)
        if let crop {
            let sx = Double(bitmap.pixelsWide) / canvas.bounds.width, sy = Double(bitmap.pixelsHigh) / canvas.bounds.height
            cgImage = try #require(cgImage.cropping(to: NSRect(x: crop.minX * sx, y: crop.minY * sy, width: crop.width * sx, height: crop.height * sy)))
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        return request.results?.compactMap { $0.topCandidates(1).first?.string.lowercased() } ?? []
    }
}
