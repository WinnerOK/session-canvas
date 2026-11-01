# Session Canvas

A free-roam canvas for existing Codex sessions: movable session notes, project regions, live attention states, and explicit result acknowledgment.

Creating a session at a free clicked location keeps that position and the current canvas pan and zoom. If another note occupies the point, the new note uses the nearest free position instead of jumping to the grid near the origin.

When zooming out, projects hide their member notes at exactly the same point that session notes stop showing compact text. Until that point, sessions inside projects remain individually visible and clickable.

When a full project needs space for an arriving session, it keeps its position and width and grows downward. Blocking projects move down with their notes, and blocking unassigned notes move down individually, propagating only through the affected chain. Same-layer hidden notes participate; other layers and the current pan/zoom stay unchanged. Refresh and reopening retain the resulting layout without automatic shrinking.

Select exactly one canvas layer in the sidebar: **Active sessions**, **Stale sessions**, or **Inactive sessions**. Archived and Unknown always belong to Inactive. Idle sessions past **Hide Idle after** move to Stale; current work, requests, unread results, and recent Idle sessions remain Active. Never leaves Stale empty. Each layer has independent project bounds, note positions, viewport, and attention/project filters. Geometry on another layer cannot block a project move. Returning sessions retain their actual Codex project and use its destination-layer region, restoring a valid remembered position or finding free space there. **Show all in this layer** clears local filters and search without changing the cutoff or combining layers.

Archive reviewed Idle sessions from a note's context menu or viewer, and restore them from Inactive. Archive state remains independent of acknowledgment. Notes show compact last source activity; current history recovery can move an Unknown session to Active Finished while keeping its result unread.

Unknown notes with a cached result and unavailable local history are rechecked automatically after discovery. Verified terminal latest turns become Finished without opening each note or marking the result reviewed. Checks run one at a time, at most once per second, and unchanged evidence is not repeatedly queried.

After restart or observation loss, **Unknown** means current execution is unverified; it does not mean Idle or approval granted. Notes and the viewer retain **Last known** execution/input/permission state separately, including request and active-turn identities in the local cache. Already-erased hints cannot be recovered from that cache alone. Use **Open in Codex** to verify an outstanding request.

Toolbar **Refresh Sessions** or **⌘R** checks the whole source, including filtered sessions, sessions without cached results, and cached identities omitted by the current inventory. A progress window shows completed/total checks, failures, and sessions still Unknown, with Stop and Done. Current live work/requests take priority; saved completion becomes Finished until explicitly acknowledged, then Idle. Regular automatic discovery keeps its lighter behavior.

Use **Acknowledge all** in the top toolbar to mark the latest results of every Finished session in the current source as reviewed, including hidden notes. Other states and later results stay unchanged. In a session viewer, the same acknowledgment button becomes **Mark as unread** so a reviewed result can be restored to unread in any state, even when its history is unavailable.

Use **Rearrange** to compact the selected layer into roughly square project and unassigned-session blocks, ordered by Attention and recent activity. Current filtered members travel with their project while retaining offsets; other filtered current geometry stays fixed. Other layers and remembered departed slots impose no obstacles. The command saves the complete layout and preserves pan/zoom and actual membership; state changes never invoke it automatically.

The application is implemented in SwiftUI/AppKit for macOS 14 and later, with SQLite persistence and no third-party package dependencies. Saved-session discovery/history work through the installed Codex source, with Guardian and other internal agent sessions hidden. Existing local projects and explicit memberships are imported from saved desktop metadata. The default connection follows live execution and attention state from the running Codex desktop, with automatic reconnection and saved-history fallback. Right-click a project area to create a saved empty session in that project and open it automatically in Codex. Names and projectless working folders are optional; creation verifies resumable history and releases its ownership before continuation. The new note/viewer stay visible despite filters, with Open in Codex for retry. Existing-session project moves are currently unavailable through the real Codex connection: the tested backend API does not update desktop membership. Move a chat in Codex to synchronize its actual project into Canvas. An isolated demo exercises simulated execution and project moves.

Saved desktop project assignments survive refresh even when backend membership is null or different. Old Canvas confirmations cannot override desktop membership and are discarded during synchronization.

```sh
swift run SessionCanvas
swift run SessionCanvas --demo
swift test --disable-xctest
python3 scripts/build-app.py
```

The local app bundle is written to `dist/Session Canvas.app`. See the [native app guide](docs/native-application.md) for controls, packaging, and the opt-in workaround for this machine's SwiftPM installation.

Local and release app bundles use the selected [blue session-cards icon](assets/branding/README.md). The branding folder also retains the original alternatives and [four light concepts](assets/branding/LIGHT-CONCEPTS.md).

Codex uses a [stable verification launcher](docs/native-application.md#codex-verification-launcher) for builds, tests, and native captures. One saved permission covers the launcher with different filters, session IDs, and capture paths.

History loads newest first in pages of at most twelve turn summaries; **Load older history** requests another page only when needed. Linear JSONL framing and decoding run outside the UI actor with paced delivery. The [performance investigation and repair](docs/history-loading-performance.md) records the reproduced stall, passing synthetic regressions, and remaining installed-session acceptance.

GitHub Actions runs application/tooling tests and release builds for Apple Silicon (`arm64`) on every pull request. To prepare a release, open **Actions → Release → Run workflow** and enter a tag such as `v0.2.0`; after verification, review and publish the generated draft with the arm64 app ZIP and SHA-256 file. Version-tag pushes also trigger releases. See the [CI/CD guide](docs/ci-cd.md) for setup, retries, and signing limitations.

- [Domain glossary](GLOSSARY.md)
- [Native application and build instructions](docs/native-application.md)
- [GitHub checks and app releases](docs/ci-cd.md)
- [Authorized agent Git/GitHub workflow](docs/git-workflow.md)
- [Verified Codex integration and remaining limits](docs/integration-compatibility.md)
- [Domain model, state rules, and edge cases](docs/domain-model.md)
- [Separate local app vs. in-app Codex view](docs/delivery-options.md)
- [Technical stack comparison](docs/technical-stack-options.md)
- [OpenSpec proposal](openspec/changes/add-session-canvas/proposal.md)
- [Design and integration gate](openspec/changes/add-session-canvas/design.md)
- [Implementation tasks](openspec/changes/add-session-canvas/tasks.md)
- [Correction coverage and verification evidence](openspec/changes/add-session-canvas/verification.md)
- [Complete SDD function inventory](openspec/changes/add-session-canvas/functional-coverage.md)

The selected delivery is a native Mac-only companion with a session/result viewer, Acknowledge, and Open in Codex. The remaining desktop integration gate is tracked explicitly; demo interactions are not presented as verified desktop mutations.

The behavioral specifications are [canvas-workspace](openspec/changes/add-session-canvas/specs/canvas-workspace/spec.md), [session-attention](openspec/changes/add-session-canvas/specs/session-attention/spec.md), [project-regions](openspec/changes/add-session-canvas/specs/project-regions/spec.md), [session-actions](openspec/changes/add-session-canvas/specs/session-actions/spec.md), [source-connection](openspec/changes/add-session-canvas/specs/source-connection/spec.md), [local-verification](openspec/changes/add-session-canvas/specs/local-verification/spec.md), and [release-automation](openspec/changes/add-session-canvas/specs/release-automation/spec.md). The [function inventory](openspec/changes/add-session-canvas/functional-coverage.md) links implemented behavior to these contracts and distinguishes inspected code from verified acceptance.

Validate the proposal with OpenSpec 1.15.0:

```sh
openspec validate --all --strict
```
