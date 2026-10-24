# Tasks

Updated against the implemented corrections through 2026-10-25. [verification.md](verification.md) maps each correction to its requirement and evidence. Checked tasks describe completed, bounded work; an unchecked parent can have verified subtasks without passing its full acceptance gate. The real desktop, isolated server, fixture, and demo evidence are distinguished explicitly. This change is not ready to archive while the remaining gates are open.

## 0. Native Mac foundation

- [x] 0.1 Deliver a SwiftUI/AppKit application, source-independent Swift core, and SQLite storage; verify a release build and an ad-hoc signed .app bundle.
- [x] 0.2 Verify the native rendering with an isolated demo window capture and run the Swift Testing core/runtime suites.
- [x] 0.3 Implement a read-only rollout compatibility reader; verify path/identity/partial-record cases in tests and actual saved-session parsing without printing transcript contents.

## 1. Prove the existing Codex integration

- [x] 1.1 Record target app/CLI versions and observed connection mechanisms; verify complete existing-session inventory, stable identities, and real saved projects in the compatibility report and opt-in source tests.
- [ ] 1.2 Demonstrate live observation of a desktop-started session through Running, Waiting for you, Permission required, and terminal outcomes; verify no competing execution or accidental permission response occurs.
  - [x] 1.2.1 Verify the active desktop's actual runtime feed reaches the application; a separate reader's `notLoaded` does not erase Running.
  - [x] 1.2.2 Verify request/completion transitions, disconnect/reconnect, fragmented frames, and invalid-patch rejection with a local desktop-protocol fixture.
  - [ ] 1.2.3 Complete the request → native response → completion workflow on the live desktop; fixture transitions alone do not pass this gate.
- [ ] 1.3 Demonstrate reading stable result identities and paginated history after reconnect; verify stale/unloaded observations cannot be mistaken for completion.
  - [x] 1.3.1 Implement paginated/legacy/local read fallbacks and verify identity, terminal-result decoding, path restrictions, and incomplete-record handling.
  - [ ] 1.3.2 Complete the live-desktop multipage/reconnect acceptance; the rollout fallback does not synthesize separately referenced fork ancestry.
- [ ] 1.4 Demonstrate actual project listing, conditional assignment/reassignment/removal, and external-change detection; verify session working directory, checkout, and active turn remain unchanged for allowed moves.
  - [x] 1.4.1 Import actual saved projects and explicit assignments; verify renames, explicit unassignment, and source-qualified server project mapping.
  - [ ] 1.4.2 Enable and verify conditional moves of existing real sessions; current real-source move actions remain unavailable.
- [ ] 1.5 Demonstrate creation in the same source and native opening of the returned session; verify a possibly applied create request can be reconciled without duplicate creation.
  - [x] 1.5.1 Verify empty durable creation and independent resume while the inventory client remains connected, including a named project session and blank-name/folder projectless session; preserve saved identity/name/project and zero turns using the actual bundled server in an isolated home.
  - [ ] 1.5.2 Complete in-project automatic-opening acceptance and full lost-response/restart recovery; isolated tests do not prove every live-desktop context.
  - [x] 1.5.3 Read and open existing user-created Canvas test sessions through internal desktop navigation and the actual codex://threads URL handler; verify each same identity reaches Idle with zero turns. No additional live-store chat or model turn was created.
- [ ] 1.6 Deliver the integration-gate decision in docs/integration-compatibility.md, including failed capabilities and supported versions; verify all six demonstrations in docs/delivery-options.md pass before selecting the local delivery transport, or record the stopped track and required scope/delivery decision.

## 2. Build the source boundary and domain projection

- [x] 2.1 Implement source-qualified identities and complete inventory discovery; verify duplicate observations, same-name sessions, external membership placement, and saved project renames with core/import tests and actual inventory checks.
- [ ] 2.2 Normalize execution, pending requests, turn results, and source revisions; verify the session-attention priority rules, multiple requests, late events, and a later turn starting before an earlier event arrives.
  - [x] 2.2.1 Verify attention priority, current requests, stable terminal identities, canonical desktop turn history, and resistance to invalid/stale observations in core/runtime fixtures.
  - [ ] 2.2.2 Complete live-host coverage of all ordering/request cases and separate last-known execution presentation while Unknown.
- [ ] 2.3 Implement reconnect/freshness reconciliation and archive/removal handling; verify disconnects and missing pages retain notes as Unknown rather than creating Finished results or deleting notes.
  - [x] 2.3.1 Reconnect the desktop observer automatically, clear lost live evidence, retain inventory on failures, and reject obsolete-generation completions.
  - [ ] 2.3.2 Complete archive/restore and incomplete-inventory acceptance across restart against the real host.
- [x] 2.4 Document supported adapter versions and integration limitations beside its contract; verify every declared capability maps to an observed mechanism from the compatibility report.
- [x] 2.5 Exclude Guardian/internal sub-agent sessions using structured source/parent metadata, remove cached internal notes, and preserve ordinary user sessions even when their title is Guardian review.

