import Foundation
import Darwin
import CanvasCore

/// A read-only follower of the desktop's existing runtime. Never claims thread ownership,
/// resumes a thread, executes tools, or answers an approval/input request.
@MainActor
final class DesktopRuntime {
    private(set) var connected = false
    var onChange: (() -> Void)?
    private var handle: FileHandle?
    private var buffer = Data()
    private var clientID: String?
    private var path = ""
    private var retryTask: Task<Void, Never>?
    private var handshakeTask: Task<Void, Never>?
    private var wanted: Set<String> = []
    private var states: [String: DesktopObservation] = [:]
    private var records: [String: (owner: String, revision: Double, state: JSONValue)] = [:]
    private var refollowedOwners: [String: Set<String>] = [:]
    private let writer = DispatchQueue(label: "session-canvas.desktop-writer")
    private var pendingFollowing: [String: Bool] = [:]
    private var followTask: Task<Void, Never>?
    private var followGeneration = UUID()

    func start(codexHome: String) {
        stop()
        path = URL(fileURLWithPath: codexHome).appendingPathComponent("ipc/ipc.sock").path
        attemptConnection()
        retryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                if self.handle == nil { self.attemptConnection() }
            }
        }
    }

    func observe(_ ids: Set<String>) {
        let added = ids.subtracting(wanted)
        let removed = wanted.subtracting(ids)
        wanted = ids
        for id in removed { follow(id, false); states.removeValue(forKey: id); records.removeValue(forKey: id); refollowedOwners.removeValue(forKey: id) }
        for id in added { follow(id, true) }
    }

    func requestSnapshots() {
        for id in wanted { follow(id, true) }
    }

    func applying(to session: Session) -> Session {
        guard let state = states[session.id] else { return session }
        var result = session
        result.execution = state.execution; result.requests = state.requests
        result.activeTurnID = state.activeTurnID
        result.savedState = false
        if let latest = state.result { result.latestResult = latest }
        if state.result != nil { result.unknownReason = nil }
        return result
    }

    private func attemptConnection() {
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFSOCK, info.st_uid == getuid() else { return }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes.map { UInt8(bitPattern: $0) }) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        let status = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        var uid: uid_t = 0, gid: gid_t = 0
        guard status == 0, getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { Darwin.close(fd); return }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        handle = file
        file.readabilityHandler = { [weak self] file in
            // Foundation's read(upToCount:) can wait for the requested count on a socket.
            // One POSIX read consumes the currently available bytes, including short frames.
            var bytes = [UInt8](repeating: 0, count: 64 * 1024)
            let count = Darwin.read(file.fileDescriptor, &bytes, bytes.count)
            let data = count > 0 ? Data(bytes.prefix(count)) : Data()
            Task { @MainActor in
                guard let self, self.handle === file else { return }
                if data.isEmpty { self.disconnected() } else { self.receive(data) }
            }
        }
        send(.object(["type": .string("request"), "method": .string("initialize"), "requestId": .string(UUID().uuidString),
                      "sourceClientId": .string("initializing-client"), "version": .number(0),
                      "params": .object(["clientType": .string("session-canvas")])]))
        handshakeTask = Task { [weak self, weak file] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self, self.handle === file, !self.connected else { return }
            self.disconnected()
        }
    }

    private func send(_ message: JSONValue) {
        guard let handle, let payload = try? JSONEncoder().encode(message), payload.count <= 64 * 1024 * 1024 else { return }
        var length = UInt32(payload.count).littleEndian
        var data = withUnsafeBytes(of: &length) { Data($0) }; data.append(payload)
        let frame = data
        writer.async { [weak self] in
            do { try handle.write(contentsOf: frame) }
            catch {
                Task { @MainActor in
                    guard let self, self.handle === handle else { return }
                    self.disconnected()
                }
            }
        }
    }

    private func follow(_ id: String, _ following: Bool) {
        guard clientID != nil else { return }
        pendingFollowing[id] = following
        guard followTask == nil else { return }
        let generation = followGeneration
        followTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.followGeneration == generation, let clientID = self.clientID,
                      let id = self.pendingFollowing.keys.sorted().first,
                      let following = self.pendingFollowing.removeValue(forKey: id) else { break }
                self.send(.object(["type": .string("broadcast"), "method": .string("thread-stream-following-changed"),
                    "sourceClientId": .string(clientID), "version": .number(1),
                    "params": .object(["conversationId": .string(id), "hostId": .string("local"), "following": .bool(following)])]))
                // Coalesce duplicates and avoid a burst of hundreds of desktop subscriptions.
                try? await Task.sleep(for: .milliseconds(100))
            }
            if self?.followGeneration == generation { self?.followTask = nil }
        }
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        guard buffer.count <= 64 * 1024 * 1024 + 4 else { disconnected(); return }
        while buffer.count >= 4 {
            let length = buffer.prefix(4).enumerated().reduce(0) { $0 | (Int($1.element) << ($1.offset * 8)) }
            guard length > 0, length <= 64 * 1024 * 1024 else { disconnected(); return }
            guard buffer.count >= length + 4 else { return }
            let payload = buffer.subdata(in: 4..<(length + 4))
            buffer = Data(buffer.dropFirst(length + 4))
            guard let message = try? JSONDecoder().decode(JSONValue.self, from: payload) else { disconnected(); return }
            received(message)
        }
    }

    private func received(_ message: JSONValue) {
        let type = message["type"].string, method = message["method"].string
        if type == "client-discovery-request" {
            send(.object(["type": .string("client-discovery-response"), "requestId": message["requestId"],
                          "response": .object(["canHandle": .bool(false)])]))
            return
        }
        if type == "request" {
            send(.object(["type": .string("response"), "requestId": message["requestId"],
                          "resultType": .string("error"), "error": .string("observer-only")]))
            return
        }
        if type == "response", method == "initialize", message["resultType"].string == "success",
           let id = message["result"]["clientId"].string {
            clientID = id; connected = true; handshakeTask?.cancel()
            for id in wanted { follow(id, true) }
            onChange?()
            return
        }
        guard type == "broadcast", let clientID, message["sourceClientId"].string != clientID else { return }
        let params = message["params"]
        if method == "client-status-changed", params["status"].string == "disconnected", let owner = params["clientId"].string {
            let ids = records.filter { $0.value.owner == owner }.map(\.key)
            for id in ids { records.removeValue(forKey: id); states.removeValue(forKey: id) }
            for id in refollowedOwners.keys { refollowedOwners[id]?.remove(owner) }
            if !ids.isEmpty { onChange?() }
            return
        }
        guard params["hostId"].string == "local", let id = params["conversationId"].string else { return }
        guard wanted.contains(id) else {
            if method == "thread-stream-following-changed", params["following"] == .bool(true) { onChange?() }
            return
        }
        if method == "thread-stream-following-changed", message["version"].number == 1, params["following"] == .bool(true) {
            // A desktop window connected or acquired a new thread after our initial inventory.
            guard let owner = message["sourceClientId"].string,
                  refollowedOwners[id, default: []].insert(owner).inserted else { return }
            follow(id, true)
            return
        }
        if method == "thread-stream-following-changed", params["following"] == .bool(false), let owner = message["sourceClientId"].string {
            refollowedOwners[id]?.remove(owner)
            return
        }
        guard method == "thread-stream-state-changed" else { return }
        guard message["version"].number == 11, let owner = message["sourceClientId"].string else {
            connected = false; records.removeAll(); states.removeAll(); onChange?()
            return
        }
        let change = params["change"]
        guard let revision = change["revision"].number else { return }
        let state: JSONValue
        if change["type"].string == "snapshot" {
            state = change["conversationState"]
            guard state["id"].string == id, !CodexWire.isInternalSession(state) else { return }
            if let record = records[id], record.owner == owner, record.revision > revision { return }
        } else if change["type"].string == "patches" {
            guard let record = records[id], record.owner == owner,
                  record.revision == change["baseRevision"].number,
                  revision > record.revision,
                  let updated = try? DesktopObservation.patching(record.state, with: change["patches"].array) else {
                records.removeValue(forKey: id); states.removeValue(forKey: id); onChange?(); follow(id, true)
                return
            }
            state = updated
        } else { return }
        records[id] = (owner, revision, state)
        connected = true
        let observation = DesktopObservation(state)
        if states[id] != observation { states[id] = observation; onChange?() }
    }

    private func disconnected() {
        handshakeTask?.cancel()
        followGeneration = UUID()
        followTask?.cancel(); followTask = nil; pendingFollowing.removeAll()
        handle?.readabilityHandler = nil
        try? handle?.close(); handle = nil; buffer.removeAll()
        clientID = nil; connected = false; records.removeAll(); states.removeAll(); refollowedOwners.removeAll()
        onChange?()
    }

    func stop() {
        retryTask?.cancel(); retryTask = nil
        for id in wanted { follow(id, false) }
        wanted.removeAll()
        disconnected()
    }
}

