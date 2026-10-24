# Native macOS application

Session Canvas is a SwiftUI/AppKit desktop application for macOS 14 and later. It has no web renderer, hosted backend, or third-party package dependencies. The core model and SQLite store are separated from the AppKit interaction layer and Codex adapter.

## Build and run

With Swift 6 or newer Command Line Tools / Xcode selected:

```sh
swift build
swift run SessionCanvas
swift run SessionCanvas --demo
swift test --disable-xctest
python3 scripts/build-app.py
```

The bundle is written to `dist/Session Canvas.app`. The default signature is ad hoc for local use; distributed releases need a Developer ID identity and notarization. `--sign IDENTITY` selects a signing identity. `--debug` builds a debug bundle.

The bundle built on this machine targets Apple Silicon. Builds on another architecture require that architecture's build/test pass; a universal distribution is a separate packaging step.

The development machine has mismatched public/private `PackageDescription` interfaces. The opt-in workaround compiles its installed public interface into a local module and uses it only for the manifest compiler:

```sh
python3 scripts/swift-local.py build
python3 scripts/swift-local.py test --disable-xctest
python3 scripts/build-app.py --local-toolchain
```

The workaround never edits the installed toolchain. Ordinary installations should use the standard commands. Tests use Swift Testing; `--disable-xctest` also works on Command Line Tools installations without XCTest. No network dependency download is required.

## Controls

| Action | Control |
| --- | --- |
| Pan | Two-finger scroll, background drag, or Space + drag |
| Zoom at pointer | Trackpad pinch or Command + scroll |
| Fit to content | Toolbar button, canvas context menu, or Command + 0 |
| Open a session | Click a note; Tab between notes and press Return; or use the note context menu |
| Move a note | Drag and release; Escape cancels |
| Move a project region | Drag its header; its members travel with it |
| Resize a region | Drag its lower-right corner; invalid edits are rejected |
| Start a session | Right-click canvas background or Command + N |
| Acknowledge | Explicit Acknowledge result button beside a loaded terminal result in the viewer |
| Continue in Codex | Open in Codex in the viewer or note context menu |
| Change connection | Connection Settings, Command + comma, or the source menu in the sidebar |

The note center at release determines the target project. Borders are unassigned space. The sidebar filters attention states; clicking a project focuses its region. Titles and state text are exposed as accessibility elements with a press action. State is represented by text, icon, and color.

## Source modes

The default **Saved Codex sessions** mode connects to the installed CLI and displays real saved conversations. It never starts or resumes a turn. A separate history reader cannot see the desktop process's live state, so its notes correctly show Unknown while result-review status is tracked independently.

**Shared Codex server** uses a configured/default control socket. This requires an already-reachable server and does not start or reconfigure a daemon. Current runtime flags are used only when that source can establish them.

**Demo workspace** is a separate, persistently isolated sample with all interaction states, project regions, simulated creation, and confirmed project moves. The app labels it DEMO and never submits these actions to a model. Actual project mutations and desktop creation are unavailable until a supported interface is verified. See [integration-compatibility.md](integration-compatibility.md).

## Persistence and recovery

The app owns `~/Library/Application Support/Session Canvas/canvas.sqlite`. It never writes a private Codex database. Workspace geometry, viewport, source-qualified session/result identities, and explicit acknowledgments are persisted independently for real and demo sources. `--storage PATH` uses a separate database, useful for verification.

Opening history does not change acknowledgment. Acknowledge commits the displayed result's identity before updating the note. A newer result remains unacknowledged even if an earlier one is acknowledged. Failed writes are shown as errors. A full application restart restores cached real observations as Unknown until refreshed; incomplete inventory refreshes retain existing notes.

The application exits when its last window closes. It reconciles saved source data on the next launch; it does not install an autostart item, daemon, or menu-bar process. Connection settings are local preferences. Full transcript history is loaded on demand rather than copied into another complete conversation store.

## Implementation map

- `Sources/CanvasCore`: domain state, coordinate/region rules, source decoding, SQLite persistence.
- `Sources/SessionCanvas/NativeCanvasView.swift`: AppKit drawing, hit testing, gestures, context menus, keyboard navigation, accessibility.
- `Sources/SessionCanvas/ContentView.swift`: SwiftUI sidebar, viewer, connection and creation sheets.
- `Sources/SessionCanvas/SessionSource.swift`: real read-only/shared protocol adapters and isolated demo source.
- `Sources/SessionCanvas/RPCConnection.swift`: bounded JSONL transport with request timeouts and no implicit approval responses.
- `Sources/CanvasCore/RolloutReader.swift`: read-only, identity-checked compatibility reader for source-provided local history paths.
- `Tests/CanvasCoreTests`: attention/result races, geometry, wire compatibility, and durable source-isolated storage.
- `Tests/CanvasRuntimeTests`: opening/acknowledgment persistence, confirmation before project moves, and reconnect/stale-command behavior using the isolated demo source.

## Visual verification

The built app supports `--demo --storage PATH --capture IMAGE.png` to render its own native window into a PNG and exit. It uses view-backed rendering, not a desktop screenshot of other applications. A normal run omits `--capture` and remains interactive.

Verified on the development Mac: release compilation, ad-hoc bundle signing, native demo launch/rendering, 31 passing Swift Testing tests, five-page discovery of 390 unique saved-session identities in the probed source set, and native parsing of an existing saved session with its identity checked. Live desktop mutations remain unverified as described in the compatibility report.