## 3. Add durable canvas state and acknowledgment

- [ ] 3.1 Implement versioned local persistence for placements, region geometry, viewport, source evidence, and pending operations; verify restart restoration and visible save failure behavior.
  - [x] 3.1.1 Persist workspace geometry/viewport, the narrow session/result cache, and acknowledgments in the canvas-owned database; verify source isolation and storage failures.
  - [ ] 3.1.2 Persist pending mutation/create correlation and recover uncertain outcomes across application restart; current in-memory guards are insufficient for this acceptance.
- [x] 3.2 Implement explicit per-user/per-result acknowledgment; verify opening alone has no effect, repeat acknowledgment is harmless, and failed persistence leaves the result unacknowledged.
- [x] 3.3 Verify that a newer result cannot retarget acknowledgment of the displayed identity, and reject acknowledgment if a new turn or request becomes active before the action; preserve prior acknowledgments and current attention.
- [x] 3.4 Add schema-version-2 per-source attention/project visibility without resetting existing workspace or acknowledgments; verify visibility restoration and source isolation. Search remains transient.

## 4. Build the canvas workspace

- [x] 4.1 Implement pan, focal zoom, Fit to content, and world-coordinate layout; verify viewport round trips, focal anchoring, stable project projection, and populated native canvas captures.
- [x] 4.2 Render labeled/icon states, outcome text, full-title accessibility, keyboard opening, and the sidebar legend; verify session text uses complete lines at closer zooms.
- [x] 4.3 Implement local note dragging, cancellation, click suppression, and collision-aware discovery placement; verify stable unrelated placements and rejected stale/invalid edits with core/runtime checks.
- [x] 4.4 Document controls and state meanings in the native guide; record representative populated canvas rendering and the source/domain checks in verification.md.
- [x] 4.5 Clip all canvas drawing and shadows at viewport edges; compare native bitmaps with notes crossing the top and bottom boundaries.
- [x] 4.6 Render project summaries in the original projected regions without enlargement, reflow, displacement, or viewport-edge clamping; verify geometry while zooming/panning.
- [x] 4.7 Truncate readable project names only when meaningful text and whole line height fit; otherwise omit all text/counts. Verify 42%, 25%, 10%, 3%, and 1% zoom with geometry, bitmap, and OCR checks.
- [x] 4.8 Allow overview-area dragging even without text; move all members including hidden notes, preserve viewport, and retain click/zoom, Escape, Space/pan, and collision behavior.
- [x] 4.9 Compose search, independent attention visibility, and individually hidden projects; omit projects without visible sessions from rendering, accessibility, and fit bounds; verify restore and empty-view behavior.
- [x] 4.10 Move New Session/Fit/Full Screen to the top toolbar, remove the workspace heading/tagline/header panel, and use the native toggleable sidebar with Shift + Command + S; verify native window captures and document controls.

## 5. Build project regions and membership commands

- [x] 5.1 Implement non-overlapping regions and world-coordinate center/boundary rules; verify borders, partial overlaps, zoom invariance, and invisible-region exclusion in core/runtime tests.
- [ ] 5.2 Implement confirmed assignment/reassignment/removal plus keyboard alternatives; verify source rejection restores confirmed placement and running-session restrictions are reported.
  - [x] 5.2.1 Exercise confirmed moves and preserved execution with the isolated demo; keep real-source move controls disabled and reject unsupported cross-boundary drops.
- [ ] 5.3 Implement conditional membership changes, pending-operation recovery, and external-change reconciliation; verify a racing external move wins over a stale drop and an uncertain mutation is not blindly retried.
- [ ] 5.4 Implement region movement/resizing and source project removal; verify members move together, invalid geometry edits are rejected, and no geometry edit mutates membership.
  - [x] 5.4.1 Verify local region movement/resizing, member retention, hidden-member movement, collision rejection, and no geometry-driven reassignment.
  - [ ] 5.4.2 Complete live source-project-removal acceptance and retain or relocate affected sessions from authoritative evidence.

## 6. Build the viewer and session actions

- [x] 6.1 Implement the same-session read-only viewer, pagination and fallback errors, outcome rendering, and loaded-result acknowledgment guard; record native viewer inspection and core/runtime history/result checks.
- [x] 6.2 Add explicit Acknowledge, already-acknowledged indication, and View latest; verify a newer result cannot retarget the loaded action or be acknowledged without loading.
- [ ] 6.3 Add Open in Codex using the verified native mechanism; verify exact identity, retryable dispatch errors, and no implicit acknowledgment or execution.
  - [x] 6.3.1 Dispatch the exact session ID through a validated codex URL and registered handler; surface failures while preserving result/execution state. Full native route acceptance remains open.
