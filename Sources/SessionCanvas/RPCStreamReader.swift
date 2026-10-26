import Foundation
import Darwin
import CanvasCore

/// Keeps delimiter search linear across fragmented frames and compacts once per read.
struct RPCLineBuffer {
    private var buffer = Data()
    private var searchedBytes = 0
    let maximumFrameBytes: Int

    init(maximumFrameBytes: Int = 64 * 1024 * 1024) {
        self.maximumFrameBytes = maximumFrameBytes
    }

    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var lines: [Data] = []
        var start = buffer.startIndex
        var search = buffer.index(start, offsetBy: searchedBytes)
        while let newline = buffer[search...].firstIndex(of: 10) {
            guard buffer.distance(from: start, to: newline) <= maximumFrameBytes else { throw oversizedFrame() }
            lines.append(Data(buffer[start..<newline]))
            start = buffer.index(after: newline)
            search = start
        }
        guard buffer.distance(from: start, to: buffer.endIndex) <= maximumFrameBytes else { throw oversizedFrame() }
        if start != buffer.startIndex { buffer = Data(buffer[start...]) }
        searchedBytes = buffer.count
        return lines
    }

    private func oversizedFrame() -> CanvasError {
        .message("Codex sent a response larger than the connection's frame limit.")
    }
}

/// Blocking pipe I/O belongs on its own dispatch queue, not the UI or Swift's
/// cooperative executor. The consumer acknowledges each decoded value before
/// reading continues, so decoded messages cannot accumulate behind the UI.
final class RPCStreamReader: @unchecked Sendable {
    private let handle: FileHandle
    private let queue = DispatchQueue(label: "SessionCanvas.rpc-reader", qos: .userInitiated)
    private let lock = NSLock()
    private var cancelled = false // Only accessed under lock; framing is queue-local.
    private let onValue: @Sendable (JSONValue) -> Void
    private let onEnd: @Sendable () -> Void

    init(handle: FileHandle, onValue: @escaping @Sendable (JSONValue) -> Void, onEnd: @escaping @Sendable () -> Void) {
        self.handle = handle; self.onValue = onValue; self.onEnd = onEnd
    }

    func start() { queue.async { self.read() } }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    private var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    private func read() {
        defer { try? handle.close() }
        var frames = RPCLineBuffer()
        var bytes = [UInt8](repeating: 0, count: 64 * 1024)
        var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0)
        do {
            while !isCancelled {
                // A bounded wait lets cancellation release even a silent pipe.
                let ready = Darwin.poll(&descriptor, 1, 100)
                if ready < 0, errno == EINTR { continue }
                if ready < 0 { break }
                if ready == 0 { continue }
                let count = bytes.withUnsafeMutableBytes { Darwin.read(handle.fileDescriptor, $0.baseAddress, $0.count) }
                guard !isCancelled else { return }
                if count < 0, errno == EINTR { continue }
                if count <= 0 { break }
                for line in try frames.append(Data(bytes.prefix(count))) {
                    guard !isCancelled else { return }
                    if let value = try? JSONDecoder().decode(JSONValue.self, from: line) { onValue(value) }
                }
            }
        } catch { /* Connection errors are normalized by the owner, never echoed. */ }
        if !isCancelled { onEnd() }
    }
}
