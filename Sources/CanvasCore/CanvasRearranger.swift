import Foundation

/// An explicit local layout command. Hidden notes remain fixed obstacles, not spare cells.
public enum CanvasRearranger {
    private static let padding = 16.0, header = 64.0, gap = 16.0, areaGap = 64.0
    private static let stepX = Placement.width + gap, stepY = Placement.height + gap
    private static let bandWidth = 3 * 760.0 + 2 * areaGap

    public static func arrange(_ workspace: Workspace, visibleSessionIDs: Set<String>, acknowledgments: [String: Set<String>] = [:]) throws -> Workspace {
        let moving = workspace.sessions.filter { visibleSessionIDs.contains($0.id) }
        guard !moving.isEmpty else { return workspace }
        guard workspace.placements.values.allSatisfy({ finite($0.rect) }), workspace.regions.values.allSatisfy({ finite($0) }) else {
            throw CanvasError.message("Canvas geometry is invalid. Refresh the workspace before rearranging.")
        }
        let ids = Set(moving.map(\.id))
        let byID = Dictionary(uniqueKeysWithValues: workspace.sessions.map { ($0.id, $0) })
        let fixed = workspace.placements.filter { !ids.contains($0.key) }
        let fixedRects = fixed.values.map(\.rect)
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
        let pinned = Set(workspace.sessions.filter { !ids.contains($0.id) }.compactMap(\.projectID))
        let free = projectIDs.subtracting(pinned)
        var next = workspace
        for id in free { next.regions.removeValue(forKey: id) }

        // Keep anchored projects' origins; try a few widths before declaring fixed geometry blocked.
        for project in workspace.projects where projectIDs.contains(project.id) && pinned.contains(project.id) {
            let original = workspace.regions[project.id]!
            let members = ordered(moving.filter { $0.projectID == project.id })
            let hidden = fixed.filter { byID[$0.key]?.projectID == project.id }.values
            let baseColumns = Int(max(1, min(3, (original.width - 2 * padding + gap) / stepX)))
            var accepted = false
            for columns in baseColumns...max(baseColumns, 6) {
                let width = max(300, 2 * padding + Double(columns) * stepX - gap,
                                hidden.map { min(original.width, $0.rect.x + $0.rect.width + padding - original.x) }.max() ?? 0)
                let placements = try grid(members, origin: Point(original.x + padding, original.y + header), columns: columns, obstacles: fixedRects)
                let bottom = max(placements.values.map { $0.rect.y + $0.rect.height + padding }.max() ?? original.y,
                                 hidden.map { min(original.y + original.height, $0.rect.y + $0.rect.height + padding) }.max() ?? original.y)
                let rect = Rect(original.x, original.y, width, max(240, bottom - original.y))
                guard !next.regions.contains(where: { $0.key != project.id && $0.value.intersects(rect) }),
                      fixed.allSatisfy({ rect.contains($0.value.center) == (byID[$0.key]?.projectID == project.id) }) else { continue }
                next.regions[project.id] = rect
                next.placements.merge(placements) { _, new in new }
                accepted = true
                break
            }
            guard accepted else {
                throw CanvasError.message("Not enough space in \(project.name) without moving hidden sessions. Show more sessions or move surrounding areas, then rearrange again.")
            }
        }

        var x = 0.0, y = 0.0, rowBottom = 0.0
        for project in workspace.projects where free.contains(project.id) {
            let members = ordered(moving.filter { $0.projectID == project.id })
            let columns = min(3, members.count)
            let local = try grid(members, origin: Point(padding, header), columns: columns, obstacles: [])
            let width = max(300, 2 * padding + Double(columns) * stepX - gap)
            let height = max(240, (local.values.map { $0.rect.y + $0.rect.height }.max() ?? header) + padding)
            let obstacles = Array(next.regions.values) + fixedRects
            while true {
                if x + width > bandWidth { x = 0; y = max(y + areaGap, rowBottom + areaGap) }
                let rect = Rect(x, y, width, height)
                guard finite(rect) else { throw CanvasError.message("No finite space is available for rearranging.") }
                let collisions = obstacles.filter { $0.intersects(rect) }
                if collisions.isEmpty {
                    next.regions[project.id] = rect
                    for (id, placement) in local { next.placements[id] = Placement(placement.position + Point(x, y)) }
                    rowBottom = max(rowBottom, y + height); x += width + areaGap
                    break
                }
                let right = collisions.map { $0.x + $0.width + areaGap }.max()!
                if right + width <= bandWidth { x = right }
                else { x = 0; y = max(y + areaGap, collisions.map { $0.y + $0.height + areaGap }.min()!) }
            }
        }
        let projectBottom = projectIDs.compactMap { next.regions[$0] }.map { $0.y + $0.height }.max()
        let unassigned = ordered(moving.filter { $0.projectID == nil })
        let placements = try grid(unassigned, origin: Point(0, projectBottom.map { $0 + areaGap } ?? 0), columns: 6,
                                  obstacles: Array(next.regions.values) + fixedRects)
        next.placements.merge(placements) { _, new in new }

        guard next.regions.allSatisfy({ next.validateRegion(id: $0.key, rect: $0.value, memberPositions: [:]) }),
              ids.allSatisfy({ id in
                  guard let placement = next.placements[id] else { return false }
                  return next.placements.allSatisfy { $0.key == id || !placement.rect.intersects($0.value.rect) }
              }) else { throw CanvasError.message("Rearrange could not preserve project boundaries and hidden sessions. Show more sessions or adjust surrounding areas, then retry.") }
        return next
    }

    private static func finite(_ rect: Rect) -> Bool {
        [rect.x, rect.y, rect.width, rect.height, rect.x + rect.width, rect.y + rect.height].allSatisfy(\.isFinite) &&
            rect.width > 0 && rect.height > 0 && rect.x + rect.width > rect.x && rect.y + rect.height > rect.y
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
                let collision = obstacles.first { $0.intersects(candidate.rect) }
                release = min(release, collision.map { $0.y + $0.height } ?? candidate.position.y + stepY)
                column += 1
                if column == columns {
                    guard let jump = Int(exactly: ceil((release - origin.y) / stepY)), row < Int.max - 1 else {
                        throw CanvasError.message("No finite space is available for rearranging.")
                    }
                    row = max(row + 1, jump); column = 0; release = .infinity
                }
                if collision == nil { result[session.id] = candidate; break }
            }
        }
        return result
    }
}
