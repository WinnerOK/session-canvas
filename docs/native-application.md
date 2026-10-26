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

The selected application icon is the [blue session-cards image](../assets/branding/README.md). The builder includes its multi-resolution `SessionCanvas.icns` in `Contents/Resources` and sets `CFBundleIconFile` before signing. This applies to local and release bundles; running the bare SwiftPM executable does not package app resources. A missing icon resource fails the build before signing.

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

`test --configuration release --history-performance --jobs 1` selects the synthetic history responsiveness suite. It uses the production adapter against a temporary fixture server, reports bytes/entry counts, elapsed/process CPU time and maximum 10 ms UI-actor heartbeat gap, and asserts a 250 ms gap budget, including the original twelve-turn 12.1 MiB reply. These fixture checks pass after the transport repair. Ordinary tests retain functional framing and pagination checks and skip machine-dependent timing. The launcher clears inherited timing opt-ins and rejects combining this mode with installed-source/live checks. See the [history performance investigation and repair](history-loading-performance.md) for measurements and remaining acceptance.

`preview` rebuilds and signs the bundle, opens a native demo window, saves its PNG, and exits within 45 seconds. Each run uses a fresh directory and separate SQLite file under `.build/verification/`. `--skip-build` captures the existing bundle. `--source desktop` connects to saved real sessions for inspection. Use `--layer active|stale|inactive` to capture one saved layer. Other supported presentation options are `--show-session ID`, `--created-session-preview` (requires an ID), `--hide-sidebar`, and `--show-result` (demo result). These options do not create a session or submit a turn.

Optional `--storage PATH.sqlite` and `--capture PATH.png` accept files under `.build/verification/`, temporary directories, or `~/.codex/visualizations/`; symlinks are resolved before checking the boundary. The production Canvas database is outside these locations. Preview reports success only after the app exits successfully and writes a fresh PNG; a stale/missing image or failed process is a failed check. The exact capture and storage paths are printed for inspection.

## Verification safety

Use fixture tests and fresh demo captures for routine work. A user reported ChatGPT at 357.8% CPU and an application crash after the live tests on 2026-10-25. An observer subscription echo loop was reproduced separately; its exact contribution to the reported crash is unproven. Own echoes are now ignored, other-owner refollows are deduplicated, subscriptions are coalesced and paced to at most ten per second, and writes run off the main UI thread.

A live observer run or `preview --source desktop` requires separate user authorization for that specific run. Standing launcher permission is insufficient. The launcher allows the observer only with `test --real-source --live-desktop --filter installedDesktopFeedsLiveStateIntoTheApplication --observe-session ID`; broad live runs and missing IDs are rejected before starting a process. The test observes only that session and uses an in-memory Canvas database. It starts no turn and records no acknowledgment.

The live-test watchdog samples ChatGPT CPU time and RSS every 0.5 seconds. It refuses to launch when baseline CPU is at least 40%, stops after two consecutive samples at or above 80%, immediately stops at 150% or 256 MiB RSS growth, and imposes a 45-second deadline including startup. Cleanup signals only the verification's new process group. A JSON report under `.build/verification/live-watch-*.json` records baseline/peak CPU, memory growth, duration, and outcome. This measures the main ChatGPT process, not every renderer/service or long-term stability. Do not repeat a hung or failing live check. Leave ChatGPT and unrelated processes running. A bounded pass does not close full-scale or cross-version host acceptance.

## Controls

The canvas starts immediately below the window toolbar. New Session, Rearrange, Fit to Content, Full Screen, and Acknowledge all live in that toolbar. The native sidebar toggle collapses the left panel and gives its space to the canvas; Shift + Command + S performs the same action without changing the viewport, filters, or open session.

