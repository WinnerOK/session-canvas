# Tasks

Checkboxes track verified implementation progress. Contract: [session-layers](specs/session-layers/spec.md); approach: [design.md](design.md); acceptance matrix: [verification.md](verification.md).

## 1. Layer classification and domain contract

- [x] 1.1 Add stable layer identity and a pure classifier in CanvasCore after note-state derivation; verify disjoint and exhaustive Active/Stale/Inactive populations across all seven note states, archive priority, and Unknown with cached unread evidence.
- [x] 1.2 Separate the shared Idle cutoff from rendering exclusions and remove Unknown age classification; verify exact cutoff boundaries for every interval, Never, missing/future timestamps, and execution/request/unread-result protections with a supplied clock.
- [x] 1.3 Add canonical Canvas layer/Active/Stale/Inactive definitions to `GLOSSARY.md` and update `docs/domain-model.md` with classification and shared membership; verify terminology and the documented table match classifier cases.

## 2. Layered storage and legacy migration

- [x] 2.1 Introduce a versioned layered workspace/preferences payload with shared sessions/projects, independent geometry/viewports/filters, selected layer, and remembered membership-relative placements; verify round trips retain three different bounds for the same project and keep sources isolated.
- [x] 2.2 Implement atomic legacy migration and original-payload backups in Canvas-owned SQLite, retaining applicable exclusions/cutoff and acknowledgments; verify temporary legacy databases preserve valid coordinates, select Active, ignore legacy Hide unknown, and do not reseed after reopening.
- [x] 2.3 Add migration/save failure recovery and unknown-version rejection; verify injected transaction failures preserve original records, repeated migration is safe, unsupported versions are not flattened, and source-driven unsaved state is explicit and retryable.
- [x] 2.4 Document the payload transition and pre-migration recovery limits in `docs/native-application.md`; verify recovery instructions affect Canvas records only and do not promise preservation of edits made after migration during downgrade.

## 3. Layer-scoped geometry and transition placement

- [x] 3.1 Refactor region validation, project hit targets, vacant placement, and manual move/resize to consume current occupants from one explicit layer; verify the reported Active-over-Inactive-coordinate move succeeds while visible/filtered same-layer region overlaps and nonmember enclosure remain rejected.
- [x] 3.2 Distinguish dormant remembered positions/empty regions from current hidden occupants; verify departed coordinates are reusable, current filtered notes remain obstacles, and moving a project carries only current members on that layer.
- [x] 3.3 Implement destination placement from valid remembered project-relative offsets with allocation/growth/whole-project translation fallback; verify first arrivals, moved/resized regions, reused slots, full/blocked regions, unassigned sessions, simultaneous arrivals, and obsolete project offsets without altering unrelated projects or other layers.
- [x] 3.4 Document independent geometry and destination fallback in `docs/domain-model.md`; verify its invariants match the geometry/placement regression cases and preserve actual source membership.

## 4. Runtime reclassification and race handling

- [x] 4.1 Route discovery, refresh, incremental source/history recovery, archive confirmation, acknowledgment/unread/bulk actions, timeout changes, and 30-second clock ticks through one transition coordinator; verify Archived to Stale to Active, Unknown to Finished, and Finished acknowledgment to old Idle without source assignment calls.
- [x] 4.2 Reconcile authoritative external project changes and invalidate obsolete remembered membership across layers; verify an Inactive A-to-B change returns to B on Active and does not revive A after restart or delayed observations.
- [x] 4.3 Capture source/layer/geometry generation in AppKit gestures and reject obsolete commits; verify layer switching, reclassification, and destination growth during note/region/resize gestures cannot write stale coordinates or trigger source membership mutations.
- [x] 4.4 Preserve selected layer/viewports during automatic transitions and close viewers that leave the visible population; verify delayed history, source reconnects, and save callbacks cannot reopen stale selection or overwrite another layer.
- [x] 4.5 Update runtime/state-transition sections in `docs/native-application.md`; verify automatic transitions, explicit creation navigation, and save-error behavior agree with their integration tests.

## 5. Exclusive navigation, filters, counts, and creation

- [x] 5.1 Add the accessible single-choice sidebar selector with unfiltered population counts and source-isolated selection restoration; verify exactly one layer contributes notes, project rows, drawing, hit targets, keyboard/accessibility items, and fit bounds, including empty layers and distant zoom.
- [x] 5.2 Limit state rows to the selected layer, persist state/project exclusions independently, remove Hide unknown, explain the shared cutoff, and replace reset labels with Show all in this layer; verify search/reset/Command + 1 never combine layers or reset the cutoff/other layers, and migrated hidden Inactive states can be revealed.
- [x] 5.3 Make visible/attention/project/review counters layer scoped while retaining the source total and source-wide Finished bulk action; verify filtering leaves layer counts unchanged and bulk acknowledgment from Inactive excludes Unknown/Archived and reclassifies only newly eligible Idle sessions.
- [x] 5.4 Route creation from the captured origin layer/project/location into the confirmed session's derived layer, switching only for explicit reveal when needed; verify Inactive-project creation lands in the same Active project, same-layer clicked placement/pan/zoom remain stable, and an unexpectedly Unknown creation reveals only Inactive without starting a turn.
- [x] 5.5 Update controls, counts, creation, and empty-state guidance in `README.md` and `docs/native-application.md`; verify every documented action has corresponding fixture/native coverage and current labels match the app.

## 6. Layer-scoped Rearrange and semantic zoom

- [x] 6.1 Restrict Rearrange input and fixed/carried obstacles to the selected layer's current occupants; verify same-layer filtered offsets, deterministic compact packing and ordering, save-before-apply, unchanged other-layer geometry, unchanged viewport, and reusable dormant coordinates.
- [x] 6.2 Route overview/detailed drawing, focus, Fit to Content, and accessibility through selected-layer bounds; extend semantic-zoom/native fixture tests at detail and distant scales to verify independent project sizes/counts/attention and absence of cross-layer targets.
- [x] 6.3 Update Rearrange/overview guidance in `README.md` and `docs/native-application.md`; verify its hidden-member and obstacle scope agrees with the revised tests.

## 7. SDD reconciliation and integration acceptance

- [x] 7.1 Reconcile the baseline `add-session-canvas` specifications, proposal/design/tasks, verification mappings, functional inventory, and `openspec/config.yaml` using the supersession table in this change's design; verify no contract still requires mixed-layer geometry, Unknown age hiding, or cross-layer creation reveal, and retain unrelated open desktop gates and historical evidence.
- [x] 7.2 Run the full offline suite through `python3 /Users/d-manakovskiy/personal/session-canvas/scripts/verify-local.py test` and build through `python3 /Users/d-manakovskiy/personal/session-canvas/scripts/verify-local.py build`; record actual executed/skipped results in verification, with desktop observation disabled.
- [x] 7.3 Use the demo preview launcher and targeted native fixture events to verify all three exclusive layers, independent region bounds, the original blocked-move regression, and cross-layer creation at detail and overview scales; inspect newly written PNGs and record capture paths/results without live-desktop observation.
- [x] 7.4 Run `openspec validate --all --strict`, `git diff --check`, and affected local Markdown path/heading checks; update this change's verification matrix with actual evidence, leaving unexecuted or failed acceptance gates open.
