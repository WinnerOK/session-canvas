import Foundation

/// Reflow visible notes; hidden members retain their offsets while their project moves.
public enum CanvasRearranger {
    private static let padding = 16.0, header = 64.0, gap = 16.0, areaGap = 64.0
    private static let stepX = Placement.width + gap, stepY = Placement.height + gap
    private struct ProjectLayout {
        var id: String
        var region: Rect
        var envelope: Rect
        var placements: [String: Placement]
    }

    public static func arrange(_ workspace: Workspace, visibleSessionIDs: Set<String>, acknowledgments: [String: Set<String>] = [:]) throws -> Workspace {
        let moving = workspace.sessions.filter { visibleSessionIDs.contains($0.id) }
        guard !moving.isEmpty else { return workspace }
        guard workspace.placements.values.allSatisfy({ finite($0.rect) }), workspace.regions.values.allSatisfy({ finite($0) }) else {
            throw CanvasError.message("Canvas geometry is invalid. Refresh the workspace before rearranging.")
        }
        let ids = Set(moving.map(\.id))
        let byID = Dictionary(uniqueKeysWithValues: workspace.sessions.map { ($0.id, $0) })
        let projectIDs = Set(moving.compactMap(\.projectID))
        guard projectIDs.isSubset(of: Set(workspace.projects.map(\.id))), projectIDs.allSatisfy({ workspace.regions[$0] != nil }) else {
            throw CanvasError.message("A session has no confirmed project area. Refresh before rearranging.")
        }
        func ordered(_ sessions: [Session]) -> [Session] {
            sessions.sorted {
                let a = NoteState.allCases.firstIndex(of: $0.state(acknowledged: acknowledgments[$0.id] ?? []))!
                let b = NoteState.allCases.firstIndex(of: $1.state(acknowledged: acknowledgments[$1.id] ?? []))!
                if a != b { return a < b }
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id < $1.id
            }
        }
        let carried = Set(workspace.sessions.filter { !ids.contains($0.id) && $0.projectID.map { projectIDs.contains($0) } == true }.map(\.id))
        let changed = ids.union(carried)
        let fixed = workspace.placements.filter { !changed.contains($0.key) }
        var next = workspace
        for id in projectIDs { next.regions.removeValue(forKey: id) }

        let obstacles = Array(next.regions.values) + fixed.values.map(\.rect)
        var projects: [ProjectLayout] = []
        for project in workspace.projects where projectIDs.contains(project.id) {
            let original = workspace.regions[project.id]!
            let originalOrigin = Point(original.x, original.y)
            let members = ordered(moving.filter { $0.projectID == project.id })
            let hidden = workspace.placements.filter { carried.contains($0.key) && byID[$0.key]?.projectID == project.id }
                .mapValues { Placement($0.position - originalOrigin) }
            let hiddenRects = hidden.values.map(\.rect)
            let columns = squareColumns(count: members.count + hidden.count, project: true)
            let local = try grid(members, origin: Point(padding, header), columns: columns, obstacles: hiddenRects)
            let contents = Array(local.values) + Array(hidden.values)
            let width = max(300, 2 * padding + Double(columns) * stepX - gap, (hiddenRects.map { $0.x + $0.width }.max() ?? 0) + padding)
            let height = max(240, (contents.map { $0.rect.y + $0.rect.height }.max() ?? header) + padding)
            // Reserve protruding hidden footprints as well as the area itself.
            let left = min(0, hiddenRects.map(\.x).min() ?? 0), top = min(0, hiddenRects.map(\.y).min() ?? 0)
            projects.append(ProjectLayout(id: project.id, region: Rect(-left, -top, width, height),
                                          envelope: Rect(0, 0, width - left, height - top),
                                          placements: local.merging(hidden, uniquingKeysWith: { first, _ in first })))
        }
        let packed = try RectanglePacker.pack(projects.map(\.envelope), gap: areaGap)
        let projectBounds = bounds(packed)
        let projectOffset = try vacantOffset(projectBounds, obstacles: obstacles)
        for (project, envelope) in zip(projects, packed) {
            let offset = Point(envelope.x, envelope.y) + projectOffset
            let region = project.region.translated(offset)
            next.regions[project.id] = region
            for (id, placement) in project.placements {
                next.placements[id] = Placement(placement.position + Point(region.x, region.y))
            }
        }
        let projectBottom = projectIDs.compactMap { next.regions[$0] }.map { $0.y + $0.height }.max()
        let unassigned = ordered(moving.filter { $0.projectID == nil })
        let placements = try grid(unassigned, origin: Point(0, 0), columns: squareColumns(count: unassigned.count), obstacles: [])
        let unassignedBounds = bounds(placements.values.map(\.rect))
        let offset = try vacantOffset(unassignedBounds, startY: projectBottom.map { $0 + areaGap } ?? 0,
                                      obstacles: obstacles + packed.map { $0.translated(projectOffset) })
        next.placements.merge(placements.mapValues { Placement($0.position + offset) }) { _, new in new }

        guard next.regions.allSatisfy({ next.validateRegion(id: $0.key, rect: $0.value, memberPositions: [:]) }),
              changed.allSatisfy({ id in
                  guard let placement = next.placements[id] else { return false }
                  return next.placements.allSatisfy {
                      $0.key == id || (!ids.contains(id) && !ids.contains($0.key) && byID[id]?.projectID == byID[$0.key]?.projectID) || !placement.rect.intersects($0.value.rect)
                  }
              }) else { throw CanvasError.message("Rearrange could not preserve project boundaries and hidden sessions. Show more sessions or adjust surrounding areas, then retry.") }
        return next
    }

