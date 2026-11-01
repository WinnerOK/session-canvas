# Proposal

## Why

Existing Codex sessions are easier to recognize and coordinate when their location is stable and their need for attention is visible. A spatial canvas should let the user organize those same sessions by project and keep completed results visible until explicitly reviewed.

## What Changes

- Reduce redundant/superseded test functions by twenty percent with at most two percentage points of production line-coverage loss. Add complete production-target coverage export to the local launcher and retain a removal-to-regression evidence map in the [test-pruning report](../../../docs/test-pruning.md).
- Specify connection preferences, desktop/shared/demo source selection, automatic/manual refresh, source-isolated restoration, connection feedback, and application shutdown. Index all implemented functions against requirements, code, and evidence in [functional-coverage.md](functional-coverage.md).
- Preserve last-known execution/request/active-turn evidence across restart and metadata-only discovery, visibly separate from Unknown current status. Make explicit refresh check the entire source, including uncached/filtered sessions, with progress, Stop, failure counts, and unresolved-state feedback.
- Display one persistent canvas with three exclusive lifecycle layers and independent project geometry/viewports. Archived and Unknown are Inactive; expired eligible Idle is Stale; all others are Active. Exclude Guardian/internal agents by source/parent metadata without deleting them.
- Keep full destination projects anchored while adding rows downward. Push only blocking same-layer projects (with all current members) and unassigned notes through a deterministic downward cascade, including filtered/protruding cards. Preserve other geometry, viewport, source facts, and acknowledgment; do not shrink automatically.
- Recover saved terminal state during discovery or on reading the latest history page, including when local history is unavailable. Automatically recheck unresolved cached-result sessions in a paced background queue without opening them; newer work and current requests take priority. Show single-unit last activity on notes and relative plus exact activity time in the viewer. Offer archive/restore and a shared persisted Idle cutoff for Stale classification; remove the former Hide unknown age toggle. Protect active work, pending requests, and unreviewed results from age hiding.
- Clip drawing to the canvas. Put New Session/Rearrange/Fit/Full Screen and Acknowledge all in the top toolbar, remove the workspace heading/tagline/header panel, and make the native sidebar toggleable.
- Add explicit compact, roughly square layout of currently visible notes: adaptive grids inside projects, a size-packed project block, and a separate unassigned-session grid below it. Retain Attention/activity/identity note order; use source/sidebar order only for equal-size project ties. Prefer a smaller longer side, then bounding area, without rotating projects. Move hidden members with their project while preserving relative offsets, keep other hidden geometry fixed, retain actual membership/viewport, and save a complete valid plan before applying it.
- Use project overviews exactly when session notes stop fitting compact text, sharing the same layout decision for rendering and interaction. Keep original geometry and drag behavior; show readable truncated names when they fit, otherwise omit text. Zoom must not shift or reflow regions.
- Combine search, independent attention visibility, and individual project hiding. Omit projects without visible sessions; persist per-source visibility and offer restore actions.
- Derive note color and label from confirmed archive status, live execution, pending requests, and explicit acknowledgment of the latest result. Archived takes priority over Unknown; both belong to Inactive with independently saved filters and are enabled on fresh profiles.
- Keep Finished until explicit acknowledgment of a displayed result or a top-bar Acknowledge all batch covering all current-source Finished sessions. Allow Mark as unread on the same viewer button to reverse one known acknowledgment in any state; opening never acknowledges.
- Import actual desktop projects and explicit memberships independently of working directories, preserving desktop assignments when backend membership is null or different. Reject unsupported real-source moves without writing or changing Canvas grouping; ignore legacy backend-only confirmations. Keep API-only desktop mutation support open until actual desktop membership can be changed and independently verified.
- Show newest-first read-only history with fixed, wrapping Acknowledge/Open in Codex/Reload controls. Session menus start with Open in Codex and omit Open session.
- Load newest-first history in on-demand pages of at most twelve turn summaries. Use linear JSONL framing and serial decoding outside the UI actor, with paced delivery and connection-generation isolation. Verify the reproduced long-history stall with fixtures; keep revision-aware caching, legacy/local full-read removal, huge visible text, and installed-session acceptance as separate work. See [the investigation and repair](../../../docs/history-loading-performance.md).
- Create from background or project areas at every zoom: confirm server project/roots, create an empty durable session, retain its note before inventory publication, and automatically open Codex for the instruction. Default blank names and projectless working folders, verify saved-history resume independently, and release creation ownership before continuation. Start no turn.
- Reveal the latest created session despite existing filters, show its viewer and continuation notice, and preserve saved visibility choices. Keep valid clicked placement, choose the nearest valid location for collisions including hidden notes, and preserve viewport pan/zoom for creation in the context's project. Keep clicked context within the same layer; focus for a changed project, changed classified layer, or explicit request. Show submission errors inside the active creation dialog.
- Deliver a native Mac-only companion using SwiftUI/AppKit, with the in-app alternatives retained as historical research. Verify source capabilities and expose unsupported desktop operations explicitly.
- Provide a stable local build/test/preview launcher with one user-authorized Codex prefix rule, local caches, and isolated captures so changing verification parameters does not repeat approval prompts.
- Run pull-request checks on Apple Silicon (`arm64`) macOS in GitHub Actions. Prepare a tested, versioned arm64 app ZIP and checksum as a draft GitHub Release from a manual run or version-tag push. Build, test, and release automation supports only arm64.
- Use the selected blue session-cards application icon in local and release macOS bundles, with native icon sizes and resource metadata included before signing. Retain unselected concepts for comparison.

## Capabilities

### New Capabilities

- `canvas-workspace`: Free-roam navigation, existing-session notes, positioning, and durable layout.
- `session-attention`: Observable execution/request states, terminal outcomes, and explicit result acknowledgment.
- `project-regions`: Project geometry and confirmed project membership through note placement.
- `session-actions`: Session/result viewing, native Codex navigation, and contextual session creation.
- `source-connection`: Startup/source selection, local connection preferences, refresh, status, isolated demo, bounded transport, and lifecycle.
- `local-verification`: Bounded agent-driven build/test/native-preview commands and reusable local permission.
- `release-automation`: Pull-request checks and versioned native macOS artifacts in reviewed GitHub Releases.

The [session-layers successor](../add-session-layers/proposal.md) owns exclusive classification, independent geometry, transition placement, migration, and layer navigation. Baseline spatial operations now refer to the selected layer.

### Modified Capabilities

None. These capabilities originated in this change and have not yet been archived into main specifications. Their requirements now include the subsequent implementation corrections.

## Impact

Introduces a native SwiftUI/AppKit canvas UI, local SQLite storage, and an integration boundary to the user's existing Codex source. The selected Mac-only companion combines CLI inventory/history, validated saved project metadata, and a read-only revisioned desktop runtime feed with automatic reconnection. The newer bundled CLI supports empty-session creation and backend project metadata, but the live check showed that metadata updates do not change desktop project membership. Real-source membership writes are disabled until an API-only desktop integration is verified. Full native workflow acceptance, atomic external-move protection, and durable uncertain-operation recovery remain open gates. See [verification.md](verification.md) for correction-to-requirement coverage and [integration compatibility](../../../docs/integration-compatibility.md) for observed capabilities and limits.

Initial scope is one user, one local source, and one canvas. Archive/restore controls are included. Collaboration, drawing tools, multiple boards, session deletion, in-view replies, and permission approval are deferred. The viewer delegates continuing work and resolving requests to Codex desktop.

Supporting investigation: [domain model](../../../docs/domain-model.md), [delivery comparison](../../../docs/delivery-options.md), and [glossary](../../../GLOSSARY.md).
