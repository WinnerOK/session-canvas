import Foundation
import CanvasCore

let args = CommandLine.arguments
guard args.count == 4 else {
    fputs("Usage: SessionCanvasProbe ROLLOUT_PATH CODEX_HOME SESSION_ID\n", stderr)
    exit(2)
}
do {
    let entries = try RolloutReader.read(path: args[1], codexHome: args[2], sessionID: args[3])
    let evidence: [String: Any] = ["identity_verified": true, "dialogue_entries": entries.count, "terminal_results": entries.filter { $0.result != nil }.count]
    let data = try JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
} catch {
    fputs("Saved-history verification failed. No conversation content was printed.\n", stderr)
    exit(1)
}