    private static func finite(_ rect: Rect) -> Bool {
        [rect.x, rect.y, rect.width, rect.height, rect.x + rect.width, rect.y + rect.height].allSatisfy(\.isFinite) &&
            rect.width > 0 && rect.height > 0 && rect.x + rect.width > rect.x && rect.y + rect.height > rect.y
    }

    /// Minimize the enclosing square's side, then unused rectangular area.
    /// Account for actual card proportions, gaps, and the project's header/minimum size.
    private static func squareColumns(count: Int, project: Bool = false) -> Int {
        guard count > 0 else { return 1 }
        return (1...count).min { a, b in
            func size(_ columns: Int) -> Rect {
                let rows = 1 + (count - 1) / columns
                return Rect(0, 0, max(project ? 300 : 0, Double(columns) * stepX - gap + (project ? 2 * padding : 0)),
                            max(project ? 240 : 0, Double(rows) * stepY - gap + (project ? header + padding : 0)))
            }
            return RectanglePacker.prefers(size(a), over: size(b))
        }!
    }

    private static func bounds(_ rects: [Rect]) -> Rect? {
        guard !rects.isEmpty else { return nil }
        return Rect(0, 0, rects.map { $0.x + $0.width }.max()!, rects.map { $0.y + $0.height }.max()!)
    }

    /// Translate a whole compact group past fixed geometry, keeping its internal shape.
    /// Each jump clears an obstacle's bottom; work does not depend on world distance.
    private static func vacantOffset(_ bounds: Rect?, startY: Double = 0, obstacles: [Rect]) throws -> Point {
        guard let bounds else { return Point(0, startY) }
        var offset = Point(0, startY)
        while true {
            let candidate = bounds.translated(offset)
            guard finite(candidate) else { throw CanvasError.message("No finite space is available for rearranging.") }
            let collisions = obstacles.filter { $0.intersects(candidate) }
            guard !collisions.isEmpty else { return offset }
            let bottom = collisions.map { $0.y + $0.height + areaGap }.max()!
            guard bottom > offset.y else { throw CanvasError.message("No finite space is available for rearranging.") }
            offset.y = bottom
        }
    }
    private static func grid(_ sessions: [Session], origin: Point, columns: Int, obstacles: [Rect]) throws -> [String: Placement] {
        guard !sessions.isEmpty else { return [:] }
        var result: [String: Placement] = [:]
        var row = 0, column = 0
        var release = Double.infinity
        for session in sessions {
            while true {
                let candidate = Placement(Point(origin.x + Double(column) * stepX, origin.y + Double(row) * stepY))
                guard finite(candidate.rect) else { throw CanvasError.message("No finite space is available for rearranging.") }
                let blockedUntil = obstacles.filter { $0.intersects(candidate.rect) }.map { $0.y + $0.height }.min()
                release = min(release, blockedUntil ?? candidate.position.y + stepY)
                column += 1
                if column == columns {
                    guard let jump = Int(exactly: ceil((release - origin.y) / stepY)), row < Int.max - 1 else {
                        throw CanvasError.message("No finite space is available for rearranging.")
                    }
                    row = max(row + 1, jump); column = 0; release = .infinity
                }
                if blockedUntil == nil { result[session.id] = candidate; break }
            }
        }
        return result
    }
}
