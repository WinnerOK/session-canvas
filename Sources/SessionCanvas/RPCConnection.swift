import Foundation
import CanvasCore

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
    private var buffer = Data()
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
        proc.terminationHandler = { [weak self] terminated in
            Task { @MainActor in
                guard let self, self.process === terminated else { return }
                self.failAll(CanvasError.message("Codex connection closed. Reconnect in Connection settings."))
                self.onDisconnect?()
            }
        }
        try proc.run()
        process = proc; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading; diagnostics = stderr.fileHandleForReading
        output?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in self?.receive(data) }
        }
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
    private func receive(_ data: Data) {
        buffer.append(data)
        guard buffer.count <= 64 * 1024 * 1024 else { stop(); onDisconnect?(); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard let value = try? JSONDecoder().decode(JSONValue.self, from: line) else { continue }
            if let id = value["id"].number, value["method"].string == nil, let continuation = pending.removeValue(forKey: Int(id)) {
                if value["error"] != .null {
                    // Do not surface arbitrary server error strings containing private tool inputs.
                    continuation.resume(throwing: RPCFailure(code: Int(value["error"]["code"].number ?? -1), message: "Codex rejected this request (\(Int(value["error"]["code"].number ?? -1)))."))
                } else { continuation.resume(returning: value["result"]) }
            } else { onMessage?(value) }
        }
    }
    private func failAll(_ error: Error) {
        let continuations = pending.values; pending.removeAll()
        for continuation in continuations { continuation.resume(throwing: error) }
    }
    func stop() {
        output?.readabilityHandler = nil; diagnostics?.readabilityHandler = nil
        process?.terminationHandler = nil
        try? input?.close()
        if process?.isRunning == true { process?.terminate() }
        process = nil; input = nil; output = nil; diagnostics = nil; buffer.removeAll()
        failAll(CanvasError.message("Codex connection was closed."))
    }
}
