# Source Connection

## Purpose

Connect the native workspace to saved Codex sessions, an existing shared server, or an isolated demo, with explicit connection status and source-owned persistence boundaries.

Canvas geometry, visible populations, filters, overview, and gestures below refer to the selected layer defined by [session-layers](../../../add-session-layers/specs/session-layers/spec.md). Source identities, actual memberships, results, and acknowledgments remain shared; explicitly source-wide actions keep that scope.

## ADDED Requirements

### Requirement: Explicit source selection and startup defaults
The app SHALL offer Codex desktop, Shared Codex server, and Demo workspace through Connection Settings and the sidebar source menu. Normal startup SHALL select Codex desktop; --demo SHALL select Demo workspace. Default executable discovery SHALL prefer the installed desktop-bundled Codex executable, then supported local CLI locations. A previously selected source mode SHALL NOT replace these startup rules.

#### Scenario: Launch without arguments
- **WHEN** the user launches the app normally
- **THEN** it attempts the desktop source using saved connection settings or executable/navigation defaults
- **AND** demo sessions are not imported into the real workspace

#### Scenario: Connect to a shared source
- **WHEN** the user selects Shared Codex server with an optional control-socket path
- **THEN** the adapter uses the existing app-server proxy and expands a leading tilde in executable/socket paths
- **AND** an unreachable server reports a connection failure with guidance to configure the socket or select Codex desktop
- **AND** Canvas does not install or reconfigure a shared daemon

### Requirement: Editable local connection preferences
Connection Settings SHALL edit source mode, Codex executable, shared control socket when applicable, and native URL template. Connect SHALL save executable/socket/template preferences locally and reconnect with the selected mode. Cancel SHALL discard edits without reconnecting. The default native URL template SHALL be codex://threads/{id}.

#### Scenario: Apply or cancel settings
- **WHEN** the user edits connection preferences and chooses Connect
- **THEN** those preferences are saved for later launches and a new connection attempt begins
- **AND** choosing Cancel instead leaves the active connection and saved preferences unchanged

### Requirement: Source identity isolates durable workspace state
Geometry, viewport, session/result cache, visibility, and acknowledgment SHALL be partitioned by confirmed source identity. Desktop and shared connections to the same Codex home SHALL share that identity; Demo workspace SHALL use a separate identity. Switching or reconnecting SHALL save the outgoing workspace, close its connection, restore the incoming source's records, clear viewer/history and temporary creation reveal, and reject delayed replies from the previous connection generation.

#### Scenario: The server identifies another Codex home
- **WHEN** initialization reports a Codex home different from the provisional local default
- **THEN** the app restores that confirmed home's workspace, visibility, and acknowledgments before reconciliation
- **AND** it does not seed the new source with another home's cached results

#### Scenario: Return from demo to real sessions
- **WHEN** the user switches from demo to Codex desktop
- **THEN** real placements and review records are restored independently of demo changes
- **AND** a late operation from the previous source cannot alter the current workspace

### Requirement: Refresh is automatic and explicitly available
A connected workspace SHALL refresh on connection, every 12 seconds, and through Refresh Sessions in the toolbar/menu or Command + R. Source-change notifications SHALL coalesce over 250 milliseconds before requesting a refresh. Only one inventory refresh SHALL run at a time. Refresh SHALL reconcile source facts without acknowledging results or invoking Rearrange. Arrivals SHALL use the anchored downward placement contract when destination space is needed.

#### Scenario: Repeated notifications arrive
- **WHEN** several relevant source changes arrive within the coalescing interval
- **THEN** they request one refresh rather than one refresh per notification
- **AND** disconnected or already-refreshing commands do not start overlapping discovery

#### Scenario: Refresh fails or the inventory connection closes
- **WHEN** a refresh fails or the inventory process disconnects
- **THEN** existing notes and review records remain, execution becomes Unknown except for the higher-priority Archived display state, and errors/status explain the failure
- **AND** reconnecting is available in Connection Settings; desktop-feed reconnection remains automatic as specified by session-attention

### Requirement: Connection feedback and empty-workspace onboarding
The toolbar SHALL distinguish connecting, desktop, saved-only, shared, demo, disconnected, and unavailable states. Saved discovery SHALL remain usable without a live desktop feed. Initial uncached discovery SHALL show progress. An empty source SHALL offer Connection settings and Explore demo with connected/unconnected guidance; a fully filtered workspace SHALL offer Show all sessions.

