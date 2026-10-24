# Delivery options for existing Codex sessions

Investigated on 2026-10-24. This repository initially contained only a README; no desktop application source or session integration was present.

This comparison records the initial investigation. The subsequent selected delivery is a native Mac-only SwiftUI/AppKit companion. Current implementation evidence is in [integration-compatibility.md](integration-compatibility.md), with correction coverage in [verification.md](../openspec/changes/add-session-canvas/verification.md). The six demonstrations below remain full acceptance gates; the later implementation and partial verification do not retroactively turn these initial research observations into full integration proof.

## Initial recommendation

Start with a **separate local companion app**, using the accepted session/result viewer with explicit Acknowledge and Open in Codex actions. Keep the canvas and domain model independent of its shell so an in-app plugin can reuse them later.

This is a delivery recommendation, not evidence that the required desktop-session bridge already exists. First prove access to the user's existing sessions, live activity, actual project membership, and native navigation. An app that sees only sessions it creates does not satisfy this project.

The local option gives us control of the canvas, durable acknowledgment, and viewer together. It avoids making custom host UI support a prerequisite. The trade-off is a second application and a session viewer to maintain.

## What was verified during the initial investigation

- The installed CLI exposes `app-server`, schema generation, a proxy to a running control socket, and daemon management. Only help commands were run; no daemon was started, stopped, or attached to.
- App Server documents stored-thread listing/reading and runtime notifications for loaded threads. Its thread metadata update example covers pinning and Git metadata, which does not establish project assignment support. [App Server documentation](https://learn.chatgpt.com/docs/app-server).
- Plugins are supported in Codex in the ChatGPT desktop app. This establishes a plugin packaging route, not unrestricted access to host session state. [Plugins documentation](https://learn.chatgpt.com/docs/plugins).
- MCP UI resources run as embedded components. The UI guide describes fullscreen experiences for canvases. [MCP UI documentation](https://developers.openai.com/plugins/build/chatgpt-ui).
- Extensions describe global sidebar apps and conversation panels. This establishes candidate in-app surfaces; availability and behavior in the user's exact Codex surface need a compatibility test. [Plugin Extensions documentation](https://developers.openai.com/plugins/build/extensions).

## Comparison

The assessments below are design inferences from those interfaces, not claims of tested integration.

| Concern | Separate local app | View inside Codex desktop |
| --- | --- | --- |
| Day-to-day workflow | Dedicated overview plus its own viewer; Open in Codex continues the conversation | Canvas and conversations can share the host, if its entrypoints and navigation support the flow |
| Canvas space | Fully controlled viewport and window behavior | Fullscreen/sidebar/panel options depend on the host surface |
| Existing session access | Needs a local bridge to the source actually executing desktop sessions | A plugin still needs an authorized session bridge; being embedded does not prove access |
| Live Running/Waiting/Permission | Must observe the executing source, rather than a newly launched isolated server | Same requirement for a plugin; a native host implementation could use host-owned state |
| Actual project assignment | Needs project enumeration and confirmed membership mutations | Plugin needs those operations too; native implementation requires access to host services |
| Explicit acknowledgment | Straightforward in our result viewer; app owns durable acknowledgment | Straightforward in a plugin result panel if supported; cannot assume we can inject controls into native chat |
| Native conversation opening | Requires a verified navigation mechanism for a stable session ID | Requires a verified host navigation API; plugin deep links to its own UI do not establish thread navigation |
| Background monitoring | App controls its local process lifetime and connection | Plugin UI can be suspended or closed; monitoring must not depend solely on the mounted component |
| Distribution | Local app plus bridge and version checks | Plugin plus bridge; installation and host compatibility also matter |
| Maintenance | Own viewer and packaging; protocol compatibility | Plugin/host compatibility; a native patch adds tight coupling to desktop internals |
| Fit for this first version | Recommended once the existing-session bridge passes | Attractive subsequent shell if host compatibility passes |

## Two meanings of “inside Codex”

**Plugin view:** A supported embedded UI or sidebar entrypoint. This is the in-app route to investigate first. It can share our UI and local bridge. It must be tested for the target Codex surface, persistent state, live refresh, and navigation.

**Native canvas view:** A new first-class view implemented in the desktop application's own code. This would offer the strongest integration if the product owner supplies the relevant source and APIs. No such source or native-view extension contract was established in this investigation. Do not plan a maintained desktop fork or bundle patch as though it were a supported plugin.

## Integration gate before feature implementation

Record a short reproducible compatibility report against the target installation. It must demonstrate:

1. An existing desktop session appears with the same stable identity and title; discovery handles all pages and the relevant session sources.
2. A turn started in desktop produces observed Running, input-request, permission-request, and terminal states without starting a competing execution.
3. A terminal result can be identified and displayed with its revision/turn identity after reconnecting.
4. Actual desktop projects can be listed; an allowed session can be assigned, moved, and unassigned without changing its checkout or working directory.
5. A new session can be created in that same source, with a confirmed project context, and appears in desktop.
6. Open in Codex navigates to the exact existing session.

These are verification deliverables, not assumptions hidden behind an adapter. App-server support for running our own threads alone does not pass the gate. Agent-facing tools available inside this chat are not automatically APIs available to an independently installed application.

If any essential operation is unavailable, record the failed capability and stop that delivery track before building against a fictional interface. Reassess the plugin/native route with evidence, or agree an explicit reduction in product scope. A fixture-backed canvas can help evaluate interaction design but cannot be reported as an integrated implementation.

## Persistence and ownership

Codex remains authoritative for session identity, title, project membership, execution, requests, and turn outcomes. Session Canvas owns positions, region bounds, viewport, and explicit result acknowledgments. Acknowledgments are initially local to this product; native Codex read/unread state is neither substituted for explicit acknowledgment nor changed implicitly.

The local bridge exposes only the operations needed by the canvas, preserves Codex's configured execution/approval policies, and keeps transcript data local. Neither delivery route requires a hosted website or a second agent runtime.