struct DesktopObservation: Equatable {
    var execution: Execution
    var requests: [String: RequestKind]
    var result: SessionResult?
    var activeTurnID: String?

    init(_ state: JSONValue) {
        let id = state["id"].string ?? ""
        let runtime = try? CodexWire.session(.object(["id": .string(id), "status": state["threadRuntimeStatus"]]), live: true)
        execution = runtime?.execution ?? .unknown; requests = runtime?.requests ?? [:]
        for request in state["requests"].array {
            let method = request["method"].string ?? ""
            let key = request["id"].string ?? request["id"].number.map { String($0) } ?? method
            if method.hasSuffix("/requestApproval") { requests[key] = .permission }
            if ["item/tool/requestUserInput", "item/tool/requestOption", "item/plan/requestImplementation", "mcpServer/elicitation/request"].contains(method) { requests[key] = .input }
        }
        var turns = state["turns"].array
        let history = state["turnHistory"]["history"]
        if state["turnHistory"]["kind"].string == "canonical" {
            turns = history["islands"].array.flatMap { $0["entries"].array }.compactMap { entry in
                guard let key = entry["value"].string else { return nil }
                return history["entitiesByKey"][key]
            }
        }
        activeTurnID = turns.last.flatMap { $0["status"].string == "inProgress" ? $0["turnId"].string : nil }
        result = turns.reversed().compactMap { turn in
            var fields = turn.object; fields["id"] = turn["turnId"]
            return CodexWire.result(.object(fields), sessionID: id)
        }.first
    }

