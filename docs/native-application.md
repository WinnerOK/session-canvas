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

The bundle is written to `dist/Session Canvas.app`. The default signature is ad hoc; Gatekeeper-trusted distribution requires a Developer ID identity and notarization. `--sign IDENTITY` selects a signing identity. `--debug` builds a debug bundle. `--version MAJOR.MINOR.PATCH` and `--build-number INTEGER` set bundle metadata; local defaults remain `0.1.0` and `1`.

The bundle built on this machine targets Apple Silicon. [GitHub Actions](ci-cd.md) checks Apple Silicon and Intel separately and prepares architecture-specific ZIPs and checksums as draft GitHub Releases. The workflow can be run entirely in GitHub with a version tag, creating a new tag at the verified commit if needed. Hosted PR tests and release bundle builds passed on both architectures; actual draft upload remains a separate acceptance check. These ad-hoc releases are not notarized or universal binaries.

The development machine has mismatched public/private `PackageDescription` interfaces. The opt-in workaround compiles its installed public interface into a local module and uses it only for the manifest compiler:

```sh
python3 scripts/swift-local.py build
python3 scripts/swift-local.py test --disable-xctest
python3 scripts/build-app.py --local-toolchain
```

The workaround never edits the installed toolchain. Ordinary installations should use the standard commands. Tests use Swift Testing; `--disable-xctest` also works on Command Line Tools installations without XCTest. No network dependency download is required.

## Codex verification launcher

For agent-driven checks, invoke the launcher directly by its absolute path:

```sh
python3 /Users/d-manakovskiy/personal/session-canvas/scripts/verify-local.py test
python3 /Users/d-manakovskiy/personal/session-canvas/scripts/verify-local.py test --real-source
python3 /Users/d-manakovskiy/personal/session-canvas/scripts/verify-local.py build --configuration release
python3 /Users/d-manakovskiy/personal/session-canvas/scripts/verify-local.py preview
```

The general user command rule in `~/.codex/rules/default.rules` allows exactly the `python3` plus absolute launcher-path prefix outside the Codex sandbox, with all supported arguments. A companion copy also exists in `session-canvas-verification.rules`. Other rules and the workspace sandbox are retained. Codex tool calls use `sandbox_permissions="require_escalated"`; a loaded matching allow rule avoids another approval prompt. When proposing an approval amendment, use the two-token launcher prefix rather than including a test name or output path. Invoke these commands directly; changing the script path or adding environment/shell wrappers can affect matching. A moved checkout needs a rule for its new absolute path.

