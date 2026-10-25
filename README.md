# Session Canvas

A free-roam canvas for existing Codex sessions: movable session notes, project regions, live attention states, and explicit result acknowledgment.

Creating a session at a free clicked location keeps that position and the current canvas pan and zoom. If another note occupies the point, the new note uses the nearest free position instead of jumping to the grid near the origin.

Reduce clutter with **Archived** in the sidebar's **Attention** block, immediately above **Unknown**, and **Hide Idle after** under Visibility. Archived sessions show their own state even without local history and are hidden by default. **Hide unknown** starts checked and applies the same age limit to Unknown sessions; Never disables age hiding. Active sessions, pending requests, and results awaiting explicit review remain protected. Archive reviewed Idle sessions from a note's context menu or viewer; show Archived to restore them without acknowledging their results. Notes show compact last activity such as `15m ago`, `1h ago`, or `1 month ago`; the viewer also shows the exact timestamp. Saved terminal evidence resolves unloaded sessions during discovery. Reading the latest history also recovers Finished when its last turn is terminal, even without a local rollout; newer work and requests keep priority.

Unknown notes with a cached result and unavailable local history are rechecked automatically after discovery. Verified terminal latest turns become Finished without opening each note or marking the result reviewed. Checks run one at a time, at most once per second, and unchanged evidence is not repeatedly queried.

Use **Acknowledge all** in the top toolbar to mark the latest results of every Finished session in the current source as reviewed, including hidden notes. Other states and later results stay unchanged. In a session viewer, the same acknowledgment button becomes **Mark as unread** so a reviewed result can be restored to unread in any state, even when its history is unavailable.

Use **Rearrange** in the top toolbar to compact the currently visible notes: projects first, unassigned sessions below, with Attention status and newest activity ordering inside each area. Hidden members travel with their project while keeping their offsets inside it; other hidden notes and fully hidden projects remain fixed. The command preserves pan/zoom and source membership, saves the complete layout, and never runs automatically on status/filter changes. Use Fit to Content to see the result at another scale.

The application is implemented in SwiftUI/AppKit for macOS 14 and later, with SQLite persistence and no third-party package dependencies. Saved-session discovery/history work through the installed Codex source, with Guardian and other internal agent sessions hidden. Existing local projects and explicit memberships are imported from saved desktop metadata. The default connection follows live execution and attention state from the running Codex desktop, with automatic reconnection and saved-history fallback. Right-click a project area to create a saved empty session in that project and open it automatically in Codex. Names and projectless working folders are optional; creation verifies resumable history and releases its ownership before continuation. The new note/viewer stay visible despite filters, with Open in Codex for retry. With a supported desktop CLI (verified from 0.164.0-alpha.11.1), drag an existing session into, between, or out of project areas to change actual Codex membership after API readback. Older/shared connections retain the unsupported-move guard. An isolated demo exercises simulated execution and project moves.

```sh
swift run SessionCanvas
swift run SessionCanvas --demo
swift test --disable-xctest
python3 scripts/build-app.py
```

The local app bundle is written to `dist/Session Canvas.app`. See the [native app guide](docs/native-application.md) for controls, packaging, and the opt-in workaround for this machine's SwiftPM installation.

Codex uses a [stable verification launcher](docs/native-application.md#codex-verification-launcher) for builds, tests, and native captures. One saved permission covers the launcher with different filters, session IDs, and capture paths.

GitHub Actions runs application/tooling tests and release builds for Apple Silicon and Intel on every pull request. To prepare a release, open **Actions → Release → Run workflow** and enter a tag such as `v0.2.0`; after verification, review and publish the generated draft with app ZIPs and SHA-256 files. Version-tag pushes also trigger releases. See the [CI/CD guide](docs/ci-cd.md) for setup, retries, and signing limitations.

- [Domain glossary](GLOSSARY.md)
- [Native application and build instructions](docs/native-application.md)
- [GitHub checks and app releases](docs/ci-cd.md)
- [Verified Codex integration and remaining limits](docs/integration-compatibility.md)
- [Domain model, state rules, and edge cases](docs/domain-model.md)
- [Separate local app vs. in-app Codex view](docs/delivery-options.md)
- [Technical stack comparison](docs/technical-stack-options.md)
- [OpenSpec proposal](openspec/changes/add-session-canvas/proposal.md)
- [Design and integration gate](openspec/changes/add-session-canvas/design.md)
- [Implementation tasks](openspec/changes/add-session-canvas/tasks.md)
- [Correction coverage and verification evidence](openspec/changes/add-session-canvas/verification.md)

The selected delivery is a native Mac-only companion with a session/result viewer, Acknowledge, and Open in Codex. The remaining desktop integration gate is tracked explicitly; demo interactions are not presented as verified desktop mutations.

The behavioral specifications are [canvas-workspace](openspec/changes/add-session-canvas/specs/canvas-workspace/spec.md), [session-attention](openspec/changes/add-session-canvas/specs/session-attention/spec.md), [project-regions](openspec/changes/add-session-canvas/specs/project-regions/spec.md), [session-actions](openspec/changes/add-session-canvas/specs/session-actions/spec.md), [local-verification](openspec/changes/add-session-canvas/specs/local-verification/spec.md), and [release-automation](openspec/changes/add-session-canvas/specs/release-automation/spec.md).

Validate the proposal with OpenSpec 1.15.0:

```sh
openspec validate add-session-canvas --strict
```
