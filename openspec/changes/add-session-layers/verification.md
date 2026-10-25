# Verification

## Scope and current status

This is a planning-only change. No application code, database, source connection, or live desktop state has been modified. References to tests below are planned coverage entry points, not successful executions. All implementation acceptance gates remain open.

The user supplied the layer definitions, same-layer project non-overlap, independent project bounds between layers, exclusive display, and return-to-project requirement. Additional defaults (Active first, per-layer viewport/filters, remembered placement fallback, and creation navigation) are recorded in [design.md](design.md).

## Request-to-requirement coverage

All requirements below are in the [session-layers specification](specs/session-layers/spec.md).

| Request or affected behavior | Requirement | Planned evidence | Status |
| --- | --- | --- | --- |
| Three layers with separate lifecycle populations | Every session has one derived layer; Idle age routes sessions to Stale | Pure classifier cases covering every note state, exact cutoffs, Never, timestamp errors, unread/request/execution protection, and Inactive precedence | Open |
| Hidden Archived/Unknown must not block moving current projects | Project geometry is independent per layer; Spatial operations use current layer occupants | Active region move/resize over coordinates occupied in Inactive succeeds; same-layer collisions including filtered regions are rejected | Open |
| Same project can have different bounds on different layers | Project geometry is independent per layer; Layer layouts and preferences survive reopening | Three independent bounds and viewports for one stable project identity, before/after SQLite restart | Open |
| Never show multiple layers at once | Exactly one layer is selected; Visibility controls stay within a layer | Native draw/hit-test/focus/accessibility/fit assertions at detail and overview zoom; reset cannot combine layers | Open |
| Archived to Stale and Stale to Active preserve the project | Transitions preserve actual project membership | Fixture archive/restore/activity sequence, same identity/project/acknowledgment, zero assignment or execution calls | Open |
| A returning session must fit its project's destination layout | Destination placement restores valid spatial context | Valid offset restoration after destination project movement; reused slot, resized/full region, blocked growth, first arrival, and unassigned fallback | Open |
| Departed notes must not create another invisible obstacle | Spatial operations use current layer occupants | Reuse departed slots/empty regions while retained layout memory stays available | Open |
| Recover Unknown and reflect review/age/source events | Automatic transitions preserve layer navigation; Transitions preserve actual project membership | Background history recovery, acknowledgment/unread/bulk transitions, clock/timeout changes, external project change, and reconnect tests | Open |
| Gestures/viewers must not target an obsolete layer | Automatic transitions preserve layer navigation | Layer switch/reclassification during drag/resize, stale history reply, and delayed save callback regressions | Open |
| Existing visibility, counts, and bulk-review behavior need clear scopes | Visibility controls stay within a layer; Counters explain layer and action scope | Per-layer filters, unfiltered selector counts, source total, and source-wide atomic Finished acknowledgment from Inactive | Open |
| Context creation must preserve project identity without a mixed view | Creation reveals one classified layer | Inactive A creation reveals Active A only; same-layer clicked location and viewport; unexpectedly Unknown creation reveals Inactive only | Open |
| Existing saved workspaces must survive the change | Existing single-layout workspaces migrate safely; Layer layouts and preferences survive reopening | Temporary legacy payloads, original-coordinate preservation, state/project preference conversion, source isolation, rollback/failure, repeat loading, and unknown-version rejection | Open |
| Existing compact layout and semantic zoom must remain usable | Rearrange and overview remain layer scoped | Revised core/runtime Rearrange and semantic-zoom cases with cross-layer coordinates, hidden current members, independent geometry, and deterministic packing | Open |

## Planned verification entry points

- Core classification/storage/geometry: extend [CanvasCoreTests](../../../Tests/CanvasCoreTests/CanvasCoreTests.swift), [SessionLifecycleTests](../../../Tests/CanvasCoreTests/SessionLifecycleTests.swift), and [CanvasRearrangerTests](../../../Tests/CanvasCoreTests/CanvasRearrangerTests.swift); introduce focused layer suites where useful.
- Runtime visibility and transitions: revise [CanvasVisibilityTests](../../../Tests/CanvasRuntimeTests/CanvasVisibilityTests.swift), [LiveStateTests](../../../Tests/CanvasRuntimeTests/LiveStateTests.swift), [ProjectMembershipTests](../../../Tests/CanvasRuntimeTests/ProjectMembershipTests.swift), and [AcknowledgmentActionsTests](../../../Tests/CanvasRuntimeTests/AcknowledgmentActionsTests.swift).
- Native interactions and regression integration: extend [ProjectCreationTests](../../../Tests/CanvasRuntimeTests/ProjectCreationTests.swift), [SemanticZoomTests](../../../Tests/CanvasRuntimeTests/SemanticZoomTests.swift), and [RearrangeTests](../../../Tests/CanvasRuntimeTests/RearrangeTests.swift).
- Execute code checks through the [authorized launcher](../../../docs/native-application.md#codex-verification-launcher), starting with offline fixtures and demo data. Live desktop checks require separate authorization for the specific run and are not an acceptance dependency of this feature.

## Planning evidence

- Read the exact invoked skill, project instructions/configuration, glossary/domain model, relevant Swift implementation/tests, baseline contracts, native/delivery documentation, and prior-context sources. Prior KB material concerned desktop project assignment; the current code/config still disable real-source assignment, and this proposal leaves that boundary intact.
- `openspec context --json` and `openspec list --json` resolved this repository as the planning root. `openspec list --specs` returned no main specifications; the baseline contract is the unarchived `add-session-canvas` change.
- `openspec validate --all --strict` passed: 2 changes, 0 failures. The new capability has 14 requirements and 32 scenarios, mapped above; all 28 implementation tasks remain unchecked.
- Local link/heading and planning-consistency checks passed for all 5 new Markdown artifacts: 32 local links, including 2 anchors; requirement descriptions meet the limit, every requirement has a verification mapping, and task IDs are unique with completion evidence.
- `git diff --check` and `git diff --cached --check` passed. `openspec status --change add-session-layers --json` reports all four schema artifacts done; that is planning completeness, not implementation acceptance.
- No application build, automated feature test, native capture, installed-source operation, or live observation was executed for this planning-only change.

## Implementation acceptance gates

- [ ] Layer classification, scoped geometry, transitions, and migration tests executed successfully.
- [ ] Native layer selection, the original move/resize regression, overview/accessibility/fit, and creation verified using fixtures/demo, with inspected captures.
- [ ] Full offline test suite and native build pass through the launcher.
- [ ] User guides, glossary/domain model, OpenSpec context, baseline specifications, and coverage inventories reconciled with actual implementation.
- [ ] Every behavior above has recorded execution evidence; failed or skipped checks stay explicit.

The baseline change's [remaining integration gates](../add-session-canvas/verification.md) are unaffected. No planning artifact or fixture success establishes real desktop membership mutation support.
