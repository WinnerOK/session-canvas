# Tasks

Native UI/domain/storage implementation is present. The full existing-desktop integration gate has not passed; unsupported source operations stay disabled. Checked items have concrete implementation/verification evidence. Unchecked items include partially implemented work whose full acceptance conditions still require a live host interface or further verification.

## 0. Native Mac foundation

- [x] 0.1 Deliver a SwiftUI/AppKit application, source-independent Swift core, and SQLite storage; verify a release build and an ad-hoc signed .app bundle.
- [x] 0.2 Verify the native rendering with an isolated demo window capture and run the Swift Testing core/runtime suites.
- [x] 0.3 Implement a read-only rollout compatibility reader; verify path/identity/partial-record cases in tests and actual saved-session parsing without printing transcript contents.

## 1. Prove the existing Codex integration

- [ ] 1.1 Record a reproducible compatibility report with target app/CLI versions and the selected connection mechanism; verify an already-existing desktop session is discovered with the same identity across all inventory pages.
- [ ] 1.2 Demonstrate live observation of a desktop-started session through Running, Waiting for you, Permission required, and terminal outcomes; verify no competing execution or accidental permission response occurs.
- [ ] 1.3 Demonstrate reading stable result identities and paginated history after reconnect; verify stale/unloaded observations cannot be mistaken for completion.
- [ ] 1.4 Demonstrate actual project listing, conditional assignment/reassignment/removal, and external-change detection; verify session working directory, checkout, and active turn remain unchanged for allowed moves.
- [ ] 1.5 Demonstrate creation in the same source and native opening of the returned session; verify a possibly applied create request can be reconciled without duplicate creation.
- [ ] 1.6 Deliver the integration-gate decision in docs/integration-compatibility.md, including failed capabilities and supported versions; verify all six demonstrations in docs/delivery-options.md pass before selecting the local delivery transport, or record the stopped track and required scope/delivery decision.

## 2. Build the source boundary and domain projection

- [ ] 2.1 Implement source-qualified session/project identities, complete inventory discovery, and the verified adapter; verify fixtures cover pagination, same-name sessions, renames, and repeat observations.
- [ ] 2.2 Normalize execution, pending requests, turn results, and source revisions; verify the session-attention priority rules, multiple requests, late events, and a later turn starting before an earlier event arrives.
- [ ] 2.3 Implement reconnect/freshness reconciliation and archive/removal handling; verify disconnects and missing pages retain notes as Unknown rather than creating Finished results or deleting notes.
- [x] 2.4 Document supported adapter versions and integration limitations beside its contract; verify every declared capability maps to an observed mechanism from the compatibility report.

## 3. Add durable canvas state and acknowledgment

- [ ] 3.1 Implement versioned local persistence for placements, region geometry, viewport, source evidence, and pending operations; verify restart restoration and visible save failure behavior.
- [x] 3.2 Implement explicit per-user/per-result acknowledgment; verify opening alone has no effect, repeat acknowledgment is harmless, and failed persistence leaves the result unacknowledged.
- [x] 3.3 Verify acknowledgment race scenarios with result B arriving while A is displayed and with a new turn already active; assert only the displayed identity is acknowledged and current requests/execution remain visible.

## 4. Build the canvas workspace

- [ ] 4.1 Implement pan, focal zoom, Fit to content, and canvas-coordinate layout; verify notes do not move when the viewport changes and off-screen content is recoverable.
- [ ] 4.2 Render session notes with current title, labeled/icon states, outcome labels, full-title access, and a state legend; verify keyboard opening and understanding without color.
- [ ] 4.3 Implement note dragging, cancellation, click suppression, and collision-aware discovery placement; verify intra-project moves remain local and source state updates preserve positions.
- [ ] 4.4 Document canvas controls and state meanings; verify the documented controls work against a representative populated canvas with off-screen notes and duplicate titles.

## 5. Build project regions and membership commands

- [ ] 5.1 Implement non-overlapping regions, center-based drop preview/commit, and boundary behavior; verify the same target at multiple zoom levels and with partial note overlap.
- [ ] 5.2 Implement confirmed assignment/reassignment/removal plus keyboard alternatives; verify source rejection restores confirmed placement and running-session restrictions are reported.
- [ ] 5.3 Implement conditional membership changes, pending-operation recovery, and external-change reconciliation; verify a racing external move wins over a stale drop and an uncertain mutation is not blindly retried.
- [ ] 5.4 Implement region movement/resizing and source project removal; verify members move together, invalid geometry edits are rejected, and no geometry edit mutates membership.

## 6. Build the viewer and session actions

- [ ] 6.1 Implement the read-only same-session viewer with paginated history and terminal outcome rendering; verify loading errors cannot expose acknowledgment for unloaded content and closing restores the viewport.
- [ ] 6.2 Add explicit Acknowledge, already-acknowledged indication, and View latest; verify a newer result does not silently retarget the displayed action.
- [ ] 6.3 Add Open in Codex using the verified native mechanism; verify exact identity, retryable dispatch errors, and no implicit acknowledgment or execution.
- [ ] 6.4 Implement contextual New session and its keyboard equivalent with project/location capture, instruction validation, and source execution-context selection; verify cancellation, empty instructions, and removed-project races.
- [ ] 6.5 Implement durable create correlation and recovery for both creation and initial-instruction submission; verify response loss does not cause duplicate creation and turn-submission failure retains the already-created note.
- [ ] 6.6 Document installation, connection, viewer limitations, and recovery steps; verify a clean local launch uses the existing source and exposes actionable errors for unavailable capabilities.

## 7. Verify the complete workflow

- [ ] 7.1 Exercise existing-session discovery → running → request → native response → terminal result → viewer → explicit acknowledgment; verify the same session identity and correct note state throughout.
- [ ] 7.2 Exercise assign → reassign → unassign and an external project move during a drag; verify actual Codex membership and preserved execution context after each step.
- [ ] 7.3 Exercise create → lost response → reconciliation → restart; verify one source session/note and restored layout/acknowledgment.
- [ ] 7.4 Run the implementation's selected checks and openspec validate add-session-canvas --strict; verify every requirement has corresponding implementation evidence before considering the change implemented.

## Workflow follow-up

- Review the implementation and its integration evidence before archiving this proposed change into main specifications.
- An optional future in-app plugin shell requires its own target-host compatibility check and must preserve the shared behavior and existing canvas state.
