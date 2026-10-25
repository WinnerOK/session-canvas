# Design

## Context

See [proposal.md](proposal.md) for motivation and [session-layers](specs/session-layers/spec.md) for the proposed behavior. This is planning only; the following are implementation decisions, not claims about shipped behavior.

Read-only inspection found:

- [Models.swift](../../../Sources/CanvasCore/Models.swift) gives `Workspace` a single `placements`, `regions`, and `viewport`. `validateRegion` iterates all source sessions and regions. `vacantPlacement` also uses the entire workspace, including filtered notes, and can expand or translate a full project when necessary.
- [ApplicationModel.swift](../../../Sources/SessionCanvas/ApplicationModel.swift) filters rendering through `visibleSessions`, while `editRegion` carries every member of a project and validates against shared geometry. Source refresh, background history recovery, acknowledgment, and the 30-second activity clock can alter the visible population independently.
- [CanvasRearranger.swift](../../../Sources/CanvasCore/CanvasRearranger.swift) accepts visible IDs but treats other placements as carried or fixed obstacles. Merely adding a layer predicate to rendering would leave the reported problem intact.
- [Database.swift](../../../Sources/CanvasCore/Database.swift) stores one encoded workspace and a separate visibility payload per source; acknowledgments already have source/session/result keys and must remain shared.
- [NativeCanvasView.swift](../../../Sources/SessionCanvas/NativeCanvasView.swift) reads workspace geometry throughout drawing, hit testing, creation contexts, gestures, fitting, and accessibility. Its current note drag captures a source revision, but no layer or geometry generation.
- [CanvasVisibilityTests.swift](../../../Tests/CanvasRuntimeTests/CanvasVisibilityTests.swift) explicitly expects age/archival changes to retain one shared placement and Unknown to use the age filter. These assertions need replacement, alongside scoped extensions of Rearrange, project, creation, overview, and acknowledgment tests.

The authoritative project integration remains the existing native, API-only contract: actual source membership is shared, and real-source assignment stays disabled. The [delivery](../../../docs/delivery-options.md) and [compatibility](../../../docs/integration-compatibility.md) constraints continue to apply.

## Goals / Non-Goals

**Goals:**

- Make lifecycle classification one deterministic domain operation, separate from optional rendering exclusions.
- Make it difficult for geometry consumers to accidentally see another layer's obstacles or mutate its layout.
- Preserve spatial memory across returns without reserving historical empty slots.
- Keep migration, event handling, and save failures testable with fixtures and temporary Canvas databases.

**Non-Goals:**

- Duplicating source sessions, source subscriptions, history caches, or acknowledgment records per layer.
- Implementing a new source state called Stale or changing Codex archival semantics.
- Repacking every project after each event, letting users manually assign layers, or introducing new integration capabilities.

## Decisions

### 1. Derive a layer after deriving note state

Introduce stable `CanvasLayer` identifiers `active`, `stale`, and `inactive`. A pure classifier consumes a session, its shared acknowledgments, the per-source idle timeout, and a supplied clock:

| Priority | Condition | Layer |
| --- | --- | --- |
| 1 | Derived note state Archived or Unknown | Inactive |
| 2 | Derived Idle, valid timestamp at/past cutoff, and no execution/request/unread-result protection | Stale |
| 3 | All other eligible sessions | Active |

Never and missing/future activity do not satisfy row 2. Search and attention/project exclusions are not classifier inputs. Existing note-state priority is unchanged. Inactive-first deliberately replaces the old optional Unknown age hiding, even if Unknown retains cached unread evidence.

Alternative: define Stale as every session hidden by any filter. Rejected because toggling a state, project, or search would unexpectedly transfer layout and would not match the requested idle-age layer.

### 2. Share source facts; store layouts by layer

Keep one source inventory/project catalog and one acknowledgment store. Replace the single geometry maps with a versioned workspace envelope containing three `LayerLayout` values (placements, regions, viewport, and saved placement membership/offset metadata). Store selected layer, global idle timeout, and per-layer attention/project exclusions with the same source boundary. Search remains transient.

Expose an explicit layer-scoped geometry value containing **all current members of that layer**, not just visible notes. Route collision checks, vacant placement, manual edits, and Rearrange through it. Rendering gets its filtered subset. Avoid copying an entire source workspace and forgetting to remove another layer's regions.

Remember departed notes' positions with the actual project identity and a project-relative offset, or an absolute unassigned position. Such records and regions with no current members are dormant: they survive reopening but are excluded from occupied rectangles, region validation, and packing. A region with current members hidden by search or filters remains an obstacle on that layer. Moving a region changes its own bounds and current members; retained relative offsets follow those bounds when a session returns.

