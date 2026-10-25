# Project Regions

## Purpose

Represent real Codex projects as spatial regions and let the user change session membership through deliberate note placement.

Canvas geometry, visible populations, filters, overview, and gestures below refer to the selected layer defined by [session-layers](../../../add-session-layers/specs/session-layers/spec.md). Source identities, actual memberships, results, and acknowledgments remain shared; explicitly source-wide actions keep that scope.

## ADDED Requirements

### Requirement: Regions represent actual projects
The selected layer SHALL display one independently positioned and sized region per visible source project, using stable project identity and the current name when text fits under canvas-workspace's zoom rules. Project visibility SHALL follow combined search, attention, and individual-project filters; projects with no visible sessions SHALL be omitted. Each session SHALL belong to zero or one project. Visible unassigned sessions SHALL appear outside every region.

#### Scenario: Discover existing membership
- **WHEN** initial synchronization discovers projects and their sessions
- **THEN** every project with visible sessions has a region and each visible assigned session's note is placed within its region at session-detail zoom
- **AND** visible sessions with no project are placed in unassigned space

#### Scenario: A project is renamed
- **WHEN** the source changes a project's name
- **THEN** the existing region's label changes without creating another region or resetting its bounds

#### Scenario: Preserve source project order in the sidebar
- **WHEN** saved local metadata provides project-order entries
- **THEN** the sidebar retains that order for visible projects, placing remaining projects afterward by localized name and stable identity
- **AND** visibility changes do not rename or reorder the underlying project catalog

### Requirement: Project discovery uses explicit source identity
Projects and memberships SHALL use explicit source identity, never cwd/name matching. Explicit desktop membership SHALL precede backend fallback. Backend null/different membership and legacy Canvas confirmations SHALL NOT override desktop assignments or explicit projectless markers. Remote/unknown exclusions SHALL persist. Unsupported metadata SHALL retain confirmed state and report an error. Desktop/server mapping SHALL use only the connected local home.

#### Scenario: A session shares a project's working folder
- **WHEN** a session has the same working folder as a project but no explicit membership, or is explicitly projectless
- **THEN** it remains unassigned rather than being grouped by its folder

#### Scenario: New server membership precedes saved desktop assignment
- **WHEN** the server reports a session project with no explicit desktop membership or projectless marker
- **THEN** the session uses that existing canvas project identity without creating a duplicate region
- **AND** another home's mapping cannot assign it to that project

#### Scenario: API null accompanies an existing desktop assignment
- **WHEN** discovery reports no backend project for a session explicitly assigned in desktop metadata
- **THEN** that session retains its desktop project and its visible project area remains available
- **AND** an older flattened Canvas cache is reconciled back to desktop membership without source mutation

#### Scenario: A legacy backend-only confirmation is restored
- **WHEN** an old Canvas snapshot contains a project confirmation whose backend value differs from explicit desktop membership
- **THEN** synchronization uses the actual desktop project or projectless marker and clears the confirmation
- **AND** cached results, acknowledgment identities, execution, and source identity remain independent of that repair

#### Scenario: Saved project metadata is malformed
- **WHEN** project metadata cannot be validated during refresh
- **THEN** existing confirmed canvas data is retained and the failure is shown

### Requirement: Region geometry has one drop target
Occupied regions SHALL be rectangular with non-overlapping interiors and no nesting within one layer. Geometry on other layers and dormant empty regions SHALL impose no collision constraint. A note's target SHALL be the region whose interior contains its center at pointer release in canvas coordinates. A center on a boundary or outside every region SHALL target unassigned space. The UI SHALL preview the target during dragging.

#### Scenario: A note partially overlaps a region
- **WHEN** part of a note overlaps a region but its center is outside the region at drop
- **THEN** the target is unassigned space

#### Scenario: A drop happens while zoomed
- **WHEN** the user drops a note at any zoom level
- **THEN** the same canvas-coordinate center rule determines the target independently of zoom

#### Scenario: A center lies exactly on an edge
- **WHEN** the note center is exactly on a region boundary at pointer release
- **THEN** the preview and final target both indicate unassigned space

### Requirement: Dropping assigns or removes actual membership
On a source supporting confirmed membership changes, a completed drop into a different region SHALL request reassignment to that actual Codex project, and a drop outside all regions SHALL request removal of membership. The app SHALL NOT substitute a canvas-only grouping when actual membership cannot be changed.

#### Scenario: Assign an unassigned session
- **WHEN** the user drops an unassigned note into project A's region and the source confirms assignment
- **THEN** the same session belongs to A in Codex and its note remains in A's region

#### Scenario: Move directly between projects
- **WHEN** the user drops an A session into B's region
- **THEN** the app requests direct reassignment from A to B without a deliberate intermediate unassignment

#### Scenario: Backend persistence does not establish desktop move support
- **WHEN** thread/metadata/update and backend readback can confirm projectId but the running Codex desktop does not apply that membership
- **THEN** the connection does not advertise project-move support and rejects cross-membership actions before sending a write
- **AND** the app does not use a cached local confirmation to substitute a Canvas-only project change

