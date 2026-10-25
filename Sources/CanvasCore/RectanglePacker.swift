import Foundation

/// Deterministic, non-rotating guillotine packing. A bounded width search keeps
/// the core O(n²) in time and O(n) in space; it does not prove an optimum.
enum RectanglePacker {
    static func prefers(_ a: Rect, over b: Rect) -> Bool {
        let longestA = max(a.width, a.height), longestB = max(b.width, b.height)
        if longestA != longestB { return longestA < longestB }
        let shortestA = min(a.width, a.height), shortestB = min(b.width, b.height)
        if shortestA != shortestB { return shortestA < shortestB }
        return a.width > b.width
    }

    static func pack(_ rectangles: [Rect], gap: Double) throws -> [Rect] {
        guard !rectangles.isEmpty else { return [] }
        let order = rectangles.indices.sorted {
            let a = rectangles[$0], b = rectangles[$1]
            if a.height != b.height { return a.height > b.height }
            if a.width != b.width { return a.width > b.width }
            return $0 < $1 // Source/sidebar order breaks equal-size ties.
        }
        let maxWidth = rectangles.map { $0.width + gap }.max()!
        let area = rectangles.reduce(0) { $0 + ($1.width + gap) * ($1.height + gap) }
        guard maxWidth.isFinite, area.isFinite, maxWidth > 0, area > 0 else {
            throw CanvasError.message("No finite space is available for rearranging.")
        }
        let ideal = sqrt(area)
        let widths = [maxWidth] + [0.65, 0.8, 1, 1.2, 1.4, 1.7, 2].map { max(maxWidth, ideal * $0) }
        var best: [Rect]?, bestBounds: Rect?
        for width in widths where width.isFinite {
            guard let candidate = pack(rectangles, order: order, width: width, gap: gap) else { continue }
            let bounds = Rect(0, 0, candidate.map { $0.x + $0.width }.max()!, candidate.map { $0.y + $0.height }.max()!)
            if bestBounds == nil || prefers(bounds, over: bestBounds!) {
                best = candidate; bestBounds = bounds
            }
        }
        guard let best else { throw CanvasError.message("No finite space is available for rearranging.") }
        return best
    }

    private static func pack(_ rectangles: [Rect], order: [Int], width: Double, gap: Double) -> [Rect]? {
        var spaces = [Rect(0, 0, width, .infinity)]
        var result = rectangles
        for index in order {
            let box = rectangles[index], w = box.width + gap, h = box.height + gap
            guard let slot = spaces.indices.reversed().first(where: { spaces[$0].width >= w && spaces[$0].height >= h }) else { return nil }
            let space = spaces[slot]
            guard (space.x + w).isFinite, (space.y + h).isFinite else { return nil }
            result[index] = Rect(space.x, space.y, box.width, box.height)
            if w == space.width && h == space.height {
                spaces.swapAt(slot, spaces.count - 1); spaces.removeLast()
            } else if h == space.height {
                spaces[slot] = Rect(space.x + w, space.y, space.width - w, space.height)
            } else if w == space.width {
                spaces[slot] = Rect(space.x, space.y + h, space.width, space.height - h)
            } else {
                spaces[slot] = Rect(space.x, space.y + h, space.width, space.height - h)
                spaces.append(Rect(space.x + w, space.y, space.width - w, h))
            }
        }
        return result
    }
}