- [x] 6.4 Implement New session on project areas/background and its keyboard equivalent. Preselect project/location, validate server identity/roots, create an empty real session, and delegate the instruction to Codex; verify native menu events at 100%, 42%, and 3% and invalid-project/prompt rejection.
- [ ] 6.5 Implement durable create correlation and cross-restart recovery; the desktop flow creates no initial turn, so initial-instruction submission/retry is outside the canvas.
  - [x] 6.5.1 Prevent duplicate submissions, block retries after unconfirmed creation, retain confirmed empty notes omitted from inventory, and preserve one session on naming failure.
  - [ ] 6.5.2 Fault-inject a lost reply/late notification and verify exact recovery, then extend it across restart with durable operation state.
- [x] 6.6 Document installation, connection, viewer limitations, and recovery steps; verify release packaging/signature, real-source discovery, and unavailable-capability messages.
- [x] 6.7 Show messages newest first, keep main actions/pagination fixed above history, wrap actions in narrow viewers, and keep older pages below newer entries; record code/native-view inspection separately from automated history/acknowledgment checks.
- [x] 6.8 Remove Open session from note context menus and put Open in Codex first for real sessions; inspect menu construction and preserve primary-click/keyboard opening of the local viewer and demo navigation limits.
- [x] 6.9 Enable and accept Acknowledge only for Finished sessions through a shared UI/command predicate; verify loaded older results cannot be acknowledged in Running, Waiting, Permission required, Idle, or Unknown, no storage writes occur, and returning to Finished enables the action again.
- [x] 6.10 Make names and projectless working folders optional with explained defaults; materialize saved history, create and verify in separate short-lived processes, await their exit, and preserve Open in Codex for continuation/retry. Reproduce the competing-owner failure before the fix, verify independent resume on the actual bundled server afterward, and reject invalid explicit folders before creation.
- [x] 6.11 Reveal the latest created session despite Unknown/search/project filters without altering saved choices; open its viewer, explain the exception and empty-session list omission, and show submission errors inside the dialog. Verify the previously failing ApplicationModel path, refresh, Apply filters, explicit/fallback detail focus, and actual SwiftUI submit-button mouse events.
- [x] 6.12 Automatically open the exact verified desktop session after ownership release; retain the note/viewer for return and manual retry. Verify one captured native URL per creation in model/native-button/actual-source tests, and suppress automatic navigation on verification warnings.
- [x] 6.13 Preserve valid clicked placement and viewport pan/zoom on creation and viewer resize. Reproduce the previous unconditional autofocus and verify native projectless context-menu creation at 100%, 78%, 42%, and 3% zoom; the remaining collision fallback is corrected in 6.14.
- [x] 6.14 Replace origin-grid fallback for occupied creation points with the nearest valid placement, including hidden-note collisions and membership boundaries. Preserve pan/zoom for creation in the context's project, and verify native context-menu events, refresh, and SQLite restoration after restart.

## 7. Verify the complete workflow

- [ ] 7.1 Exercise existing-session discovery → running → request → native response → terminal result → viewer → explicit acknowledgment; verify the same session identity and correct note state throughout.
- [ ] 7.2 Exercise assign → reassign → unassign and an external project move during a drag; verify actual Codex membership and preserved execution context after each step.
- [ ] 7.3 Exercise create → lost response → reconciliation → restart; verify one source session/note and restored layout/acknowledgment.
- [ ] 7.4 Run the implementation's selected checks and openspec validate add-session-canvas --strict; verify every requirement has corresponding implementation evidence before considering the change implemented.
  - [x] 7.4.1 Record the implementation regression run: 28 core + 43 runtime tests passed, including nearest placement for visible/hidden collisions, refresh/restart retention, click/viewport preservation, filtered creation reveal, native submit-button events, inline failures, captured automatic native navigation, and independent actual-server resume; opt-in installed-source checks, release build, bundle signature, and strict OpenSpec validation passed.
  - [x] 7.4.2 Reconcile all conversation corrections across proposal/design/specs/tasks, add their evidence matrix, and validate local document links and OpenSpec structure.
  - [ ] 7.4.3 Close the remaining gates above before declaring the full change implemented or archiving it.

## 8. Reusable local verification permission

- [x] 8.1 Add the bounded build/test/preview launcher with local caches, explicit installed-source opt-in, isolated preview storage, validated outputs, and fresh-capture failure checks; verify its argument/output boundary.
- [x] 8.2 Install the user-authorized absolute launcher-prefix rule without changing unrelated permissions; verify differing filters, session IDs, and output paths match and unrelated commands do not.
- [x] 8.3 Run the launcher against actual tests, a signed app build, and native captures; inspect a new PNG and record evidence in verification.md.
- [x] 8.4 Document the stable direct command for future Codex chats and synchronize the local-verification contract, guide, and strict validation.
- [x] 8.5 Add the general launcher prefix to the main default.rules allow list after the repeated-prompt report; verify the exact reported command and changed preview parameters against that file, run the targeted regression, and document that existing chats need startup reload. File matching alone does not prove prompt-free execution.

## Workflow follow-up

- Review the implementation and its integration evidence before archiving this proposed change into main specifications.
- An optional future in-app plugin shell requires its own target-host compatibility check and must preserve the shared behavior and existing canvas state.
