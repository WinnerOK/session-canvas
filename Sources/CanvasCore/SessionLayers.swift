import Foundation

public enum CanvasLayer: String, CaseIterable, Codable, Sendable {
    case active, stale, inactive
    public var label: String {
        switch self { case .active: return "Active sessions"; case .stale: return "Stale sessions"; case .inactive: return "Inactive sessions" }
    }
    public var states: [NoteState] {
        switch self { case .active: return [.running, .waiting, .permission, .finished, .idle]; case .stale: return [.idle]; case .inactive: return [.archived, .unknown] }
    }
    public static func classify(_ session: Session, acknowledged: Set<String>, timeout: IdleTimeout, now: Date) -> Self {
        let state = session.state(acknowledged: acknowledged)
        if state == .archived || state == .unknown { return .inactive }
        guard state == .idle, session.unknownReason == nil, session.execution != .running, session.requests.isEmpty,
              session.latestResult.map({ acknowledged.contains($0.id) }) ?? true,
              let seconds = timeout.seconds, session.updatedAt.timeIntervalSince1970 > 0,
              now.timeIntervalSince(session.updatedAt) >= seconds else { return .active }
        return .stale
    }
}

public struct LayerFilters: Codable, Equatable, Sendable {
    public var hiddenStates: Set<NoteState> = []
    public var hiddenProjectIDs: Set<String> = []
    public init() {}
}

public struct RememberedPlacement: Codable, Equatable, Sendable {
    public var projectID: String?
    public var offset: Point
}

public struct LayerLayout: Codable, Equatable, Sendable {
    public var placements: [String: Placement] = [:]
    public var regions: [String: Rect] = [:]
    public var viewport = Viewport()
    public var remembered: [String: RememberedPlacement] = [:]
    public init() {}
}

public struct LayerState: Codable, Equatable, Sendable {
    public var version = 1
    public var selected: CanvasLayer = .active
    public var idleTimeout: IdleTimeout = .never
    public var layouts: [CanvasLayer: LayerLayout] = [:]
    public var filters: [CanvasLayer: LayerFilters] = [:]
    public var assignments: [String: CanvasLayer] = [:]
    public var homes: [String: RememberedPlacement] = [:]
    public init() {}
    enum CodingKeys: CodingKey { case version, selected, idleTimeout, layouts, filters, assignments, homes }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        guard version == 1 else { throw CanvasError.message("This canvas was saved by a newer application. Update Session Canvas before opening it.") }
        selected = try c.decode(CanvasLayer.self, forKey: .selected)
        idleTimeout = try c.decode(IdleTimeout.self, forKey: .idleTimeout)
        layouts = try c.decode([CanvasLayer: LayerLayout].self, forKey: .layouts)
        filters = try c.decode([CanvasLayer: LayerFilters].self, forKey: .filters)
        assignments = try c.decode([String: CanvasLayer].self, forKey: .assignments)
        homes = try c.decode([String: RememberedPlacement].self, forKey: .homes)
    }
}

