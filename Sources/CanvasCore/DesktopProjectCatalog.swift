import Foundation

/// Read-only compatibility with the local desktop's saved projects. Never derives membership from cwd.
public struct DesktopProjectCatalog: Sendable {
    public var projects: [Project]
    private var assignments: [String: String]
    private var excludedSessions: Set<String>
    private var nonlocalSessions: Set<String>
    private var serverIDs: [String: String]
    private var roots: [String: [String]]

    public func projectID(for sessionID: String, serverProjectID: String? = nil, authoritativeServer: Bool = false) -> String? {
        // New metadata APIs own membership, including explicit null. Legacy projectless
        // entries can lag behind a confirmed API move; remote identities stay excluded.
        if authoritativeServer {
            guard !nonlocalSessions.contains(sessionID) else { return nil }
            return serverIDs.first { $0.value == serverProjectID }?.key
        }
        guard !excludedSessions.contains(sessionID) else { return nil }
        return assignments[sessionID] ?? serverIDs.first { $0.value == serverProjectID }?.key
    }
    public func serverProjectID(for projectID: String) -> String? { serverIDs[projectID] }
    public func allowsLocalMembership(for sessionID: String) -> Bool { !nonlocalSessions.contains(sessionID) }
    public func rootPaths(for projectID: String) -> [String] { roots[projectID] ?? [] }

    public init(data: Data, codexHome: String? = nil) throws {
        let state = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .object(let entries) = state["local-projects"] else {
            throw CanvasError.message("The saved Codex project format is unsupported. Existing canvas data was retained.")
        }
        let order = state["project-order"].array.compactMap(\.string)
        var projects: [Project] = []
        roots = [:]
        for (id, value) in entries {
            guard value["id"].string == id, let name = value["name"].string else {
                throw CanvasError.message("A saved Codex project has an unsupported format. Existing canvas data was retained.")
            }
            projects.append(Project(id: id, name: name))
            roots[id] = value["rootPaths"].array.compactMap(\.string).filter { $0.hasPrefix("/") }
        }
        self.projects = projects.sorted {
            let a = order.firstIndex(of: $0.id) ?? Int.max, b = order.firstIndex(of: $1.id) ?? Int.max
            if a != b { return a < b }
            if $0.name != $1.name { return $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return $0.id < $1.id
        }
        let known = Set(projects.map(\.id))
        let projectless = Set(state["projectless-thread-ids"].array.compactMap(\.string))
        let hosts = state["thread-project-membership-host-ids"]
        nonlocalSessions = Set(hosts.object.compactMap { id, value in
            value.string != nil && value.string != "local" ? id : nil
        })
        for (id, value) in state["thread-project-assignments"].object {
            if value["projectKind"].string != "local" || !known.contains(value["projectId"].string ?? "") {
                nonlocalSessions.insert(id)
            }
        }
        excludedSessions = projectless.union(nonlocalSessions)
        serverIDs = [:]
        if let codexHome {
            for (id, value) in state["app-server-project-id-by-legacy-project-id-by-host"]["local:" + codexHome].object {
                if known.contains(id), let serverID = value.string, !serverID.isEmpty { serverIDs[id] = serverID }
            }
        }
        assignments = [:]
        for (id, value) in state["thread-project-assignments"].object {
            guard !projectless.contains(id), value["projectKind"].string == "local",
                  hosts[id].string == nil || hosts[id].string == "local",
                  let projectID = value["projectId"].string, known.contains(projectID) else { continue }
            assignments[id] = projectID
        }
    }

    public static func read(codexHome: String) throws -> Self? {
        let file = URL(fileURLWithPath: codexHome).appendingPathComponent(".codex-global-state.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 16 * 1024 * 1024 else { throw CanvasError.message("Saved Codex project metadata exceeds the supported size.") }
        return try Self(data: Data(contentsOf: file), codexHome: codexHome)
    }
}
