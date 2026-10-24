import Foundation

public struct Point: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public static func +(a: Self, b: Self) -> Self { Self(a.x + b.x, a.y + b.y) }
    public static func -(a: Self, b: Self) -> Self { Self(a.x - b.x, a.y - b.y) }
}

public struct Rect: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(_ x: Double, _ y: Double, _ width: Double, _ height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public func contains(_ p: Point) -> Bool {
        p.x > x && p.x < x + width && p.y > y && p.y < y + height
    }
    public func intersects(_ other: Rect) -> Bool {
        x < other.x + other.width && x + width > other.x && y < other.y + other.height && y + height > other.y
    }
    public func translated(_ delta: Point) -> Rect { Rect(x + delta.x, y + delta.y, width, height) }
}

public struct Viewport: Codable, Equatable, Sendable {
    public var origin: Point = Point(80, 80)
    public var zoom: Double = 1
    public init(origin: Point = Point(80, 80), zoom: Double = 1) { self.origin = origin; self.zoom = zoom }
    public func world(_ screen: Point) -> Point { Point((screen.x - origin.x) / zoom, (screen.y - origin.y) / zoom) }
    public func screen(_ world: Point) -> Point { Point(world.x * zoom + origin.x, world.y * zoom + origin.y) }
    public mutating func zoom(to value: Double, around screenPoint: Point) {
        let anchor = world(screenPoint)
        zoom = min(2.5, max(0.01, value))
        origin = Point(screenPoint.x - anchor.x * zoom, screenPoint.y - anchor.y * zoom)
    }
}

public enum Execution: String, Codable, Sendable { case unknown, idle, running }
public enum UnknownReason: String, Codable, Sendable {
    case historyMissing, incompleteHistory
    public var label: String {
        switch self {
        case .historyMissing: return "Saved history is not available on this Mac"
        case .incompleteHistory: return "Saved history does not establish the current state"
        }
    }
}
public enum RequestKind: String, Codable, Sendable { case input, permission }
public enum Outcome: String, Codable, Sendable {
    case completed, failed, stopped
    public var label: String { rawValue.capitalized }
}
public enum NoteState: String, CaseIterable, Codable, Sendable {
    case running, waiting, permission, finished, idle, archived, unknown
    public var label: String {
        switch self {
        case .running: return "Running"
        case .waiting: return "Waiting for you"
        case .permission: return "Permission required"
        case .finished: return "Finished"
        case .idle: return "Idle"
        case .archived: return "Archived"
        case .unknown: return "Unknown"
        }
    }
    public var symbol: String {
        switch self {
        case .running: return "waveform"
        case .waiting: return "bubble.left.and.bubble.right"
        case .permission: return "hand.raised"
        case .finished: return "checkmark.circle"
        case .idle: return "moon"
        case .archived: return "archivebox"
        case .unknown: return "questionmark.circle"
        }
    }
}

public struct CanvasVisibility: Codable, Equatable, Sendable {
    public var hiddenStates: Set<NoteState> = [.archived]
    public var hiddenProjectIDs: Set<String> = []
    public var idleTimeout: IdleTimeout = .never
    public var hideUnknown = true
    public init() {}
    public var isFiltered: Bool { !hiddenStates.isEmpty || !hiddenProjectIDs.isEmpty || idleTimeout != .never }
    enum CodingKeys: String, CodingKey { case hiddenStates, hiddenProjectIDs, hideArchived, idleTimeout, hideUnknown }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hiddenStates = try c.decodeIfPresent(Set<NoteState>.self, forKey: .hiddenStates) ?? [.archived]
        hiddenProjectIDs = try c.decodeIfPresent(Set<String>.self, forKey: .hiddenProjectIDs) ?? []
        let hidden = try c.decodeIfPresent(Bool.self, forKey: .hideArchived) ?? true
        if hidden { hiddenStates.insert(.archived) } else { hiddenStates.remove(.archived) }
        idleTimeout = try c.decodeIfPresent(IdleTimeout.self, forKey: .idleTimeout) ?? .never
        hideUnknown = try c.decodeIfPresent(Bool.self, forKey: .hideUnknown) ?? true
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        // Keep the old payload readable; the in-memory setting has one owner, hiddenStates.
        try c.encode(hiddenStates.subtracting([.archived]), forKey: .hiddenStates)
        try c.encode(hiddenStates.contains(.archived), forKey: .hideArchived)
        try c.encode(hiddenProjectIDs, forKey: .hiddenProjectIDs)
        try c.encode(idleTimeout, forKey: .idleTimeout)
        try c.encode(hideUnknown, forKey: .hideUnknown)
    }
    public func includesLifecycle(_ session: Session, acknowledged: Set<String>, now: Date) -> Bool {
        guard session.execution != .running, session.requests.isEmpty else { return true }
        if let result = session.latestResult, !acknowledged.contains(result.id) { return true }
        let state = session.state(acknowledged: acknowledged)
        let eligible = (state == .idle && session.unknownReason == nil) || (state == .unknown && hideUnknown)
        guard eligible else { return true }
        guard let seconds = idleTimeout.seconds, session.updatedAt.timeIntervalSince1970 > 0 else { return true }
        return now.timeIntervalSince(session.updatedAt) < seconds
    }
}