#### Scenario: A future API confirms a real desktop transition
- **WHEN** an API is demonstrated to change the same chat's actual desktop membership
- **THEN** support can be enabled only with independent desktop readback, preserved identity and execution context, and failure/conflict handling
- **AND** UI automation and direct rewriting of Codex metadata are not substituted for the user's API-only integration

#### Scenario: A normal native launch reports a recent server version
- **WHEN** initialization reports a recent desktop or session_canvas user agent and project APIs are available
- **THEN** these facts alone do not enable project mutation without demonstrated desktop membership support

#### Scenario: Remove a session's project
- **WHEN** the user drops an assigned note into unassigned space and the source confirms removal
- **THEN** the session has no project in Codex and its note remains outside every region

### Requirement: Unsupported membership changes do not alter grouping
When a connection cannot confirm actual membership mutations, move-to-project controls SHALL be disabled and cross-membership drops SHALL preserve confirmed placement with an explanation. Local movement within the same membership area and region geometry editing SHALL remain available.

#### Scenario: Cross a project boundary with an unsupported source
- **WHEN** a user drops a note across a membership boundary on a connection without verified move support
- **THEN** the note keeps its confirmed membership and position and the app explains the unavailable action
- **AND** no source mutation or canvas-only reassignment is submitted

### Requirement: Membership requires confirmation
While a membership change is pending, the UI SHALL show a pending indicator, retain confirmed coordinates, and prevent another membership change for that session. On success it SHALL commit the placement. On rejection it SHALL retain confirmed placement or reconcile newer source membership and explain the failure.

#### Scenario: The source rejects a project move
- **WHEN** an assignment operation is rejected, including because the source forbids moving that active session
- **THEN** the note returns to its confirmed project and position
- **AND** the error identifies the rejected action and provides a retry when applicable

#### Scenario: The outcome is unknown
- **WHEN** the source connection fails after a membership request may have been applied
- **THEN** the placement is marked unconfirmed and reconciled against source membership
- **AND** the mutation is not blindly repeated

### Requirement: Project moves preserve execution context
Assigning or removing project membership SHALL preserve the session identity, current working directory, checkout, active turn, and execution/approval policies. A source operation that requires changing those properties SHALL be rejected as an unsupported project move.

#### Scenario: Organize a running session
- **WHEN** an allowed running session is moved between project regions
- **THEN** its active turn continues in the same execution context with only project membership changed

### Requirement: External membership changes reconcile placement
An authoritative membership change made outside the canvas SHALL relocate the affected note into the destination region or unassigned space without moving unrelated notes. If membership changes externally during a drag, the stale drop SHALL be rejected and current source membership displayed.

#### Scenario: Codex moves a session to another project
- **WHEN** the source confirms that a session moved from A to B outside the canvas
- **THEN** its note is relocated to available space in B's region and other notes retain their positions

#### Scenario: External change races with a drop
- **WHEN** a session changes project externally after its drag began but before its drop is applied
- **THEN** the app rejects the stale drop and reconciles the note to the authoritative membership

### Requirement: Region editing preserves membership
The user SHALL be able to move and resize regions. Manual region movement SHALL carry all current member notes on the affected layer by the same displacement. Resizing SHALL retain all member-note centers. Edits SHALL reject region overlaps or enclosed nonmember centers. Explicit Rearrange SHALL translate hidden members with their project while reflowing only visible members. Geometry edits SHALL NOT issue membership mutations.

#### Scenario: Move an entire region
- **WHEN** the user moves a region to a nonconflicting position
- **THEN** all its current member notes on that layer move by the same displacement with no project membership changes

#### Scenario: Move a project while zoomed out
- **WHEN** the user drags any part of a project area in the overview, including an area too small for a label
- **THEN** its area and label preview the movement and the region commits on release
- **AND** all current member notes on that layer move by the same canvas-coordinate displacement, including filtered members
- **AND** the viewport and unrelated projects remain unchanged
- **AND** clicking without dragging still zooms into the project, Escape cancels the drag, and Space + drag pans the canvas
- **AND** existing region collision and membership-preservation rules still apply

#### Scenario: Resize past a member
- **WHEN** the user attempts to shrink a region so that a member-note center would be outside it
- **THEN** the edit is rejected with feedback and its previous geometry is retained

#### Scenario: Sweep over an unassigned note
- **WHEN** a region edit would enclose an unassigned note's center
- **THEN** the edit is rejected and that note remains unassigned

### Requirement: Source project removal is reconciled
When the source removes a project, the canvas SHALL reconcile its sessions' current memberships before removing the obsolete region. Notes SHALL be retained or hidden according to authoritative session state, without deleting sessions or inventing replacement projects.

#### Scenario: A project disappears while its sessions remain
- **WHEN** the source confirms project A was removed and its sessions are now unassigned
- **THEN** their notes move to unassigned space and A's region is removed

### Requirement: Membership has a keyboard alternative
The UI SHALL provide an accessible move-to-project action and a remove-from-project action that use the same confirmation, execution-context, and reconciliation rules as note drops.

#### Scenario: Assign without dragging
- **WHEN** the user chooses project B through a focused note's accessible project action
- **THEN** the same confirmed reassignment occurs and the note is placed in available space in B's region
- **AND** an explicitly chosen hidden/empty project may be targeted without treating an invisible spatial region as a drop target
