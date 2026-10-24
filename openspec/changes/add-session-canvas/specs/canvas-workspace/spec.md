# Canvas Workspace

## Purpose

Give existing Codex sessions stable spatial homes in a persistent free-roam workspace that the user can navigate and rearrange.

## ADDED Requirements

### Requirement: Native macOS application
The application SHALL use native SwiftUI/AppKit interfaces on macOS 14 or later, including native window, menu, keyboard, and accessibility integration. The canvas and session viewer SHALL NOT depend on a browser renderer.

#### Scenario: Launch the Mac application
- **WHEN** the user launches the packaged Session Canvas application on a supported Mac
- **THEN** a native window presents the canvas, sidebar, and session viewer without a web renderer

### Requirement: Free-roam navigation
The canvas SHALL support panning in every direction, zooming around a focal point, and fitting all visible notes and regions into view. Viewport changes SHALL preserve note and region positions in canvas coordinates.

#### Scenario: Pan and zoom across the workspace
- **WHEN** the user pans beyond the initial viewport and zooms around the pointer
- **THEN** the viewport changes without moving any note or region in the canvas
- **AND** the canvas supports positions on either side of its initial origin

#### Scenario: Recover an off-screen workspace
- **WHEN** the user invokes Fit to content after panning away
- **THEN** all visible notes and project regions fit within the viewport

### Requirement: Existing sessions appear once
The system SHALL display exactly one note for each non-archived session in the connected local source's supported inventory. It SHALL identify notes by stable session identity, show the session's current title and note state, and use Untitled session when no title is available.

#### Scenario: Multiple pages and repeated observations
- **WHEN** discovery returns several pages and later repeats a previously discovered session
- **THEN** all eligible sessions appear once without requiring recreation

#### Scenario: Sessions share a name
- **WHEN** two eligible sessions have the same title
- **THEN** they remain separate notes that open their respective sessions

#### Scenario: A session has no title yet
- **WHEN** a session is discovered without a title
- **THEN** its note displays Untitled session until a title becomes available

### Requirement: Notes can be repositioned
The user SHALL be able to drag a note to a new canvas position. A completed drag SHALL NOT open the session. Crossing a project boundary SHALL use the membership behavior defined by project-regions; movement within the same membership area SHALL only change layout.

#### Scenario: Rearrange notes within a project
- **WHEN** the user drags a note to another position within its current project region and releases it
- **THEN** the new position is retained without a project membership mutation or session opening

#### Scenario: Cancel a drag
- **WHEN** the user cancels a note drag before releasing it
- **THEN** its last confirmed position and membership are restored without a source mutation

### Requirement: Layout survives reopening
The system SHALL persist note positions, project-region bounds, and viewport for this user's canvas. Reopening the app SHALL restore that layout without resetting it to source listing order. A failed layout save SHALL be visible and offer a retry.

#### Scenario: Restore the same workspace
- **WHEN** the user closes and reopens the app after rearranging the canvas
- **THEN** its saved notes, regions, and viewport are restored
- **AND** latest session metadata is reconciled without resetting unrelated positions

#### Scenario: A position cannot be saved
- **WHEN** durable layout storage rejects a note movement
- **THEN** the app indicates that the position is unsaved and offers retry
- **AND** it does not report the layout as durably saved

### Requirement: New sessions receive predictable placement
The system SHALL place newly discovered notes without covering existing notes, within their project's region or in unassigned space. It SHALL create a region for a newly discovered project, expanding that region when space is needed without overlapping another region.

#### Scenario: Discover an additional project session
- **WHEN** a previously unseen session belongs to a project already represented on the canvas
- **THEN** its note is placed in available space in that region without rearranging existing notes

#### Scenario: Discover a new project
- **WHEN** a session's project has no region yet
- **THEN** the app creates a region in available canvas space and places the note inside it

### Requirement: Updates preserve spatial context
Session title, execution, and acknowledgment updates SHALL refresh the existing note without changing its position. Authoritative membership changes SHALL relocate only the affected note as defined by project-regions.

#### Scenario: A session finishes and is renamed
- **WHEN** a known session receives a new title and a terminal result
- **THEN** its existing note updates its title and state at the same position

### Requirement: Inventory gaps do not remove notes
The system SHALL retain known notes during disconnects, incomplete discovery, or unavailable inventory pages. It SHALL hide a note only on authoritative evidence that its session is archived or removed, preserving layout for sessions that later return.

#### Scenario: Refresh fails partway through discovery
- **WHEN** the source disconnects before the final inventory page is read
- **THEN** previously known notes are retained and affected execution state is marked unavailable

#### Scenario: Archive and restore outside the canvas
- **WHEN** the source confirms a known session was archived and subsequently restored
- **THEN** its note is hidden while archived and restored to its saved position if that position still matches its membership

### Requirement: Notes remain understandable without color
Every note SHALL expose its full title and note-state text to assistive technology. The UI SHALL provide a state legend and a keyboard action to open a focused note. Truncated visual titles SHALL have a way to reveal the full title.

#### Scenario: Open a session using the keyboard
- **WHEN** the user focuses a note and invokes its open action
- **THEN** the corresponding session viewer opens and exposes the session's title and state
- **AND** color is not required to determine the note's state