| Action | Control |
| --- | --- |
| Pan | Two-finger scroll, background drag, or Space + drag |
| Zoom at pointer | Trackpad pinch or Command + scroll |
| Fit to content | Toolbar button, canvas context menu, or Command + 0 |
| Toggle sidebar | Top toolbar or Shift + Command + S |
| Toggle full screen | Top toolbar or Control + Command + F |
| Open the local session viewer | Click a note, or Tab between notes and press Return |
| Move a note | Drag and release; Escape cancels |
| Move a project region | Drag its header, or any part of its area in the zoomed-out overview; current members on that layer travel with it |
| Resize a region | Drag its lower-right corner; invalid edits are rejected |
| Explore a zoomed-out project | Click its summary, or focus it with Tab and press Return |
| Show/hide attention states | Check/uncheck any combination under Attention |
| Hide one project | Click its eye button in the sidebar, or choose Hide project from its canvas context menu |
| Restore a hidden project | Choose it from Hidden projects in the sidebar |
| Select layer | Active sessions, Stale sessions, or Inactive sessions in the sidebar |
| Reset visibility and search | Show all in this layer or Command + 1; keep the cutoff and other layers |
| Create a session | Top toolbar, File menu, right-click canvas background or a project area, or Command + N |
| Rearrange visible notes | Rearrange in the top toolbar; compact projects and unassigned notes, carry hidden project members with their project, and preserve pan/zoom |
| Acknowledge | Acknowledge result in the viewer's fixed top panel; available only for Finished sessions with a loaded, unacknowledged result |
| Acknowledge all | Top toolbar; review latest results of all current-source Finished sessions, including notes hidden by filters |
| Reverse acknowledgment | Mark as unread on the same viewer button; available for a known acknowledged result in any session state after loading ends |
| Continue in Codex | Open in Codex in the viewer's top panel or the first item in a real note's context menu |
| Reload history | Reload history in the viewer's top panel |
| Refresh source inventory | Toolbar refresh, Refresh Sessions in the menu, or Command + R |
| Change connection | Connection Settings, Command + comma, or the source menu in the sidebar |

**Find a session** matches a localized, case-insensitive substring of the session title. It does not search transcript text, folders, or project names. Search is transient; reopening starts with no title restriction while saved visibility choices remain. Changing search ends any temporary creation reveal.

Layer counts show source populations before filters. The source total counts the known inventory; canvas/project/review counts use the selected visible layer. Attention counts apply search/project choices but ignore state exclusions. **Acknowledge all** retains its source-wide Finished scope even while Stale or Inactive is selected. The footer also shows zoom. Search is transient and applies within the selected layer.

The note center at release determines the target project. Borders are unassigned space. The sidebar independently toggles attention states; clicking a visible project focuses its region without clearing filters. Titles and state text are exposed as accessibility elements with a press action. State is represented by text, icon, and color.

Tab and Shift + Tab cycle rendered items while the canvas has focus; Return or keypad Enter opens a note or zooms into a project. Escape cancels uncommitted note/region/resize/pan previews. Detailed note footers show a pending move first, otherwise result outcome/review status, otherwise the working folder's last component or a source label. Intermediate scales use compact title/state/activity text; very distant unassigned notes can show only their shape. A project's overview dot summarizes visible members in permission, input, running, finished, archived, unknown, then idle priority.

Real session-note context menus start with Open in Codex and omit the duplicate Open session action. Primary click and keyboard activation open the local viewer. Demo notes have no native Codex navigation target.

The session viewer displays messages and results newest first, opening at the top. Loading older pages appends them below the newer content. Acknowledge result, Open in Codex, Reload history, and pagination controls stay above the scrolling transcript; narrow viewers wrap the main actions into two rows. Acknowledge targets the newest loaded result and is enabled only while the session is Finished and history is not loading. It remains disabled in Running, Waiting for you, Permission required, Idle, Archived, and Unknown, or for an unloaded/already acknowledged result. The command rechecks the current state before saving, including when a new turn starts after the viewer rendered. A newer unviewed result offers View latest result without changing the acknowledgment target. History failures appear beside Reload history for retry.