extension Workspace {
    public var selectedLayer: CanvasLayer { layerState?.selected ?? .active }
    public var geometrySessions: [Session] {
        guard let state = layerState else { return sessions }
        return sessions.filter { state.assignments[$0.id] == state.selected }
    }
    /// A geometry-only value includes filtered current occupants, never dormant or other-layer records.
    public var geometryProjection: Workspace {
        var value = Workspace()
        value.sessions = geometrySessions; value.projects = projects
        value.placements = placements; value.regions = regions; value.viewport = viewport
        return value
    }
    public var selectedVisibility: CanvasVisibility {
        var value = CanvasVisibility(); value.hiddenStates = []
        guard let state = layerState else { return value }
        let filter = state.filters[state.selected] ?? LayerFilters()
        value.hiddenStates = filter.hiddenStates; value.hiddenProjectIDs = filter.hiddenProjectIDs
        value.idleTimeout = state.idleTimeout
        return value
    }
    public mutating func setLayerVisibility(_ visibility: CanvasVisibility) {
        guard var state = layerState else { return }
        var filter = LayerFilters()
        filter.hiddenStates = visibility.hiddenStates.intersection(state.selected.states)
        filter.hiddenProjectIDs = visibility.hiddenProjectIDs
        state.filters[state.selected] = filter; state.idleTimeout = visibility.idleTimeout
        layerState = state
    }
    public mutating func installGeometry(_ geometry: Workspace) {
        placements = geometry.placements; regions = geometry.regions; viewport = geometry.viewport
        rememberLayerLayout()
    }
    public mutating func rememberLayerLayout() {
        guard var state = layerState else { return }
        var layout = state.layouts[state.selected] ?? LayerLayout()
        layout.regions.merge(regions) { _, new in new }; layout.viewport = viewport
        for (id, placement) in placements {
            layout.placements[id] = placement
            let projectID: String?
            if let home = state.homes[id] { projectID = home.projectID }
            else { projectID = sessions.first(where: { $0.id == id })?.projectID }
            let origin = projectID.flatMap { regions[$0] }.map { Point($0.x, $0.y) } ?? Point(0, 0)
            layout.remembered[id] = RememberedPlacement(projectID: projectID, offset: placement.position - origin)
        }
        state.layouts[state.selected] = layout; layerState = state
    }
    /// Reconcile all populations together. Saved departed slots are memory, not occupied geometry.
    public mutating func reconcileLayers(acknowledgments: [String: Set<String>], now: Date,
                                         legacyVisibility: CanvasVisibility? = nil, selecting: CanvasLayer? = nil) {
        let migrating = layerState == nil
        if layerState == nil {
            var state = LayerState()
            state.idleTimeout = legacyVisibility?.idleTimeout ?? .never
            for layer in CanvasLayer.allCases {
                var layout = LayerLayout(); layout.regions = regions; layout.viewport = viewport
                var filter = LayerFilters()
                filter.hiddenStates = (legacyVisibility?.hiddenStates ?? []).intersection(layer.states)
                filter.hiddenProjectIDs = legacyVisibility?.hiddenProjectIDs ?? []
                state.filters[layer] = filter
                for session in sessions where CanvasLayer.classify(session, acknowledged: acknowledgments[session.id] ?? [], timeout: state.idleTimeout, now: now) == layer {
                    if let placement = placements[session.id] {
                        layout.placements[session.id] = placement
                        let origin = session.projectID.flatMap { regions[$0] }.map { Point($0.x, $0.y) } ?? Point(0, 0)
                        layout.remembered[session.id] = RememberedPlacement(projectID: session.projectID, offset: placement.position - origin)
                    }
                }
                state.layouts[layer] = layout
            }
            // Seed membership before the first capture; old coordinates belong to their classified layer.
            state.assignments = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, CanvasLayer.classify($0, acknowledged: acknowledgments[$0.id] ?? [], timeout: state.idleTimeout, now: now)) })
            state.homes = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, RememberedPlacement(projectID: $0.projectID, offset: Point(0, 0))) })
            layerState = state
            let ids = Set(sessions.filter { state.assignments[$0.id] == state.selected }.map(\.id))
            placements = placements.filter { ids.contains($0.key) }
            let projectIDs = Set(sessions.filter { ids.contains($0.id) }.compactMap(\.projectID))
            regions = regions.filter { projectIDs.contains($0.key) }
        }
        rememberLayerLayout()
        guard var state = layerState else { return }
        if let selecting { state.selected = selecting }
        let assignments = Dictionary(uniqueKeysWithValues: sessions.map {
            ($0.id, CanvasLayer.classify($0, acknowledged: acknowledgments[$0.id] ?? [], timeout: state.idleTimeout, now: now))
        })
        var projections: [CanvasLayer: Workspace] = [:]
        for layer in CanvasLayer.allCases {
            var layout = state.layouts[layer] ?? LayerLayout()
            var geometry = Workspace()
            geometry.sessions = sessions.filter { assignments[$0.id] == layer }.sorted { $0.id < $1.id }
            let projectIDs = Set(geometry.sessions.compactMap(\.projectID))
            geometry.projects = projects.filter { projectIDs.contains($0.id) }
            geometry.viewport = layout.viewport
            // Retain unchanged occupants first. New arrivals cannot steal their positions.
            for session in geometry.sessions where state.assignments[session.id] == layer && state.homes[session.id]?.projectID == session.projectID {
                if let placement = layout.placements[session.id] { geometry.placements[session.id] = placement }
            }
            let occupiedProjects = Set(sessions.filter { state.assignments[$0.id] == layer }.compactMap { state.homes[$0.id]?.projectID })
            let orderedProjects = geometry.projects.sorted {
                if occupiedProjects.contains($0.id) != occupiedProjects.contains($1.id) { return occupiedProjects.contains($0.id) }
                return $0.id < $1.id
            }
            for project in orderedProjects {
                if let rect = layout.regions[project.id], Self.finiteRegion(rect),
                   !geometry.regions.values.contains(where: { $0.intersects(rect) }),
                   !geometry.placements.contains(where: { entry in
                       geometry.sessions.first(where: { $0.id == entry.key })?.projectID != project.id && rect.contains(entry.value.center)
                   }) {
                    geometry.regions[project.id] = rect
                } else {
                    let right = max(geometry.regions.values.map { $0.x + $0.width }.max() ?? -100,
                                    geometry.placements.values.map { $0.rect.x + $0.rect.width }.max() ?? -100) + 100
                    geometry.regions[project.id] = Rect(right, 0, 760, 580)
                    for session in geometry.sessions where session.projectID == project.id { geometry.placements.removeValue(forKey: session.id) }
                }
            }
            for session in geometry.sessions {
                if let placement = geometry.placements[session.id], geometry.project(at: placement.center) == session.projectID,
                   Self.finiteRegion(placement.rect), !migrating || !geometry.placements.contains(where: {
                       $0.key < session.id && placement.rect.intersects($0.value.rect)
                   }) { continue }
                geometry.placements.removeValue(forKey: session.id)
                let memory = layout.remembered[session.id]
                let origin = session.projectID.flatMap { geometry.regions[$0] }.map { Point($0.x, $0.y) } ?? Point(0, 0)
                let desired = memory?.projectID == session.projectID ? memory.map { $0.offset + origin } : nil
                geometry.placements[session.id] = geometry.vacantPlacement(projectID: session.projectID, excluding: session.id, near: desired)
            }
            layout.placements = layout.placements.filter { id, _ in sessions.contains { $0.id == id } }
            layout.remembered = layout.remembered.filter { id, _ in sessions.contains { $0.id == id } }
            layout.regions = layout.regions.filter { id, _ in projects.contains { $0.id == id } }
            layout.regions.merge(geometry.regions) { _, new in new }
            for session in geometry.sessions {
                guard let placement = geometry.placements[session.id] else { continue }
                layout.placements[session.id] = placement
                let origin = session.projectID.flatMap { geometry.regions[$0] }.map { Point($0.x, $0.y) } ?? Point(0, 0)
                layout.remembered[session.id] = RememberedPlacement(projectID: session.projectID, offset: placement.position - origin)
            }
            state.layouts[layer] = layout; projections[layer] = geometry
        }
        state.assignments = assignments
        state.homes = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, RememberedPlacement(projectID: $0.projectID, offset: Point(0, 0))) })
        layerState = state
        if let current = projections[state.selected] { placements = current.placements; regions = current.regions; viewport = current.viewport }
    }
    private static func finiteRegion(_ rect: Rect) -> Bool {
        [rect.x, rect.y, rect.width, rect.height, rect.x + rect.width, rect.y + rect.height].allSatisfy(\.isFinite) && rect.width > 0 && rect.height > 0
    }
}
