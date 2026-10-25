# Proposal

## Why

Hidden Archived and Unknown sessions still occupy the shared canvas geometry, so their notes and project regions can prevent moves on an apparently empty canvas. Separate lifecycle layers let the user organize current work independently while retaining each session's actual Codex project when its state changes.

## What Changes

- Introduce three mutually exclusive layers: **Active sessions**, **Stale sessions**, and **Inactive sessions**. Show exactly one layer at a time, defaulting to Active.
- Classify Archived and Unknown as Inactive first. Classify otherwise Idle sessions excluded by **Hide Idle after** as Stale; classify all remaining sessions as Active. Preserve the existing age protections for execution, requests, and unread results. Never makes Stale empty.
- Give each layer independent project-region positions/sizes, session-note placements, and viewport. Project identity and session membership remain shared source facts.
- Apply project non-overlap, note containment, placement, hit testing, region editing, and Rearrange within one layer. Geometry belonging to other layers cannot block an edit.
- Reclassify on source, result-review, timeout, and clock changes. Restore a valid destination-layer position or allocate space inside the same project's destination region. Retain layouts for later returns without letting departed notes reserve space.
- Retain attention and project filters within each layer, with independent saved choices. Replace **Hide unknown** with the Inactive layer; the age cutoff applies only to otherwise eligible Idle sessions. **BREAKING**: visibility reset can no longer combine every session on one canvas, and Unknown is always Inactive regardless of age or retained result evidence.
- Migrate the current single layout without discarding coordinates, project identities, acknowledgment, or the configured idle timeout.

## Capabilities

### New Capabilities

- `session-layers`: Exclusive lifecycle classification, layer navigation, independent durable geometry, automatic transitions, and integration of existing canvas operations with one selected layer.

### Modified Capabilities

None in the main-spec inventory: `openspec list --specs` currently returns no specifications. The relevant existing contracts are still declared in [add-session-canvas](../add-session-canvas/proposal.md). This change adds the cohesive `session-layers` capability and explicitly supersedes that change's single-layout and lifecycle-visibility rules as mapped in [design.md](design.md). Implementation must reconcile those baseline artifacts rather than archive conflicting contracts.

## Impact

The native SwiftUI/AppKit application and Canvas-owned SQLite payloads are affected: `Models.swift`, `Database.swift`, `CanvasRearranger.swift`, `ApplicationModel.swift`, `ContentView.swift`, `NativeCanvasView.swift`, overview/accessibility consumers, demo fixtures, and geometry/runtime tests. Existing source transport and acknowledgment identities remain shared and unchanged. No new dependency or source API is required.

Implementation updates the glossary, domain/native guides, README, OpenSpec context, and the baseline change's proposal/design/specs/tasks/verification/function inventory. Completed work and actual verification evidence are recorded in [verification.md](verification.md); unrelated desktop integration gates remain open.

Out of scope: manual layer assignment, custom layers, a combined-layer view, cross-layer project synchronization of geometry, new desktop membership APIs, session execution, and enabling currently unsupported real-source project moves.