public enum IdleTimeout: String, CaseIterable, Codable, Sendable {
    case never, fifteenMinutes, oneHour, oneDay, oneWeek, oneMonth
    public var seconds: TimeInterval? {
        switch self {
        case .never: return nil
        case .fifteenMinutes: return 900
        case .oneHour: return 3600
        case .oneDay: return 86400
        case .oneWeek: return 604800
        case .oneMonth: return 2592000
        }
    }
    public var label: String {
        switch self {
        case .never: return "Never"
        case .fifteenMinutes: return "15 minutes"
        case .oneHour: return "1 hour"
        case .oneDay: return "1 day"
        case .oneWeek: return "1 week"
        case .oneMonth: return "1 month"
        }
    }
}

public enum ActivityTime {
    public static func label(_ date: Date, now: Date = Date()) -> String {
        guard date.timeIntervalSince1970 > 0 else { return "Activity unavailable" }
        let age = max(0, now.timeIntervalSince(date))
        if age >= 2592000 { return "1 month ago" }
        if age >= 86400 { return "\(Int(age / 86400))d ago" }
        if age >= 3600 { return "\(Int(age / 3600))h ago" }
        return "\(Int(age / 60))m ago"
    }
}

public struct SessionResult: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var outcome: Outcome
    public var text: String
    public init(id: String, outcome: Outcome, text: String) { self.id = id; self.outcome = outcome; self.text = text }
}

public struct Session: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var projectID: String?
    public var cwd: String
    public var execution: Execution
    public var requests: [String: RequestKind]
    public var latestResult: SessionResult?
    public var updatedAt: Date
    public var revision: String
    // Optional storage fields preserve decoding of existing workspace snapshots.
    public var archived: Bool?
    public var savedState: Bool?
    public var unknownReason: UnknownReason?
    public var isArchived: Bool { archived == true }
    public var stateIsFromHistory: Bool { savedState == true }
    public init(id: String, title: String, projectID: String? = nil, cwd: String = "", execution: Execution = .unknown,
                requests: [String: RequestKind] = [:], latestResult: SessionResult? = nil, updatedAt: Date = Date(), revision: String = "0", isArchived: Bool = false) {
        self.id = id; self.title = title.isEmpty ? "Untitled session" : title
        self.projectID = projectID; self.cwd = cwd; self.execution = execution; self.requests = requests
        self.latestResult = latestResult; self.updatedAt = updatedAt; self.revision = revision
        self.archived = isArchived; self.savedState = false
    }
    public func state(acknowledged: Set<String>) -> NoteState {
        if isArchived { return .archived }
        guard execution != .unknown else { return .unknown }
        if requests.values.contains(.permission) { return .permission }
        if requests.values.contains(.input) { return .waiting }
        if execution == .running { return .running }
        if let result = latestResult, !acknowledged.contains(result.id) { return .finished }
        return .idle
    }
}

public struct Project: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct Placement: Codable, Equatable, Sendable {
    public static let width: Double = 232
    public static let height: Double = 150
    public var position: Point
    public init(_ position: Point) { self.position = position }
    public var center: Point { Point(position.x + Self.width / 2, position.y + Self.height / 2) }
    public var rect: Rect { Rect(position.x, position.y, Self.width, Self.height) }
}