Alternative: only ignore filtered rectangles in existing validation. Rejected because independent sizes/positions cannot be represented and restoring visibility would produce ambiguous project interiors. Alternative: duplicate complete workspaces including source facts. Rejected because state and acknowledgment would diverge.

### 3. Reconcile transitions as complete geometry plans

Use one coordinator for initial discovery, refresh, live/history recovery, archive confirmation, acknowledgment/Mark as unread/bulk acknowledgment, timeout changes, and activity-clock ticks. Compute all layer populations from one snapshot. Sessions leaving a layer become dormant there before destination placement is planned; deterministic stable-ID order resolves simultaneous arrivals.

For each arrival:

1. Resolve current authoritative membership. Ignore cached offsets whose project identity differs.
2. Use the destination project's existing region. Restore a remembered project-relative placement if its current center and footprint are valid and vacant. Unassigned positions must remain outside every occupied region.
3. If no valid remembered slot exists, allocate the nearest valid slot to that remembered position when available, otherwise a deterministic free slot. If no region exists, seed an empty remembered region only if nonconflicting; otherwise allocate new bounds without copying over an existing destination region.
4. Grow the destination region if possible. If surrounding same-layer geometry blocks growth, use the existing whole-project translation strategy into free space, carrying current members together. Do not rearrange unrelated projects. Validate finite bounds, project non-overlap, containment, and new note collisions against current hidden and visible occupants.
5. Publish all affected layouts together. Persist one complete snapshot. Manual geometry commands save before publishing; automatic source-driven changes may retain a complete valid in-memory plan flagged unsaved if persistence fails. Source state never rolls back because a Canvas save failed. Retain the prior durable snapshot and expose explicit retry.

Source membership changes invalidate remembered positions under the former project across all layers; they never revive obsolete grouping. A new layer-specific geometry generation accompanies any membership/population/layout change. Capture it with source identity, selected layer, and session revision when starting a gesture; reject stale commits and discard AppKit previews on layer switches. History work must also respect current selection/generation.

Alternative: preserve the same absolute coordinates on every transition. Rejected because destination projects have independent bounds and a former slot can have been reused. Automatic global Rearrange is also rejected because it destroys spatial context.

### 4. Use a single-choice native layer selector

Add a native sidebar layer group above Attention, with the three full labels, population counts, and an accessible selected state. No checkbox or All layers option is offered. Active defaults to five state rows (Running, Waiting for you, Permission required, Finished, Idle), Stale to Idle, and Inactive to Archived then Unknown. Fresh layers start with their applicable states enabled; migrated preferences preserve explicit exclusions. Explain an empty filtered Inactive layer and provide **Show all in this layer**.

Keep **Hide Idle after** as the one shared cutoff and explain that expired Idle sessions move to Stale. Remove **Hide unknown**. Keep transient title search across switches, and save attention/project exclusions separately for each layer. Rename the current inventory/reset row to **Show all in this layer**, retaining a clearly labeled source-wide total elsewhere. Command + 1 resets search and selected-layer exclusions without changing cutoff or selection. All population counts ignore filters; attention rows ignore their own state exclusions, preserving the existing useful counts.

Save a viewport per layer and restore it without automatic fit. Switching layers cancels gestures/focus previews, ends temporary creation reveal, and closes any viewer that is no longer visible. Ordinary reclassification updates counts but never switches layers. **Acknowledge all** keeps its source-wide Finished scope and help text regardless of selected layer.

Creation is an explicit navigation exception: capture the origin layer/project/location, then reveal only the confirmed session's classified layer. Same-layer/same-project creation retains clicked placement and viewport; crossing layers uses destination geometry and explicitly focuses the new note. Never borrow an Inactive region's bounds to overwrite its Active counterpart. If confirmed creation is unexpectedly Unknown, reveal it in Inactive rather than bypassing classification.

Alternative: remove all attention filters. Rejected as unnecessary loss of existing control. A global Show all reset that selects multiple layers contradicts the requested exclusive display.

### 5. Reconcile the unarchived baseline contract during apply

`openspec list --specs` reports no main specs. The existing seven capabilities live in `add-session-canvas`; creating MODIFIED deltas against nonexistent main specs would invent an invalid archive baseline. This change therefore introduces the cohesive `session-layers` capability. The following mapping explicitly records proposed supersession; implementation must align the baseline artifacts before archiving either change.

