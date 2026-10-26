# Verification

## Issue #11 follow-up: anchored downward growth, 2026-10-26

The [downward-growth correction](../add-session-canvas/verification.md#26-anchored-downward-growth-issue-11-2026-10-26) supersedes the crowded-destination translation described in the original evidence below. The destination now retains its origin, width, and current notes, grows downward, and pushes only blocking same-layer projects/cards. The updated crowded-return test, eight new growth-core cases, and two runtime cases passed in ordinary fixture verification, covering filtered/protruding obstacles, inactive/dormant isolation, stable refresh/reopening, and whole-layout save failure/retry. Both native fixture captures were inspected. No live source was used; unrelated integration gates remain open.

## Scope and result

Implemented the three exclusive layers with independent project geometry, note positions, viewport, filters, automatic same-project transitions, versioned storage/migration, layer-scoped canvas operations, source-wide review actions, and classified creation reveal.

Verification used offline source fixtures, temporary Canvas databases, and a separate demo capture database. No installed-source check, live desktop observer, real Codex membership mutation, model turn, release publication, or PR merge was performed. Unrelated baseline integration gates remain open.

The user supplied layer definitions, same-layer non-overlap, independent project bounds, exclusive display, and return-to-project behavior. Additional defaults are recorded in [design.md](design.md).

## Request-to-requirement coverage

All requirements below are in the [session-layers specification](specs/session-layers/spec.md).

| Request or affected behavior | Requirement | Executed fixture coverage | Status |
| --- | --- | --- | --- |
| Three layers with separate lifecycle populations | Every session has one derived layer; Idle age routes sessions to Stale | Pure classifier cases covering every note state, exact cutoffs, Never, timestamp errors, unread/request/execution protection, and Inactive precedence | Passed |
| Hidden Archived/Unknown must not block moving current projects | Project geometry is independent per layer; Spatial operations use current layer occupants | Active region move/resize over coordinates occupied in Inactive succeeds; same-layer collisions including filtered regions are rejected | Passed |
| Same project can have different bounds on different layers | Project geometry is independent per layer; Layer layouts and preferences survive reopening | Three independent bounds and viewports for one stable project identity, before/after SQLite restart | Passed |
| Never show multiple layers at once | Exactly one layer is selected; Visibility controls stay within a layer | Native draw/hit-test/focus/accessibility/fit assertions at detail and overview zoom; reset cannot combine layers | Passed |
| Archived to Stale and Stale to Active preserve the project | Transitions preserve actual project membership | Fixture archive/restore/activity sequence, same identity/project/acknowledgment, zero assignment or execution calls | Passed |
| A returning session must fit its project's destination layout | Destination placement restores valid spatial context | Valid offset restoration after destination project movement; reused slot, resized/full region, blocked growth, first arrival, and unassigned fallback | Passed |
| Departed notes must not create another invisible obstacle | Spatial operations use current layer occupants | Reuse departed slots/empty regions while retained layout memory stays available | Passed |
| Recover Unknown and reflect review/age/source events | Automatic transitions preserve layer navigation; Transitions preserve actual project membership | Background history recovery, acknowledgment/unread/bulk transitions, clock/timeout changes, external project change, and reconnect tests | Passed |
| Gestures/viewers must not target an obsolete layer | Automatic transitions preserve layer navigation | Layer switch/reclassification during drag/resize, stale history reply, and delayed save callback regressions | Passed |
| Existing visibility, counts, and bulk-review behavior need clear scopes | Visibility controls stay within a layer; Counters explain layer and action scope | Per-layer filters, unfiltered selector counts, source total, and source-wide atomic Finished acknowledgment from Inactive | Passed |
| Context creation must preserve project identity without a mixed view | Creation reveals one classified layer | Inactive A creation reveals Active A only; same-layer clicked location and viewport; unexpectedly Unknown creation reveals Inactive only | Passed |
| Existing saved workspaces must survive the change | Existing single-layout workspaces migrate safely; Layer layouts and preferences survive reopening | Temporary legacy payloads, original-coordinate preservation, state/project preference conversion, source isolation, rollback/failure, repeat loading, and unknown-version rejection | Passed |
| Existing compact layout and semantic zoom must remain usable | Rearrange and overview remain layer scoped | Revised core/runtime Rearrange and semantic-zoom cases with cross-layer coordinates, hidden current members, independent geometry, and deterministic packing | Passed |

## Verified regression entry points

- Core classification/storage/geometry: [CanvasCoreTests](../../../Tests/CanvasCoreTests/CanvasCoreTests.swift), [SessionLifecycleTests](../../../Tests/CanvasCoreTests/SessionLifecycleTests.swift), and [CanvasRearrangerTests](../../../Tests/CanvasCoreTests/CanvasRearrangerTests.swift); focused additions are [SessionLayerTests](../../../Tests/CanvasCoreTests/SessionLayerTests.swift) and [LayerInteractionTests](../../../Tests/CanvasRuntimeTests/LayerInteractionTests.swift).
- Runtime visibility and transitions: [CanvasVisibilityTests](../../../Tests/CanvasRuntimeTests/CanvasVisibilityTests.swift), [LiveStateTests](../../../Tests/CanvasRuntimeTests/LiveStateTests.swift), [ProjectMembershipTests](../../../Tests/CanvasRuntimeTests/ProjectMembershipTests.swift), and [AcknowledgmentActionsTests](../../../Tests/CanvasRuntimeTests/AcknowledgmentActionsTests.swift).
- Native interactions and regression integration: [ProjectCreationTests](../../../Tests/CanvasRuntimeTests/ProjectCreationTests.swift), [SemanticZoomTests](../../../Tests/CanvasRuntimeTests/SemanticZoomTests.swift), and [RearrangeTests](../../../Tests/CanvasRuntimeTests/RearrangeTests.swift).
- Execute code checks through the [authorized launcher](../../../docs/native-application.md#codex-verification-launcher), starting with offline fixtures and demo data. Live desktop checks require separate authorization for the specific run and are not an acceptance dependency of this feature.

## Executed verification

- Full offline launcher `python3 /Users/d-manakovskiy/personal/session-canvas/scripts/verify-local.py test --jobs 2` passed. Swift Testing reported 56 core tests and 85 runtime tests; five installed/live-source opt-in checks were skipped (136 executed named tests, plus parameterized cases).
- After a final visibility-save indicator correction, `test --filter 'LayerInteractionTests|CanvasVisibilityTests' --jobs 2` passed all 17 tests, including save failure/retry, the nine note/region/resize stale-context cases, and project dragging at 100%, 42%, and 3%.
- `python3 -m unittest discover -s scripts/tests -v` passed all 18 tooling tests, including single-layer preview parsing and rejection of a combined-layer capture.
- `python3 /Users/d-manakovskiy/personal/session-canvas/scripts/verify-local.py build --jobs 2` passed and wrote the signed `dist/Session Canvas.app`. The final build includes the last indicator correction.
- Initial broad runs exposed obsolete shared-layout/Unknown fixtures, a test-only optional-value compilation error, and exact floating-point comparison at distant zoom. Those were corrected before the passing runs above.
- Layer tests cover original-coordinate and filter migration, original raw backup retention, transaction rollback, source isolation, unknown-version rejection, repeated loading, crowded destination growth/translation, reused slots, project-relative restoration, external membership changes, and dormant geometry.
- Integration tests cover automatic history recovery across layers, viewer closure and stale history, review/unread/bulk routing, source/reconnect guards, exclusive fit/accessibility/overview, same-layer filtered obstacles, cross-layer creation including Unknown, and creation visibility during a layout-save failure.
- `openspec validate --all --strict` passed for both changes (2 passed, 0 failed). `git diff --check` and `git diff --cached --check` passed, including all new source/test files. Local path/heading verification passed 466 links, including 169 anchors, across all 18 affected Markdown files.

## Native capture evidence

The preview launcher wrote and validated three fresh PNGs using only demo source and a separate fixture database. All three were opened and visually inspected:

| Local capture | Observed result |
| --- | --- |
| `.build/verification/layers/active.png` | One Running note; Active selected; five applicable state rows; project bounds 500 × 320 |
| `.build/verification/layers/stale.png` | One old Idle note; Stale selected; only Idle under Attention; independent project bounds 600 × 400 at another position |
| `.build/verification/layers/inactive.png` | Only Archived and Unknown notes; Inactive selected; two corresponding state rows; independent project bounds 760 × 400 |

The deterministic demo fixture has four sessions in the same actual project, a one-hour cutoff, and populations 1/1/2. Commands used `preview --source demo --storage /Users/d-manakovskiy/personal/session-canvas/.build/verification/layers/preview.sqlite`, the respective `--layer active|stale|inactive`, `--capture` path, and `--skip-build`. No installed desktop was observed.

Native event tests separately verify the original blocked-move regression at detail and overview scales, same-layer rejection, independent bounds, cross-layer creation, exclusive accessibility/fit, and stale gesture cancellation. Captures establish rendering, not live Codex integration support.

## Implementation entry points

- [SessionLayers.swift](../../../Sources/CanvasCore/SessionLayers.swift): classifier, layer layouts/filters, current-occupant projection, remembered placements, transitions.
- [Database.swift](../../../Sources/CanvasCore/Database.swift) and [Models.swift](../../../Sources/CanvasCore/Models.swift): atomic legacy migration/backups, version rejection, geometry and current-layer validation.
- [ApplicationModel.swift](../../../Sources/SessionCanvas/ApplicationModel.swift): source/review/clock coordination, persistence errors/retry, exclusive navigation, source-wide bulk review, and creation.
- [ContentView.swift](../../../Sources/SessionCanvas/ContentView.swift) and [NativeCanvasView.swift](../../../Sources/SessionCanvas/NativeCanvasView.swift): selector/counts/controls and layer-scoped drawing/gestures/overview/accessibility.
- Glossary, README, native/domain guides, OpenSpec context, and the baseline change's proposal/design/specifications/tasks/verification/function inventory were reconciled in the same task.

## Implementation acceptance gates

- [x] Layer classification, scoped geometry, transitions, and migration tests executed successfully.
- [x] Native layer selection, the original move/resize regression, overview/accessibility/fit, and creation verified using fixtures/demo, with inspected captures.
- [x] Full offline test suite and native build pass through the launcher.
- [x] User guides, glossary/domain model, OpenSpec context, baseline specifications, and coverage inventories reconciled with actual implementation.
- [x] Every behavior above has recorded execution evidence; failed or skipped checks stay explicit.

The baseline change's [remaining integration gates](../add-session-canvas/verification.md) are unaffected. No planning artifact or fixture success establishes real desktop membership mutation support.