Modern history requests at most twelve descending server turn summaries (`itemsView: summary`) and continues through `nextCursor` only after **Load older history**. Source-provided messages, plans, and terminal outcomes are displayed without eagerly fetching omitted full tool/item detail. Repeated clicks during loading and older-history actions after the cursor is exhausted send no duplicate request. Older pages leave the newest result and its acknowledgment target unchanged. The [performance report](history-loading-performance.md#server-side-reverse-pagination) distinguishes this summary-only contract from complete underlying item history and older-server compatibility.

History shows selectable user/assistant messages, plans, and terminal outcomes, omitting arbitrary tool payloads and hidden reasoning. Missing assistant response text uses the recorded error or an explicit no-response-text fallback. Empty successfully loaded history says No messages have been recorded yet. Older servers use legacy history with local paging; when that fails, an available exact local rollout must pass source-path and identity validation. Switching session/source prevents an older reply from replacing the current viewer.

Pipe reading, linear framing, and generic JSON decoding run on a dedicated serial worker. Each decoded value is handed to the UI before the worker continues, so replies cannot build an unbounded UI queue. Reads are at most 64 KiB and individual frames at most 64 MiB. Reconnect invalidates the old reader, and EOF delivers any final complete reply before disconnecting. These changes remove the reproduced quadratic scan; a giant visible text message and cold installed-server hydration have separate acceptance gates. Reopening still revalidates the latest page; revision-aware caching and legacy/local full-read removal remain future work.

**Acknowledge all** applies to every currently Finished session in the connected source, including notes hidden by search, attention, or project filters. It records only each session's latest known result at the moment of the click; no viewer or history request is required. Running, pending requests, Unknown, Archived, no-result sessions, and results discovered afterward are excluded. The button is disabled during refresh or when no eligible result/storage/connection exists. The batch is atomic: a storage failure leaves all prior acknowledgments and attention intact. Normal classification and layer filters apply afterward and can close the selected viewer.

For an acknowledged result the viewer's same button reads **Mark as unread**. It removes only that result's local review record and remains available in Idle, Running, request states, Unknown, and Archived after loading ends. If transcript history failed to load, the known acknowledged latest result can still be marked unread. A latest inactive result becomes Finished again; active work/requests, archives, and other results keep their normal priority. Both directions persist across restart and surface storage errors without optimistic UI changes. Select Stale to review an old acknowledged Idle session; marking its latest result unread moves it to Active Finished.

Opening or reloading the latest history can also resolve Unknown: if the newest raw turn is terminal and no newer work or pending request is known, the note and viewer become Finished for its unread result. This works with paged and legacy history even when the local rollout is unavailable. The viewer marks saved-history provenance; opening still does not acknowledge the result. Older pages, a cached Completed result alone, empty/unsupported latest evidence, and a completed turn followed by newer work cannot establish Finished. Source revision/file changes and live state take priority over a delayed history response. Normal refresh retains valid recovered evidence; explicit acknowledgment then returns the session to Idle and enables the selected age limit.

Unknown notes with cached terminal results and missing local history are rechecked automatically after the initial canvas appears. One background worker checks one session at a time, starting checks at least one second apart. Modern APIs return one latest turn; older APIs may require a full history response, whose transcript is discarded after checking state. Confirmed completion updates the note and counts without opening the viewer, acknowledging the result, or reloading the whole inventory. Active/requesting, archived/internal, no-result, and known later-local-work sessions are excluded. Unchanged source/file/result evidence is checked once per connection, including failures; changed evidence or reconnect permits another attempt, and manual Reload history remains available. Closing/disconnecting stops the queue. Viewer transcripts remain on demand.

Choose exactly one layer above Attention: Active, Stale, or Inactive. Selection, viewport, attention exclusions, and project exclusions persist per source and layer. Only selected-layer content contributes to drawing, project rows, overview, hit targets, accessibility, keyboard focus, and Fit to Content. Empty layers remain selected. **Show all in this layer** and Command + 1 clear search and selected-layer state/project exclusions without changing the shared idle cutoff or any other layer. Ordinary state changes never switch layers. A viewer closes when its session leaves the selected visible population; stale history replies and gestures cannot restore the old context.

**Rearrange** compacts only the selected layer's visible sessions. It creates a roughly square project block and a separate physical-card grid of unassigned sessions below it. Visible notes use Attention order, newest activity, then stable identity across rows. Project packing retains size ordering, source/sidebar tie-breaking, and no rotation.

The planner prefers the smallest longer side, then the smallest bounding area, and then a wider orientation for a complete tie. It tries a bounded set of project-block widths and reuses free spaces. This is a compact-layout heuristic, not a guarantee of minimum area or an exact square. Hidden members can enlarge their project, and fixed hidden geometry can shift either whole block downward while preserving its internal shape. The rectangle-packing core is O(P²) time and O(P) extra space for P projects; note sorting, hidden obstacles, and final membership/collision validation add their own costs.

Filtered current members of a participating project receive its displacement without internal reflow. Visible members avoid those footprints; filtered unassigned notes and projects with no visible current members stay fixed. All these constraints apply only within the selected layer. Other-layer geometry and dormant remembered placements/empty regions do not reserve space. Manual project dragging likewise carries only current members of that layer. Project interiors cannot overlap or nest within a layer, including filtered occupied regions.

Rearrangement is a local, explicit action with no Codex mutation or history request. It preserves pan/zoom, selection/history, source facts, review records, and filters, and persists the complete geometry before updating the canvas. A repeated click with unchanged input keeps the same coordinates. Status/activity/filter updates do not rearrange automatically. The button is disabled without visible notes, a connection/storage, or while refresh/creation/membership work is pending. Use Fit to Content separately if the arranged content is outside the current view.

**Archived** appears under **Attention** only on Inactive, immediately above **Unknown**. Fresh Inactive filters enable both states; migrated exclusions remain saved. Confirmed archived sessions show Archived on their note and in the viewer even when execution is unavailable or local history is missing. The checkbox shows/hides them independently of Unknown and without acknowledging their results. The former Hide archived sessions choice migrates to this checkbox; no separate archive toggle remains under Visibility.

**Hide Idle after** sets one per-source cutoff: Never (default), 15 minutes, 1 hour, 1 day, 1 week, or 1 month (30 days). Otherwise eligible Idle sessions at/past the cutoff belong to **Stale sessions**; Never leaves Stale empty. Execution, requests, unread results, and missing/future timestamps prevent age classification as Stale. **Archived** and **Unknown** always belong to **Inactive sessions**, regardless of age or cached unread evidence; the former Hide unknown toggle is removed. Active offers its five possible states, Stale offers Idle, and Inactive offers Archived then Unknown. Fresh layer filters enable all applicable states; migration retains previous exclusions. Time is reevaluated within 30 seconds.

Archive reviewed Idle sessions through **Archive session** in the note context menu or viewer. The action refreshes and rechecks eligibility before calling Codex and saves archive state only after confirmation. Check Archived to use **Unarchive session**. Restoration recalculates the session's state from current evidence, including Unknown or Finished, without acknowledging its result. Archived sessions cannot acknowledge results until restored to Finished. History, project membership, and remembered layer positions are retained; errors leave the note available. Archive is unavailable for active, uncertain, or unreviewed sessions. The demo simulates the same lifecycle within its own store.

Notes show source last activity in one largest unit: `15m ago`, `1h ago`, `1d ago`, capped at `1 month ago` for 30 days and older. Under one minute and future timestamps show `0m ago`; missing timestamps show Activity unavailable. The viewer includes relative activity and the exact local date/time. Viewing, acknowledging, refreshing, and archiving do not manufacture activity.

Zooming out hides individual project members and draws labels inside their original project regions. Names use a readable single line with tail truncation. If the region cannot fit a meaningful prefix plus an ellipsis, or a full line's height, it shows only its area without text or a session count. Counts and attention dots appear only when there is enough additional room. Regions and hit areas follow the viewport transform exactly: labels never move, enlarge, or rearrange projects to avoid crowding or viewport edges. Clicking a project area, including one without a label, zooms into its sessions; dragging it moves the project and its current member notes on that layer, including filtered members, without changing the viewport. The area and label preview that same movement before release. Escape cancels; Space + drag or a background drag pans the canvas. Closer zooms show compact session titles and states, then full note details. Selecting even a tall project opens at a readable zoom near its top.

## Source modes

Normal startup selects **Codex desktop**; `--demo` selects **Demo workspace**. The last source selection is not a startup preference. Connection Settings stages the executable, optional shared socket, and native URL template until **Connect** saves them in local preferences and reconnects; **Cancel** discards the form edits. Executable/socket paths accept a leading tilde. The default URL template is `codex://threads/{id}`; navigation requires `{id}`, a `codex` scheme, and a registered handler, and percent-encodes the exact session ID. A bad template or handler produces a settings/retry error.

Connection and manual **Refresh Sessions** perform discovery; connected sources also refresh every 12 seconds. Source notifications coalesce over 250 milliseconds, and refreshes never overlap. Inventory/history requests time out after 20 seconds; arbitrary server errors/stderr are not copied into the UI. Initial discovery shows progress, empty sources offer Connection settings and Explore demo, and connection status distinguishes saved-only operation from live desktop state. Inventory-process disconnect requires reconnecting through settings; the desktop feed reconnects independently.

The default **Codex desktop** mode combines saved-session discovery/history through the installed CLI with live observations from the desktop's existing local coordination socket. It prefers the desktop's bundled CLI for protocol compatibility. The observer follows revisioned conversation snapshots and patches; Running, input, approval, and completion changes update automatically. It never claims ownership, starts or resumes a turn, executes a tool, or answers a request. A history refresh cannot overwrite a newer live observation with `notLoaded`.

The observer reconnects automatically after desktop/socket loss. Live observations are cleared immediately on disconnect or a stream revision gap; a fresh snapshot restores them. Discovery checks identity-verified saved terminal evidence for unloaded sessions before opening their viewers: a terminal latest turn becomes Finished until acknowledged, then Idle. Current live state takes priority for non-archived sessions; confirmed archives display Archived. Discovery reads at most a 64 KiB identity header and 256 KiB tail per exact inventory-provided rollout, with revision/file caching; later work or incomplete evidence remains Unknown. Missing local files are explained in the viewer rather than treated as inactivity. The connection indicator and viewer distinguish live observations from saved state. This is a version-checked desktop compatibility adapter, not a public app-server socket: unsupported stream versions fail closed. It checks socket and peer ownership, bounds frames, ignores remote-host state, and never starts an IPC router or daemon.

Guardian reviews and other sub-agent sessions are excluded using source/parent metadata, including notes cached by earlier versions. Local projects and session assignments are read from the connected Codex home's `.codex-global-state.json`. Projectless sessions stay unassigned even when their working directory matches a project's folder. Backend null/different membership and old Canvas confirmations cannot override explicit desktop membership. Old confirmations still decode for storage compatibility but are discarded by synchronization. Remote-host exclusions apply; Canvas never rewrites the metadata file.

Existing-session project moves are currently disabled for real Codex connections, including the tested 0.164.0-alpha.11.1. A live test confirmed that `thread/metadata/update.projectId` changes backend metadata without changing the chat's desktop project; reading that same backend back is insufficient. Move-to-project menu items are disabled, and crossing a project boundary retains the confirmed project and position with an explanation before any source mutation. Moving a note within its current project and editing project geometry remain available. Changes made through Codex's own project menu synchronize into Canvas. An API-only desktop mutation channel remains an open integration gate; Accessibility/UI automation is excluded by the user's instruction.

The earlier server-version/user-agent gate and backend mutation implementation are historical evidence, superseded by the live desktop failure. Current `CodexSource` advertises no project-move capability and its assignment method rejects before sending any RPC. The desired API-only transition, independent desktop readback, execution-context preservation, atomic conflict protection, and durable pending-operation recovery remain acceptance work. Installed-server verification uses temporary config/SQLite homes with desktop observation disabled.

Desktop subscription echoes are ignored, repeated announcements from another observer are deduplicated, and socket writes run off the main thread. This prevents a following-announcement loop from freezing updates when several observers or windows share the desktop feed. Explicit archive/restore uses the source API separately from discovery. Real-source project writes are disabled.

**Shared Codex server** uses a configured/default control socket. This requires an already-reachable server and does not start or reconfigure a daemon. Current runtime flags are used only when that source can establish them.

Right-clicking a project area offers **New session in project…** at every zoom, with that project selected in the dialog. The real desktop source creates an empty durable session using the project's server identity and confirmed working roots, then automatically opens the exact session in Codex for the initial instruction. A blank name becomes **New session**. Without a project, the working folder is optional: leave it blank for a separate workspace under `~/Library/Application Support/Session Canvas/Workspaces`, or choose an existing folder. The creator and independent history verifier both exit before native opening. Creation starts no model turn and overrides no permission settings.

Same-layer creation in the confirmed context's project keeps valid clicked placement and pan/zoom; an occupied point uses the nearest free position on that layer. Creating from Stale or Inactive selects the confirmed session's derived layer and focuses its note inside the same actual project's destination region, without overwriting another layer's project bounds. An unexpectedly Unknown creation is revealed only in Inactive. Temporary reveal bypasses selected-layer filters only and leaves saved choices unchanged. Changing layers, search/visibility, or reconnecting ends it. Native creation still verifies durable history, releases ownership, opens Codex without a model turn, and retains submission errors in the dialog.

The server APIs are negotiated; older CLI versions and the unverified shared mode explain why creation is unavailable. A confirmed session remains on the canvas even while empty threads are absent from inventory, or naming/history verification/navigation fails. A verification warning prevents automatic native opening. An unconfirmed create is never automatically retried. See [integration-compatibility.md](integration-compatibility.md).

**Demo workspace** is a separate, persistently isolated sample with all interaction states, project regions, simulated creation, and confirmed project moves. The app labels it DEMO and never submits these actions to a model. Real-source membership changes stay disabled until an API can confirm the actual desktop transition.

Demo creation requires a prompt and accepts an optional title/project. A blank title uses the prompt's prefix; the local sample becomes Running and produces a simulated Completed result after about three seconds, still requiring explicit acknowledgment. Its source identity is `demo-v1`, and native Codex opening is unavailable. Desktop/shared connections identifying the same Codex home reuse that home's workspace and review state; a different home restores separate records. Switching saves outgoing state, closes its connection, clears viewer/reveal, and prevents old replies from entering the new workspace.

## Persistence and recovery

The app owns `~/Library/Application Support/Session Canvas/canvas.sqlite` and never directly opens or writes a Codex database. Source facts, project identities, and acknowledgments are shared, while each source stores three independent geometry/viewports/filter sets and selected layer. Search remains transient. Schema version 3 adds `layer_migration_backup`; the layered payload is version 1. The old unversioned workspace and visibility are converted atomically, with original raw payloads retained in backup records. Valid old note coordinates and project bounds are preserved in their derived layers, applicable state/project exclusions are copied, the cutoff is retained, and Active is selected. Reopening does not reseed layouts; unsupported newer payload versions are rejected.

To recover a failed migration, close the app and preserve a copy of this Canvas-owned database before retrying. Transaction failure leaves the original workspace readable. An intentional downgrade requires restoring the pre-migration workspace/visibility records from `layer_migration_backup` after closing the app; it discards layer edits made since migration and does not change Codex or acknowledgment records. Do not open a layered database in an older binary without restoring a compatible Canvas snapshot first.

Manual geometry saves commit before changing the canvas. A source-driven transition publishes a complete valid in-memory layout even if saving fails, retaining authoritative source facts and the previous durable snapshot; **Layout not saved → Retry save** retries it. Migration/load failures disable writes until reconnect succeeds. Returning sessions restore valid remembered project-relative positions or allocate free space inside the destination project, growing or translating that whole project when needed. Dormant records do not block current geometry.

Opening history does not change acknowledgment. Acknowledge commits the displayed result's identity before updating the note. A newer result remains unacknowledged even if an earlier one is acknowledged. Failed writes are shown as errors. A full application restart restores cached non-archived real observations as Unknown until refreshed; confirmed archives retain Archived. Incomplete inventory refreshes retain existing notes.

The application exits when its last window closes. It reconciles saved source data on the next launch; it does not install an autostart item, daemon, or menu-bar process. Connection settings are local preferences. Full transcript history is loaded on demand rather than copied into another complete conversation store.

## Implementation map

The [SDD function inventory](../openspec/changes/add-session-canvas/functional-coverage.md) maps every implemented area to requirements, source files, and existing verification entry points. The [source-connection contract](../openspec/changes/add-session-canvas/specs/source-connection/spec.md) covers connection preferences and lifecycle; the [verification report](../openspec/changes/add-session-canvas/verification.md#remaining-acceptance-gates) retains unfinished acceptance.

- `Sources/CanvasCore`: domain state, coordinate/region rules, source decoding, SQLite persistence.
- `Sources/SessionCanvas/NativeCanvasView.swift`: AppKit drawing, hit testing, gestures, context menus, keyboard navigation, accessibility.
- `Sources/SessionCanvas/CanvasOverview.swift`: fitting readable labels inside the original projected project regions.
- `Sources/SessionCanvas/ContentView.swift`: SwiftUI sidebar, viewer, connection and creation sheets.
- `Sources/SessionCanvas/SessionSource.swift`: real inventory/history adapters, confirmed empty-session creation, and isolated demo source.
- `Sources/SessionCanvas/DesktopRuntime.swift`: read-only desktop observation, revision reconciliation, bounded framing, and reconnect.
- `Sources/SessionCanvas/RPCConnection.swift`: bounded JSONL transport with request timeouts and no implicit approval responses.
- `Sources/SessionCanvas/RPCStreamReader.swift`: incremental per-frame bounds, serial off-UI decoding, and paced delivery for the JSONL transport.
- `Sources/CanvasCore/RolloutReader.swift`: read-only, identity-checked compatibility reader for source-provided local history paths.
- `Sources/CanvasCore/DesktopProjectCatalog.swift`: bounded read-only import of saved local projects and exact session assignments.
- `Tests/CanvasCoreTests`: attention/result races, geometry, wire compatibility, and durable source-isolated storage.
- `Tests/CanvasRuntimeTests`: opening/acknowledgment persistence, confirmation before project moves, and reconnect/stale-command behavior using the isolated demo source.

## Visual verification

The built app supports `--demo --storage PATH --capture IMAGE.png` to render its own native window, including the toolbar, into a PNG and exit. Add `--hide-sidebar` to verify the expanded canvas with its sidebar collapsed. It uses view-backed rendering, not a desktop screenshot of other applications. A normal run omits `--capture` and remains interactive.

Verified on the development Mac before the documentation audit: 60 passing core/runtime tests, release compilation, ad-hoc bundle signing, native demo and saved-canvas rendering, a point-in-time inventory of 392 user sessions with 1,069 internal sessions hidden, import of 18 projects with 101 assigned sessions, and identity-checked parsing of existing saved history. Native rendering checks cover readable project names at 42% and 25%, truncated names at 10%, and areas without text at 3% and 1%, including an 18-project distant overview. Geometry and event checks verify stable projected bounds and overview dragging with hidden members. Whole-line note text, composed visibility filters, source-isolated persistence, and hidden/empty project behavior are covered. Viewer/toolbar/sidebar presentation also has code and native-capture inspection, rather than a dedicated automated SwiftUI interaction suite.

The actual bundled server verifies empty-session creation and independent resume with the inventory client still connected, including a named project session, a projectless session with blank name/folder, and the ApplicationModel creation flow with Unknown hidden. A native keyboard-event test activates the SwiftUI submit button through Return and verifies viewer selection, exactly one creation, and the captured automatic navigation URL. Canvas interaction tests retain native mouse events. Existing user-created projectless test sessions were opened through internal desktop navigation and the actual `codex://threads` handler; each reached Idle with zero turns. Native capture verifies the fully visible focused note, success/filter notice, and retry controls. Earlier isolated 0.164.0-alpha.11.1 checks proved backend assignment/reassignment/removal only. The live 17:53 failure invalidated the claim that this establishes a desktop move; those actions are now disabled in the real adapter. Complete in-project automatic-opening acceptance, live-host project-move presentation, atomic external-move protection, and cross-restart recovery of uncertain operations remain gates. See the [OpenSpec correction/evidence matrix](../openspec/changes/add-session-canvas/verification.md) and [compatibility report](integration-compatibility.md).