public struct Workspace: Codable, Equatable, Sendable {
    public var placements: [String: Placement] = [:]
    public var regions: [String: Rect] = [:]
    public var viewport = Viewport()
    public var sessions: [Session] = []
    public var projects: [Project] = []
    public init() {}
    public func project(at point: Point) -> String? {
        regions.keys.sorted().first { regions[$0]?.contains(point) == true }
    }
    public mutating func reconcile(sessions incoming: [Session], projects: [Project]) {
        self.projects = projects
        let old = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        sessions = incoming
        for (index, project) in projects.enumerated() where regions[project.id] == nil {
            // New regions are placed beyond all existing content, including unassigned notes.
            let right = max(regions.values.map { $0.x + $0.width }.max() ?? -100,
                            placements.values.map { $0.position.x + Placement.width }.max() ?? -100)
            regions[project.id] = Rect(max(Double(index) * 820, right + 100), 0, 760, 580)
        }
        for session in incoming {
            if placements[session.id] == nil || old[session.id]?.projectID != session.projectID {
                placements[session.id] = vacantPlacement(projectID: session.projectID, excluding: session.id)
            }
        }
    }
    public mutating func vacantPlacement(projectID: String?, excluding: String? = nil, near point: Point? = nil) -> Placement {
        let occupied = placements.filter { $0.key != excluding }.map(\.value.rect)
        if let point, let placement = nearestPlacement(to: point, projectID: projectID, occupied: occupied) {
            return placement
        }
        if let id = projectID, var region = regions[id] {
            for index in 0..<300 {
                let column = index % 3, row = index / 3
                let candidate = Placement(Point(region.x + 20 + Double(column) * 250, region.y + 64 + Double(row) * 172))
                if !occupied.contains(where: { candidate.rect.intersects($0) }) {
                    let desiredHeight = max(region.height, candidate.position.y + Placement.height + 24 - region.y)
                    let expanded = Rect(region.x, region.y, region.width, desiredHeight)
                    if !regions.contains(where: { $0.key != id && $0.value.intersects(expanded) }) &&
                        !placements.contains(where: { entry in
                            entry.key != excluding && sessions.first(where: { $0.id == entry.key })?.projectID != id && expanded.contains(entry.value.center)
                        }) {
                        region = expanded; regions[id] = region
                        return candidate
                    }
                }
            }
            // If surrounding geometry blocks growth, translate this entire region into free space.
            // This preserves its members' relative positions and never changes their membership.
            let right = max(regions.values.map { $0.x + $0.width }.max() ?? 0,
                            placements.values.map { $0.position.x + Placement.width }.max() ?? 0) + 100
            let delta = Point(right - region.x, -region.y)
            regions[id] = Rect(right, 0, max(760, region.width), region.height + 200)
            for session in sessions where session.projectID == id && session.id != excluding {
                if let placement = placements[session.id] { placements[session.id] = Placement(placement.position + delta) }
            }
            return vacantPlacement(projectID: id, excluding: excluding)
        }
        let left = regions.isEmpty ? 0 : (regions.values.map(\.x).min() ?? 0) - 1400
        for index in 0..<100000 {
            let candidate = Placement(Point(left + Double(index % 5) * 254, Double(index / 5) * 174))
            if !occupied.contains(where: { candidate.rect.intersects($0) }) && project(at: candidate.center) == nil { return candidate }
        }
        return Placement(Point(left, 10000000))
    }
    private func nearestPlacement(to point: Point, projectID: String?, occupied: [Rect]) -> Placement? {
        if let projectID, regions[projectID] == nil { return nil }
        func valid(_ placement: Placement) -> Bool {
            project(at: placement.center) == projectID && !occupied.contains { placement.rect.intersects($0) }
        }
        let requested = Placement(point)
        if valid(requested) { return requested }

        // A closest non-overlapping rectangle aligns with the requested coordinate or
        // an obstacle edge on each axis. Search these boundaries instead of the origin grid.
        var xs: Set<Double> = [point.x], ys: Set<Double> = [point.y]
        for rect in occupied {
            xs.formUnion([rect.x - Placement.width, rect.x + rect.width])
            ys.formUnion([rect.y - Placement.height, rect.y + rect.height])
        }
        for (id, rect) in regions {
            let inset = id == projectID ? 1.0 : 0.0
            xs.formUnion([rect.x - Placement.width / 2 + inset, rect.x + rect.width - Placement.width / 2 - inset])
            ys.formUnion([rect.y - Placement.height / 2 + inset, rect.y + rect.height - Placement.height / 2 - inset])
        }
        let orderedX = xs.sorted { abs($0 - point.x) == abs($1 - point.x) ? $0 < $1 : abs($0 - point.x) < abs($1 - point.x) }
        let orderedY = ys.sorted { abs($0 - point.y) == abs($1 - point.y) ? $0 < $1 : abs($0 - point.y) < abs($1 - point.y) }
        var best: Placement?, distance = Double.infinity
        for x in orderedX {
            let dx = x - point.x
            if dx * dx > distance { break }
            for y in orderedY {
                let dy = y - point.y, squaredDistance = dx * dx + dy * dy
                if squaredDistance >= distance { break }
                let candidate = Placement(Point(x, y))
                if valid(candidate) {
                    best = candidate; distance = squaredDistance
                    break
                }
            }
        }
        return best
    }
    public func validateRegion(id: String, rect: Rect, memberPositions: [String: Placement]) -> Bool {
        guard rect.width >= 300, rect.height >= 240 else { return false }
        if regions.contains(where: { $0.key != id && $0.value.intersects(rect) }) { return false }
        for session in sessions {
            guard let placement = memberPositions[session.id] ?? placements[session.id] else { continue }
            if rect.contains(placement.center) != (session.projectID == id) { return false }
        }
        return true
    }
}

public struct HistoryEntry: Identifiable, Equatable, Sendable {
    public var id: String
    public var role: String
    public var text: String
    public var result: SessionResult?
    public init(id: String, role: String, text: String, result: SessionResult? = nil) {
        self.id = id; self.role = role; self.text = text; self.result = result
    }
}
public struct HistoryPage: Sendable {
    public var entries: [HistoryEntry]
    public var nextCursor: String?
    public init(entries: [HistoryEntry], nextCursor: String? = nil) { self.entries = entries; self.nextCursor = nextCursor }
}

public enum CanvasError: LocalizedError {
    case message(String)
    public var errorDescription: String? { switch self { case .message(let text): return text } }
}
