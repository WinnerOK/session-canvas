import Foundation

/// Reflow visible notes; hidden members retain their offsets while their project moves.
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

        var obstacles = Array(next.regions.values) + fixed.values.map(\.rect)
        var x = 0.0, y = 0.0, rowBottom = 0.0
        for project in workspace.projects where projectIDs.contains(project.id) {
            let original = workspace.regions[project.id]!
            let originalOrigin = Point(original.x, original.y)
            let members = ordered(moving.filter { $0.projectID == project.id })
            let hidden = workspace.placements.filter { carried.contains($0.key) && byID[$0.key]?.projectID == project.id }
                .mapValues { Placement($0.position - originalOrigin) }
            let hiddenRects = hidden.values.map(\.rect)
            let columns = min(3, members.count + hidden.count)
            let local = try grid(members, origin: Point(padding, header), columns: columns, obstacles: hiddenRects)
            let contents = Array(local.values) + Array(hidden.values)
            let width = max(300, 2 * padding + Double(columns) * stepX - gap, (hiddenRects.map { $0.x + $0.width }.max() ?? 0) + padding)
            let height = max(240, (contents.map { $0.rect.y + $0.rect.height }.max() ?? header) + padding)
            // Reserve protruding hidden footprints as well as the area itself.
            let left = min(0, hiddenRects.map(\.x).min() ?? 0), top = min(0, hiddenRects.map(\.y).min() ?? 0)
            let envelopeWidth = width - left, envelopeHeight = height - top
            while true {
                if x + envelopeWidth > bandWidth { x = 0; y = max(y + areaGap, rowBottom + areaGap) }
                let envelope = Rect(x, y, envelopeWidth, envelopeHeight)
                guard finite(envelope) else { throw CanvasError.message("No finite space is available for rearranging.") }
                let collisions = obstacles.filter { $0.intersects(envelope) }
                if collisions.isEmpty {
                    let origin = Point(x - left, y - top)
                    next.regions[project.id] = Rect(origin.x, origin.y, width, height)
                    for (id, placement) in local.merging(hidden, uniquingKeysWith: { first, _ in first }) {
                        next.placements[id] = Placement(placement.position + origin)
                    }
                    obstacles.append(envelope)
                    rowBottom = max(rowBottom, y + envelopeHeight); x += envelopeWidth + areaGap
                    break
                }
                let right = collisions.map { $0.x + $0.width + areaGap }.max()!
                if right + envelopeWidth <= bandWidth { x = right }
                else { x = 0; y = max(y + areaGap, collisions.map { $0.y + $0.height + areaGap }.min()!) }
            }
        }
        let projectBottom = projectIDs.compactMap { next.regions[$0] }.map { $0.y + $0.height }.max()
        let unassigned = ordered(moving.filter { $0.projectID == nil })
        let placements = try grid(unassigned, origin: Point(0, projectBottom.map { $0 + areaGap } ?? 0), columns: 6,
                                  obstacles: obstacles)
        next.placements.merge(placements) { _, new in new }

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