| Existing contract in add-session-canvas | Proposed layer-specific interpretation |
| --- | --- |
| canvas-workspace: Visibility filters combine and persist; Persisted archive and idle-age visibility; Optional age hiding for Unknown | Visibility is per layer; the shared cutoff routes eligible Idle to Stale; Unknown always belongs to Inactive and its age toggle is removed |
| canvas-workspace: Layout survives reopening; Updates preserve spatial context; Inventory gaps do not remove notes | Store geometry per layer; unchanged-layer updates preserve position, while classification changes materialize destination geometry without deleting the source session |
| canvas-workspace: Explicit visible-session rearrangement; Compact square-oriented layout; New sessions receive predictable placement | Consider current selected-layer occupants only; retain same-layer filtered geometry rules and ignore dormant or cross-layer geometry |
| canvas-workspace: Workspace counters explain their scope; Search matches session titles without changing stored organization; Canvas-first window controls; Native navigation inputs remain discoverable | Add exclusive selector; selected-layer counts and resets; source-wide bulk action and total remain explicit |
| project-regions: Regions represent actual projects; Region geometry has one drop target; Region editing preserves membership; External membership changes reconcile placement | One representation per actual project per layer, independent bounds, same-layer validation and current occupants; source membership shared across layers |
| session-attention: Restore an archived session; Project overview summarizes visible attention; Automatic recovery for cached terminal results; Reverse explicit acknowledgment | Retain source/acknowledgment behavior, but resulting state changes route sessions into destination-layer geometry and overview scope |
| session-actions: Created notes use the confirmed session; Created sessions remain visible and actionable; Context creation preserves the clicked location | Reveal exactly the confirmed session's layer, preserve same-layer clicked context, and focus explicitly when changing layers |
| source-connection: Source identity isolates durable workspace state | Keep layers and preferences isolated inside the same source identity; source facts/history remain shared |

Also update `openspec/config.yaml`, baseline proposal/design/tasks/verification/function inventory, README, glossary, domain model, and native guide during implementation. Current user guides and historical test evidence remain descriptions of the existing app until then. The new [verification plan](verification.md) keeps every feature acceptance gate open.

## Risks / Trade-offs

- [Unknown no longer appears in Active even with cached unread evidence] → Give Inactive a visible count and retain automatic recovery; source-wide bulk acknowledgment still excludes Unknown and Archived.
- [An arriving session may require translating a crowded destination project] → Prefer remembered vacant positions and growth; translate only that project as a validated group and preserve the selected viewport.
- [Dormant placement or empty-region records accidentally become obstacles] → Separate retained memory from current occupancy and test reusing departed coordinates explicitly.
- [Older events, gestures, or save callbacks overwrite another layer] → Use source/layer/geometry generations and serialize whole-snapshot publication and persistence. Do not regress authoritative source facts on save failure.
- [Persisting three layouts increases payload size] → Share inventories/history/acknowledgments and keep only small geometry records per layer; use the existing Canvas-owned SQLite database.
- [Migrated exclusions make Inactive initially empty] → Preserve user choices, show unfiltered population counts, and offer a layer-scoped reset; fresh installations enable both Inactive states.

## Migration Plan

1. Detect the unversioned workspace and legacy visibility payload without changing the source connection. Read shared acknowledgments before classification. Reject unsupported newer payload versions rather than silently flattening them.
2. Retain the raw original workspace and visibility payloads in Canvas-owned migration backup records. Build all three layouts from the old bounds/viewport and only that layer's current placements, preserving exact coordinates when valid. Repair invalid legacy geometry deterministically within the affected layer, preferring valid remembered positions and translating only conflicting project groups.
3. Copy each legacy state exclusion to layers where that state can occur; copy project exclusions to all three. Keep the idle timeout, ignore legacy Hide unknown for classification, and select Active. Fresh profiles instead use enabled applicable states and Never.
4. Commit backup, versioned workspace, and converted preferences in one SQLite transaction. Failure leaves the original readable and disables layout writes until a retry succeeds. Loading the versioned payload must not reseed layers on every launch.
5. Keep migration backups available for explicit recovery. Downgrade requires restoring the pre-migration Canvas records after closing the app; it discards subsequent layer edits and does not alter Codex or shared acknowledgment records. Do not auto-flatten a layered snapshot for an older binary.

No live-desktop verification is needed for the proposed behavior. Implementation uses fixtures and demo captures first; any later live check requires separate authorization for that run under the existing [verification safety rules](../../../docs/native-application.md#verification-safety).