#### Scenario: Codex desktop is closed
- **WHEN** saved-session discovery succeeds without a reachable desktop feed
- **THEN** saved notes/history remain available and the status explains that only saved history is connected
- **AND** the UI does not claim that the saved reader proves live execution

### Requirement: Demo exercises the workspace without real execution
Demo workspace SHALL be visibly labeled DEMO and persist its own sample sessions, layout, filters, and acknowledgments. It SHALL provide sample running, input, permission, completed, and stopped sessions, simulated archive/restore and confirmed project moves, and prompt-driven simulated creation. It SHALL NOT submit real model turns or offer native navigation for demo identities.

#### Scenario: Create a demo session
- **WHEN** the user submits a nonblank demo prompt with an optional title and project
- **THEN** one local Running sample note is created, using the prompt's prefix when the title is blank
- **AND** it produces a simulated Completed result after a short delay that requires explicit acknowledgment
- **AND** no real Codex session is created

#### Scenario: Reopen the demo
- **WHEN** the user reconnects to an existing demo workspace
- **THEN** its cached sample sessions and saved organization are restored instead of resetting every visit to the seed layout

### Requirement: Observation stays within validated local boundaries
The source adapter SHALL read project metadata only from the connected Codex home and SHALL NOT directly write Codex databases or metadata files. Desktop observation SHALL require a same-user local socket and peer, bounded frames, and supported stream versions. Remote-host observations SHALL NOT establish local execution. Observation SHALL decline execution ownership and input/approval handling; the explicit session-actions creation flow retains its separate short-lived ownership contract.

#### Scenario: Unsafe or unsupported observation
- **WHEN** socket ownership, framing, or stream validation fails
- **THEN** that feed provides no authoritative live state and saved discovery remains independent
- **AND** Canvas does not start an IPC router, claim a session, submit work, or answer requests to repair observation

### Requirement: Connection errors are bounded and actionable
Inventory/history RPC requests SHALL time out after 20 seconds and fail pending requests on connection closure. The transport SHALL drain child-process diagnostics without displaying arbitrary stderr and SHALL report server rejections using error codes rather than arbitrary private server messages. General action/storage failures SHALL be visible; history errors SHALL appear beside Reload history, and creation errors SHALL remain in their active dialog.

#### Scenario: The server does not reply
- **WHEN** an inventory or history request receives no reply within its timeout
- **THEN** the action fails visibly instead of remaining indefinitely pending
- **AND** no timeout is interpreted as completion, acknowledgment, or permission approval

### Requirement: JSONL transport preserves responsiveness and connection identity
Pipe reading, linear incremental framing, and JSON decoding SHALL run on a serial worker outside the UI actor. Frames SHALL be limited to 64 MiB, with reads bounded to 64 KiB and decoded delivery paced by UI consumption. Replacing or closing a connection SHALL invalidate its reader and queued callbacks. EOF SHALL drain complete replies before failing remaining requests.

#### Scenario: Fragmented and coalesced replies
- **WHEN** UTF-8 JSON frames span reads or several frames arrive together
- **THEN** the transport reconstructs complete frames once and delivers replies/notifications in source order
- **AND** complete and incomplete oversized frames close the connection without decoding arbitrary unbounded data

#### Scenario: An old reader completes after reconnect
- **WHEN** a replaced connection emits a late reply, notification, or EOF
- **THEN** it cannot affect the new connection or its pending requests

#### Scenario: The server exits after its last reply
- **WHEN** a final complete response is followed immediately by EOF
- **THEN** that response is delivered before the connection reports closure and rejects new requests

### Requirement: Native application lifecycle preserves local state
The app SHALL save workspace state on source switching and application termination, close its owned source connections, and cancel refresh/history/observation work. Closing the last window SHALL terminate the application. It SHALL NOT install an autostart, menu-bar background process, or daemon. --storage SHALL select an alternate Canvas database without changing the source identity rules; routine verification SHALL use the isolated launcher contract.

#### Scenario: Close and reopen the app
- **WHEN** the user closes the final window and later launches again
- **THEN** the app exits, later restores its saved workspace, and refreshes real cached execution evidence before treating it as current
- **AND** transcript pages remain loaded on demand rather than becoming a second durable conversation store
