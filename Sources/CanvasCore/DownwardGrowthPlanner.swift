import Foundation

/// Plan one anchored arrival. Projects are rigid blocks, including protruding cards.
enum DownwardGrowthPlanner {
    private static let gap = 24.0
    private struct Block {
        var key: String
        var projectID: String?
        var members: [String]
        var footprint: [Rect]
        var top: Double { footprint.map(\.y).min()! }
    }
    private struct Reserved {
        var footprint: [Rect]
        var affected: Bool
    }

    static func place(_ arrival: Placement, in expanded: Rect, projectID: String,
                      workspace: Workspace, excluding: String?) -> Workspace {
        let owners = Dictionary(uniqueKeysWithValues: workspace.geometrySessions.compactMap { session in
            session.projectID.map { (session.id, $0) }
        })
        let placements = workspace.placements.filter { $0.key != excluding }
        let members = Dictionary(grouping: placements.keys.filter { owners[$0] != nil }, by: { owners[$0]! })
        var blocks: [Block] = []
        for (id, rect) in workspace.regions where id != projectID {
            let ids = (members[id] ?? []).sorted()
            blocks.append(Block(key: "project/" + id, projectID: id, members: ids,
                                footprint: [rect] + ids.compactMap { placements[$0]?.rect }))
        }
        for (id, placement) in placements where owners[id].flatMap({ workspace.regions[$0] }) == nil {
            blocks.append(Block(key: "session/" + id, members: [id], footprint: [placement.rect]))
        }
        blocks.sort { $0.top == $1.top ? $0.key < $1.key : $0.top < $1.top }

        var next = workspace
        next.regions[projectID] = expanded
        var reserved = [Reserved(footprint: [expanded, arrival.rect] + (members[projectID] ?? []).compactMap { placements[$0]?.rect }, affected: true)]
        for block in blocks {
            // Existing unrelated overlaps do not make a new arrival rearrange the canvas.
            guard reserved.contains(where: { $0.affected && intersects(block.footprint, $0.footprint) }) else {
                reserved.append(Reserved(footprint: block.footprint, affected: false))
                continue
            }
            var displacement = 0.0
            let obstacles = reserved.flatMap(\.footprint)
            while true {
                var required = displacement
                for rect in block.footprint {
                    let moved = rect.translated(Point(0, displacement))
                    for fixed in obstacles where moved.intersects(fixed) {
                        required = max(required, fixed.y + fixed.height + gap - rect.y)
                    }
                }
                guard required > displacement else { break }
                displacement = required
            }
            let delta = Point(0, displacement)
            if let id = block.projectID { next.regions[id] = workspace.regions[id]!.translated(delta) }
            for id in block.members { next.placements[id] = Placement(placements[id]!.position + delta) }
            reserved.append(Reserved(footprint: block.footprint.map { $0.translated(delta) }, affected: true))
        }
        return next
    }

    private static func intersects(_ a: [Rect], _ b: [Rect]) -> Bool {
        a.contains { rect in b.contains { rect.intersects($0) } }
    }
}
