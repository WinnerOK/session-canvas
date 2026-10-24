# Proposal

## Why

Existing Codex sessions are easier to recognize and coordinate when their location is stable and their need for attention is visible. A spatial canvas should let the user organize those same sessions by project and keep completed results visible until explicitly reviewed.

## What Changes

- Add one persistent, pannable and zoomable canvas of existing non-archived Codex sessions, each represented by a movable sticky note showing its title and state.
- Derive note color and label from live execution, pending requests, and explicit acknowledgment of the latest terminal result: Running, Waiting for you, Permission required, Finished, Idle, or Unknown.
- Keep Finished until the user explicitly acknowledges a displayed result in the session viewer. Opening alone does not acknowledge it.
- Represent actual Codex projects as regions. A note drop assigns, reassigns, or removes project membership after source confirmation.
- Open the same session in a local result/history viewer on note click, with Acknowledge and Open in Codex actions.
- Start a session from a context menu at the clicked canvas location, inheriting the region's project when applicable.
- Deliver a native Mac-only companion using SwiftUI/AppKit, with the in-app alternatives retained as historical research. Verify source capabilities and expose unsupported desktop operations explicitly.

## Capabilities

### New Capabilities

- `canvas-workspace`: Free-roam navigation, existing-session notes, positioning, and durable layout.
- `session-attention`: Observable execution/request states, terminal outcomes, and explicit result acknowledgment.
- `project-regions`: Project geometry and confirmed project membership through note placement.
- `session-actions`: Session/result viewing, native Codex navigation, and contextual session creation.

### Modified Capabilities

None. This is a new project with no existing OpenSpec capabilities or application implementation.

## Impact

Introduces a native SwiftUI/AppKit canvas UI, a local SQLite store, and an integration boundary to the user's existing Codex source. The user selected a Mac-only application. Protocol support for live desktop sessions, actual projects, and native navigation remains an explicit feasibility gate, not a claim of completed integration. See docs/integration-compatibility.md for the implemented subset and verification evidence.

Initial scope is one user, one local source, and one canvas. Collaboration, drawing tools, multiple boards, session archive/delete controls, in-view replies, and permission approval are deferred. The viewer delegates continuing work and resolving requests to Codex desktop.

Supporting investigation: [domain model](../../../docs/domain-model.md), [delivery comparison](../../../docs/delivery-options.md), and [glossary](../../../GLOSSARY.md).
