import Foundation
import CanvasCore
import Darwin

struct RPCFailure: LocalizedError {
    var code: Int
    var message: String
    var errorDescription: String? { message }
}

@MainActor
final class RPCConnection {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var diagnostics: FileHandle?
    private var reader: RPCStreamReader?
    private var generation = UUID()
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    var onMessage: ((JSONValue) -> Void)?
    var onDisconnect: (() -> Void)?

    func start(executable: String, arguments: [String]) throws {
        stop()
        let proc = Process(), stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        proc.standardInput = stdin; proc.standardOutput = stdout; proc.standardError = stderr
        try proc.run()
        process = proc; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading; diagnostics = stderr.fileHandleForReading
        let token = generation
        let reader = RPCStreamReader(handle: stdout.fileHandleForReading, onValue: { [weak self] value in
            let delivered = DispatchSemaphore(value: 0)
            Task { @MainActor [weak self] in
                defer { delivered.signal() }
                guard let self, self.generation == token else { return }
                self.receive(value)
            }
            delivered.wait()
        }, onEnd: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.stop()
                self.onDisconnect?()
            }
        })
        self.reader = reader
        reader.start()
        // Drain stderr, but never echo arbitrary runtime logs or credentials into the UI.
        diagnostics?.readabilityHandler = { handle in _ = handle.availableData }
    }
    func request(_ method: String, _ params: [String: JSONValue] = [:]) async throws -> JSONValue {
        nextID += 1
        let id = nextID
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do { try send(.object(["id": .number(Double(id)), "method": .string(method), "params": .object(params)])) }
            catch { pending.removeValue(forKey: id)?.resume(throwing: error); return }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                self?.pending.removeValue(forKey: id)?.resume(throwing: CanvasError.message("Codex did not answer \(method) within 20 seconds. The connection may be unavailable."))
            }
        }
    }
    func notify(_ method: String) throws { try send(.object(["method": .string(method)])) }
    private func send(_ value: JSONValue) throws {
        guard process?.isRunning == true, let input else { throw CanvasError.message("Connect to Codex first.") }
        var data = try JSONEncoder().encode(value); data.append(10)
        try input.write(contentsOf: data)
    }
    private func receive(_ value: JSONValue) {
        if let id = value["id"].number, value["method"].string == nil, let continuation = pending.removeValue(forKey: Int(id)) {
            if value["error"] != .null {
                // Do not surface arbitrary server error strings containing private tool inputs.
                continuation.resume(throwing: RPCFailure(code: Int(value["error"]["code"].number ?? -1), message: "Codex rejected this request (\(Int(value["error"]["code"].number ?? -1)))."))
            } else { continuation.resume(returning: value["result"]) }
        } else { onMessage?(value) }
    }
    private func failAll(_ error: Error) {
        let continuations = pending.values; pending.removeAll()
        for continuation in continuations { continuation.resume(throwing: error) }
    }
    func stop() {
        generation = UUID()
        reader?.cancel(); reader = nil
        diagnostics?.readabilityHandler = nil
        process?.terminationHandler = nil
        try? input?.close()
        if process?.isRunning == true { process?.terminate() }
        process = nil; input = nil; output = nil; diagnostics = nil
        failAll(CanvasError.message("Codex connection was closed."))
    }
    /// A creator owns its thread lock until the process exits, even after unsubscribe.
    /// Wait without blocking the UI; only terminate the child this connection started.
    func stopAndWait() async {
        guard let child = process else { return }
        stop()
        let deadline = Date().addingTimeInterval(3)
        while child.isRunning, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        await Task.detached { child.waitUntilExit() }.value
    }
}