[Codex loads rule files at startup](https://learn.chatgpt.com/docs/agent-configuration/rules). Restart Codex after editing them so already-running chats load the policy, then retry the direct command. An approval dialog already on screen does not disappear when a file is edited. `codex execpolicy check --rules ...` proves that a file matches a command; it does not prove that an existing chat loaded that file or ran without showing a prompt.

The launcher accepts only build, test, and preview operations, with no shell command passthrough. It uses the local manifest workaround by default; `--standard-toolchain` selects normal SwiftPM. SwiftPM's shared cache and compiler module cache are directed under `.build/`; native GUI and actual-source tests still run outside the Codex sandbox through the saved rule.

`test --filter REGEX` selects tests. `--real-source` enables saved-inventory checks with desktop observation disabled and actual-server checks in isolated homes. It does not enable the live desktop observer. The launcher clears inherited real-source, live-desktop, and old capture-test switches. Opt-in server-creation checks use their own isolated Codex home and SQLite files and start no model turn. Swift compilation defaults to two parallel jobs; `--jobs 1` reduces it further.

`preview` rebuilds and signs the bundle, opens a native demo window, saves its PNG, and exits within 45 seconds. Each run uses a fresh directory and separate SQLite file under `.build/verification/`. `--skip-build` captures the existing bundle. `--source desktop` connects to saved real sessions for inspection. Supported presentation options are `--show-session ID`, `--created-session-preview` (requires an ID), `--hide-sidebar`, and `--show-result` (demo result). These options do not create a session or submit a turn.

Optional `--storage PATH.sqlite` and `--capture PATH.png` accept files under `.build/verification/`, temporary directories, or `~/.codex/visualizations/`; symlinks are resolved before checking the boundary. The production Canvas database is outside these locations. Preview reports success only after the app exits successfully and writes a fresh PNG; a stale/missing image or failed process is a failed check. The exact capture and storage paths are printed for inspection.

## Verification safety

Use fixture tests and fresh demo captures for routine work. A user reported ChatGPT at 357.8% CPU and an application crash after the live tests on 2026-10-25. An observer subscription echo loop was reproduced separately; its exact contribution to the reported crash is unproven. Own echoes are now ignored, other-owner refollows are deduplicated, subscriptions are coalesced and paced to at most ten per second, and writes run off the main UI thread.

A live observer run or `preview --source desktop` requires separate user authorization for that specific run. Standing launcher permission is insufficient. The launcher allows the observer only with `test --real-source --live-desktop --filter installedDesktopFeedsLiveStateIntoTheApplication --observe-session ID`; broad live runs and missing IDs are rejected before starting a process. The test observes only that session and uses an in-memory Canvas database. It starts no turn and records no acknowledgment.

The live-test watchdog samples ChatGPT CPU time and RSS every 0.5 seconds. It refuses to launch when baseline CPU is at least 40%, stops after two consecutive samples at or above 80%, immediately stops at 150% or 256 MiB RSS growth, and imposes a 45-second deadline including startup. Cleanup signals only the verification's new process group. A JSON report under `.build/verification/live-watch-*.json` records baseline/peak CPU, memory growth, duration, and outcome. This measures the main ChatGPT process, not every renderer/service or long-term stability. Do not repeat a hung or failing live check. Leave ChatGPT and unrelated processes running. A bounded pass does not close full-scale or cross-version host acceptance.

## Controls

The canvas starts immediately below the window toolbar. New Session, Fit to Content, and Full Screen live in that toolbar. The native sidebar toggle collapses the left panel and gives its space to the canvas; Shift + Command + S performs the same action without changing the viewport, filters, or open session.

| Action | Control |
| --- | --- |
| Pan | Two-finger scroll, background drag, or Space + drag |
| Zoom at pointer | Trackpad pinch or Command + scroll |
| Fit to content | Toolbar button, canvas context menu, or Command + 0 |
| Toggle sidebar | Top toolbar or Shift + Command + S |
| Toggle full screen | Top toolbar or Control + Command + F |
| Open the local session viewer | Click a note, or Tab between notes and press Return |
| Move a note | Drag and release; Escape cancels |
| Move a project region | Drag its header, or any part of its area in the zoomed-out overview; all members travel with it |
| Resize a region | Drag its lower-right corner; invalid edits are rejected |
| Explore a zoomed-out project | Click its summary, or focus it with Tab and press Return |
| Show/hide attention states | Check/uncheck any combination under Attention |
| Hide one project | Click its eye button in the sidebar, or choose Hide project from its canvas context menu |
| Restore a hidden project | Choose it from Hidden projects in the sidebar |
| Reset visibility and search | All sessions, the empty-view button, or Command + 1 |
| Create a session | Top toolbar, File menu, right-click canvas background or a project area, or Command + N |
| Acknowledge | Acknowledge result in the viewer's fixed top panel; available only for Finished sessions with a loaded, unacknowledged result |
| Continue in Codex | Open in Codex in the viewer's top panel or the first item in a real note's context menu |
| Reload history | Reload history in the viewer's top panel |
| Change connection | Connection Settings, Command + comma, or the source menu in the sidebar |

The note center at release determines the target project. Borders are unassigned space. The sidebar independently toggles attention states; clicking a visible project focuses its region without clearing filters. Titles and state text are exposed as accessibility elements with a press action. State is represented by text, icon, and color.

Real session-note context menus start with Open in Codex and omit the duplicate Open session action. Primary click and keyboard activation open the local viewer. Demo notes have no native Codex navigation target.

The session viewer displays messages and results newest first, opening at the top. Loading older pages appends them below the newer content. Acknowledge result, Open in Codex, Reload history, and pagination controls stay above the scrolling transcript; narrow viewers wrap the main actions into two rows. Acknowledge targets the newest loaded result and is enabled only while the session is Finished and history is not loading. It remains disabled in Running, Waiting for you, Permission required, Idle, Archived, and Unknown, or for an unloaded/already acknowledged result. The command rechecks the current state before saving, including when a new turn starts after the viewer rendered. A newer unviewed result offers View latest result without changing the acknowledgment target. History failures appear beside Reload history for retry.

Opening or reloading the latest history can also resolve Unknown: if the newest raw turn is terminal and no newer work or pending request is known, the note and viewer become Finished for its unread result. This works with paged and legacy history even when the local rollout is unavailable. The viewer marks saved-history provenance; opening still does not acknowledge the result. Older pages, a cached Completed result alone, empty/unsupported latest evidence, and a completed turn followed by newer work cannot establish Finished. Source revision/file changes and live state take priority over a delayed history response. Normal refresh retains valid recovered evidence; explicit acknowledgment then returns the session to Idle and enables the selected age limit.

Unknown notes with cached terminal results and missing local history are rechecked automatically after the initial canvas appears. One background worker checks one session at a time, starting checks at least one second apart. Modern APIs return one latest turn; older APIs may require a full history response, whose transcript is discarded after checking state. Confirmed completion updates the note and counts without opening the viewer, acknowledging the result, or reloading the whole inventory. Active/requesting, archived/internal, no-result, and known later-local-work sessions are excluded. Unchanged source/file/result evidence is checked once per connection, including failures; changed evidence or reconnect permits another attempt, and manual Reload history remains available. Closing/disconnecting stops the queue. Viewer transcripts remain on demand.

Search, attention visibility, and individually hidden projects combine. Only projects containing matching visible sessions appear in the sidebar and canvas; overview counts and Fit to Content use the same visible set. Hidden projects can be restored individually or together from the Hidden projects menu. A fully filtered workspace shows an explicit empty view with Show all sessions. Hiding the currently viewed session closes its viewer. Visibility choices persist per source in the app's own SQLite database without altering project membership, source sessions, acknowledgments, or layout.

**Archived** appears under **Attention**, immediately above **Unknown**, and is unchecked by default. Confirmed archived sessions show Archived on their note and in the viewer even when execution is unavailable or local history is missing. The checkbox shows/hides them independently of Unknown and without acknowledging their results. The former Hide archived sessions choice migrates to this checkbox; no separate archive toggle remains under Visibility.

**Hide Idle after** remains under Visibility: Never (default), 15 minutes, 1 hour, 1 day, 1 week, or 1 month (30 days). **Hide unknown** sits directly below it and starts checked, including for existing saved preferences. With an age limit selected, it also hides Unknown sessions once their last source activity reaches that limit. Uncheck it to apply the limit only to confirmed Idle sessions. Never disables age hiding for both states. Running, pending input/permission, and any known result awaiting acknowledgment remain eligible regardless of age, even if displayed as Unknown; explicit search/attention/project filters still apply. The Unknown checkbox under Attention independently controls all Unknown sessions. These settings persist per source. **Show all sessions** clears the filters, including Archived, by resetting the timeout to Never. Time is reevaluated every 30 seconds, and new activity makes a note eligible again at its saved position. Missing activity timestamps cannot expire by age.

Archive reviewed Idle sessions through **Archive session** in the note context menu or viewer. The action refreshes and rechecks eligibility before calling Codex and saves archive state only after confirmation. Check Archived to use **Unarchive session**. Restoration recalculates the session's state from current evidence, including Unknown or Finished, without acknowledging its result. Archived sessions cannot acknowledge results until restored to Finished. History, project membership, and note position are retained; errors leave the note available. Archive is unavailable for active, uncertain, or unreviewed sessions. The demo simulates the same lifecycle within its own store.

Notes show source last activity in one largest unit: `15m ago`, `1h ago`, `1d ago`, capped at `1 month ago` for 30 days and older. Under one minute and future timestamps show `0m ago`; missing timestamps show Activity unavailable. The viewer includes relative activity and the exact local date/time. Viewing, acknowledging, refreshing, and archiving do not manufacture activity.

Zooming out hides individual project members and draws labels inside their original project regions. Names use a readable single line with tail truncation. If the region cannot fit a meaningful prefix plus an ellipsis, or a full line's height, it shows only its area without text or a session count. Counts and attention dots appear only when there is enough additional room. Regions and hit areas follow the viewport transform exactly: labels never move, enlarge, or rearrange projects to avoid crowding or viewport edges. Clicking a project area, including one without a label, zooms into its sessions; dragging it moves the project and all its member notes, including filtered-out members, without changing the viewport. The area and label preview that same movement before release. Escape cancels; Space + drag or a background drag pans the canvas. Closer zooms show compact session titles and states, then full note details. Selecting even a tall project opens at a readable zoom near its top.

## Source modes

The default **Codex desktop** mode combines saved-session discovery/history through the installed CLI with live observations from the desktop's existing local coordination socket. It prefers the desktop's bundled CLI for protocol compatibility. The observer follows revisioned conversation snapshots and patches; Running, input, approval, and completion changes update automatically. It never claims ownership, starts or resumes a turn, executes a tool, or answers a request. A history refresh cannot overwrite a newer live observation with `notLoaded`.

The observer reconnects automatically after desktop/socket loss. Live observations are cleared immediately on disconnect or a stream revision gap; a fresh snapshot restores them. Discovery checks identity-verified saved terminal evidence for unloaded sessions before opening their viewers: a terminal latest turn becomes Finished until acknowledged, then Idle. Current live state takes priority for non-archived sessions; confirmed archives display Archived. Discovery reads at most a 64 KiB identity header and 256 KiB tail per exact inventory-provided rollout, with revision/file caching; later work or incomplete evidence remains Unknown. Missing local files are explained in the viewer rather than treated as inactivity. The connection indicator and viewer distinguish live observations from saved state. This is a version-checked desktop compatibility adapter, not a public app-server socket: unsupported stream versions fail closed. It checks socket and peer ownership, bounds frames, ignores remote-host state, and never starts an IPC router or daemon.

Guardian reviews and other sub-agent sessions are excluded using source/parent metadata, including notes cached by earlier versions. Local projects and explicit session assignments are read from the connected Codex home's `.codex-global-state.json`. Projectless sessions stay unassigned even when their working directory matches a project's folder. This discovery adapter is read-only; moves of existing sessions between projects still happen in Codex.

Desktop subscription echoes are ignored, repeated announcements from another observer are deduplicated, and socket writes run off the main thread. This prevents a following-announcement loop from freezing updates when several observers or windows share the desktop feed. Explicit archive/restore commands use the source API separately from discovery; project moves remain unavailable.

**Shared Codex server** uses a configured/default control socket. This requires an already-reachable server and does not start or reconfigure a daemon. Current runtime flags are used only when that source can establish them.

Right-clicking a project area offers **New session in project…** at every zoom, with that project selected in the dialog. The real desktop source creates an empty durable session using the project's server identity and confirmed working roots, then automatically opens the exact session in Codex for the initial instruction. A blank name becomes **New session**. Without a project, the working folder is optional: leave it blank for a separate workspace under `~/Library/Application Support/Session Canvas/Workspaces`, or choose an existing folder. The creator and independent history verifier both exit before native opening. Creation starts no model turn and overrides no permission settings.

The new note is placed with its top-left corner at the clicked canvas coordinate when that position satisfies membership/collision rules. If a visible or hidden note occupies that placement, the app chooses the closest free position with confirmed membership near the click instead of returning to the grid near the origin. Refresh and restart retain the position. Creation in the context's project preserves pan and zoom, including collision adjustment and viewer resizing; choosing a different project can focus its adjusted placement automatically. The note is temporarily shown even if Unknown, search, or its project is hidden; saved filters and other hidden notes are unchanged. Its viewer explains the exception and retains **Open in Codex** for retry. **Apply filters**, changing search/visibility, creating another session, or reconnecting ends the exception. The tested Codex server omits empty sessions from its list, so use the exact opened session rather than searching the list before its first message. Submission errors appear within the creation dialog and preserve inputs for correction.

The server APIs are negotiated; older CLI versions and the unverified shared mode explain why creation is unavailable. A confirmed session remains on the canvas even while empty threads are absent from inventory, or naming/history verification/navigation fails. A verification warning prevents automatic native opening. An unconfirmed create is never automatically retried. See [integration-compatibility.md](integration-compatibility.md).

**Demo workspace** is a separate, persistently isolated sample with all interaction states, project regions, simulated creation, and confirmed project moves. The app labels it DEMO and never submits these actions to a model. Moving existing real sessions between projects remains unavailable.

## Persistence and recovery

The app owns `~/Library/Application Support/Session Canvas/canvas.sqlite`. It never directly opens or writes a Codex database. Workspace geometry, viewport, source-qualified session/result identities, explicit acknowledgments, attention/project visibility, and archive/idle settings are persisted independently for real and demo sources. Schema version 2 adds visibility without resetting the existing workspace; new lifecycle fields decode old payloads with defaults. Search is transient. `--storage PATH` uses a separate database, useful for verification.

Opening history does not change acknowledgment. Acknowledge commits the displayed result's identity before updating the note. A newer result remains unacknowledged even if an earlier one is acknowledged. Failed writes are shown as errors. A full application restart restores cached non-archived real observations as Unknown until refreshed; confirmed archives retain Archived. Incomplete inventory refreshes retain existing notes.

The application exits when its last window closes. It reconciles saved source data on the next launch; it does not install an autostart item, daemon, or menu-bar process. Connection settings are local preferences. Full transcript history is loaded on demand rather than copied into another complete conversation store.

## Implementation map

- `Sources/CanvasCore`: domain state, coordinate/region rules, source decoding, SQLite persistence.
- `Sources/SessionCanvas/NativeCanvasView.swift`: AppKit drawing, hit testing, gestures, context menus, keyboard navigation, accessibility.
- `Sources/SessionCanvas/CanvasOverview.swift`: fitting readable labels inside the original projected project regions.
- `Sources/SessionCanvas/ContentView.swift`: SwiftUI sidebar, viewer, connection and creation sheets.
- `Sources/SessionCanvas/SessionSource.swift`: real inventory/history adapters, confirmed empty-session creation, and isolated demo source.
- `Sources/SessionCanvas/DesktopRuntime.swift`: read-only desktop observation, revision reconciliation, bounded framing, and reconnect.
- `Sources/SessionCanvas/RPCConnection.swift`: bounded JSONL transport with request timeouts and no implicit approval responses.
- `Sources/CanvasCore/RolloutReader.swift`: read-only, identity-checked compatibility reader for source-provided local history paths.
- `Sources/CanvasCore/DesktopProjectCatalog.swift`: bounded read-only import of saved local projects and exact session assignments.
- `Tests/CanvasCoreTests`: attention/result races, geometry, wire compatibility, and durable source-isolated storage.
- `Tests/CanvasRuntimeTests`: opening/acknowledgment persistence, confirmation before project moves, and reconnect/stale-command behavior using the isolated demo source.

## Visual verification

The built app supports `--demo --storage PATH --capture IMAGE.png` to render its own native window, including the toolbar, into a PNG and exit. Add `--hide-sidebar` to verify the expanded canvas with its sidebar collapsed. It uses view-backed rendering, not a desktop screenshot of other applications. A normal run omits `--capture` and remains interactive.

Verified on the development Mac before the documentation audit: 60 passing core/runtime tests, release compilation, ad-hoc bundle signing, native demo and saved-canvas rendering, a point-in-time inventory of 392 user sessions with 1,069 internal sessions hidden, import of 18 projects with 101 assigned sessions, and identity-checked parsing of existing saved history. Native rendering checks cover readable project names at 42% and 25%, truncated names at 10%, and areas without text at 3% and 1%, including an 18-project distant overview. Geometry and event checks verify stable projected bounds and overview dragging with hidden members. Whole-line note text, composed visibility filters, source-isolated persistence, and hidden/empty project behavior are covered. Viewer/toolbar/sidebar presentation also has code and native-capture inspection, rather than a dedicated automated SwiftUI interaction suite.

The actual bundled server verifies empty-session creation and independent resume with the inventory client still connected, including a named project session, a projectless session with blank name/folder, and the ApplicationModel creation flow with Unknown hidden. A native keyboard-event test activates the SwiftUI submit button through Return and verifies viewer selection, exactly one creation, and the captured automatic navigation URL. Canvas interaction tests retain native mouse events. Existing user-created projectless test sessions were opened through internal desktop navigation and the actual `codex://threads` handler; each reached Idle with zero turns. Native capture verifies the fully visible focused note, success/filter notice, and retry controls. Complete in-project automatic-opening acceptance, real existing-session membership mutations, and cross-restart recovery of uncertain operations remain gates. See the [OpenSpec correction/evidence matrix](../openspec/changes/add-session-canvas/verification.md) and [compatibility report](integration-compatibility.md).
