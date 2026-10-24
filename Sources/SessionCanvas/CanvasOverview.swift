import AppKit
import CanvasCore

struct ProjectOverview {
    var project: Project
    var region: NSRect
    var frame: NSRect { region }
    var count: Int
    var state: NoteState
}

enum CanvasOverview {
    static let zoomThreshold = 0.55

    /// Text adapts to the projected region; it never moves or enlarges the project.
    static func titleFrame(for name: String, in region: NSRect, font: NSFont) -> NSRect? {
        let inset: CGFloat = 8
        let width = region.width - inset * 2
        let height = ceil(font.ascender - font.descender + font.leading) + 2
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let abbreviated = name.count > 3 ? String(name.prefix(3)) + "…" : name
        let minimumWidth = min((name as NSString).size(withAttributes: attributes).width,
                               (abbreviated as NSString).size(withAttributes: attributes).width)
        guard width >= ceil(minimumWidth), region.height >= height + inset * 2 else { return nil }
        return NSRect(x: region.minX + inset, y: region.minY + inset, width: width, height: height)
    }
}