    static func patching(_ state: JSONValue, with patches: [JSONValue]) throws -> JSONValue {
        var result = state
        for patch in patches {
            guard let op = patch["op"].string, ["add", "replace", "remove"].contains(op) else { throw CanvasError.message("Unsupported desktop patch") }
            result = try applying(op, path: ArraySlice(patch["path"].array), value: patch["value"], to: result)
        }
        return result
    }
    private static func applying(_ op: String, path: ArraySlice<JSONValue>, value: JSONValue, to root: JSONValue) throws -> JSONValue {
        guard let part = path.first else { return op == "remove" ? .null : value }
        let rest = path.dropFirst()
        switch root {
        case .object(var object):
            guard let key = part.string else { break }
            if rest.isEmpty, op == "remove" { object.removeValue(forKey: key) }
            else {
                guard object[key] != nil || (rest.isEmpty && op == "add") else { break }
                object[key] = try applying(op, path: rest, value: value, to: object[key] ?? .null)
            }
            return .object(object)
        case .array(var array):
            guard let number = part.number, number.rounded() == number, number >= 0, number <= Double(array.count) else { break }
            let index = Int(number)
            if rest.isEmpty, op == "add" { array.insert(value, at: index) }
            else {
                guard index < array.count else { break }
                if rest.isEmpty, op == "remove" { array.remove(at: index) }
                else { array[index] = try applying(op, path: rest, value: value, to: array[index]) }
            }
            return .array(array)
        default: break
        }
        throw CanvasError.message("Desktop stream needs a fresh snapshot")
    }
}
