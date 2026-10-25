# Canvas Workspace

## Purpose

Give existing Codex sessions stable spatial homes in a persistent free-roam workspace that the user can navigate and rearrange.

## ADDED Requirements

### Requirement: Native macOS application
The application SHALL use native SwiftUI/AppKit interfaces on macOS 14 or later, including native window, menu, keyboard, and accessibility integration. The canvas and session viewer SHALL NOT depend on a browser renderer.

#### Scenario: Launch the Mac application
- **WHEN** the user launches the packaged Session Canvas application on a supported Mac
- **THEN** a native window presents the canvas, sidebar, and session viewer without a web renderer

### Requirement: Canvas-first window controls
The application SHALL place New Session, Fit to Content, Full Screen, labeled Rearrange, and Acknowledge all controls in the top window toolbar. The canvas SHALL begin directly below that toolbar without a workspace heading, tagline, or header panel. The left sidebar SHALL be collapsible through the native toolbar toggle and Shift + Command + S.

#### Scenario: Acknowledge from the top bar
- **WHEN** Finished sessions have unacknowledged latest results
- **THEN** Acknowledge all is available in the top toolbar independently of viewer selection and filters
- **AND** it is disabled with no eligible results, during source refresh, or without a connected source/storage

#### Scenario: Collapse and restore the sidebar
- **WHEN** the user toggles the sidebar through the toolbar or keyboard shortcut
- **THEN** the sidebar hides or reappears and the canvas uses the available window space
- **AND** the canvas viewport, note positions, project regions, visibility filters, and open session remain unchanged

### Requirement: Free-roam navigation
The canvas SHALL support panning in every direction, zooming around a focal point, and fitting all visible notes and regions into view. Viewport changes SHALL preserve note and region positions in canvas coordinates.

#### Scenario: Pan and zoom across the workspace
- **WHEN** the user pans beyond the initial viewport and zooms around the pointer
- **THEN** the viewport changes without moving any note or region in the canvas
- **AND** the canvas supports positions on either side of its initial origin

#### Scenario: Recover an off-screen workspace
- **WHEN** the user invokes Fit to content after panning away
- **THEN** all visible notes and project regions fit within the viewport

#### Scenario: Content crosses a viewport edge
- **WHEN** panning or zooming places notes or regions partly outside the canvas
- **THEN** their drawing and shadows are clipped to the canvas without covering the window toolbar, sidebar, or footer

#### Scenario: Zoom out to projects
- **WHEN** the user zooms out until individual project sessions are too small to read
- **THEN** their original project regions replace individual notes, with readable names truncated to fit within those regions
- **AND** visible session counts and attention colors are shown only when additional space is available
- **AND** if even a meaningful truncated name or a full line's height cannot fit, the region is shown without any text
- **AND** project regions and hit areas follow the viewport transform without enlargement, reflow, displacement, or clamping to viewport edges
- **AND** text boxes fit whole lines without clipping letters vertically

#### Scenario: Open a project from the overview
- **WHEN** the user clicks a project area, including one without text, or activates it with the keyboard or assistive technology
- **THEN** the canvas zooms into that project's sessions at a readable scale, even when its region is too tall to fit entirely
- **AND** hidden member notes are not independently clickable in the overview

### Requirement: Existing sessions appear once
At session-detail zoom, the system SHALL display exactly one note for each eligible user session matching the current filters or temporarily revealed after creation. It SHALL use stable source identity, show the current title and note state, and use Untitled session when no title is available. Archived sessions SHALL remain in discovery and retain geometry for optional display and restoration.

#### Scenario: Multiple pages and repeated observations
- **WHEN** discovery returns several pages and later repeats a previously discovered session
- **THEN** all eligible sessions appear once without requiring recreation

#### Scenario: Sessions share a name
- **WHEN** two eligible sessions have the same title
- **THEN** they remain separate notes that open their respective sessions

#### Scenario: A session has no title yet
- **WHEN** a session is discovered without a title
- **THEN** its note displays Untitled session until a title becomes available

### Requirement: Internal agent sessions are excluded without source deletion
Guardian reviews and other internal agent sessions SHALL be excluded using structured source/parent metadata, including previously cached internal notes. A title alone SHALL NOT classify a session as internal. Exclusion SHALL NOT archive or delete the underlying Codex session.

#### Scenario: Remove internal-session clutter from an existing canvas
- **WHEN** discovery identifies a cached note as a Guardian review or another internal sub-agent session
- **THEN** its note and active placement are removed from the canvas without modifying the source session

#### Scenario: An ordinary session has a Guardian title
- **WHEN** a user session has a Guardian review title but no internal source or parent metadata
- **THEN** it remains eligible under the normal visibility filters

### Requirement: Notes can be repositioned
The user SHALL be able to drag a note to a new canvas position. A completed drag SHALL NOT open the session. Crossing a project boundary SHALL use the membership behavior defined by project-regions; movement within the same membership area SHALL only change layout.

#### Scenario: Rearrange notes within a project
- **WHEN** the user drags a note to another position within its current project region and releases it
- **THEN** the new position is retained without a project membership mutation or session opening

#### Scenario: Cancel a drag
- **WHEN** the user cancels a note drag before releasing it
- **THEN** its last confirmed position and membership are restored without a source mutation

### Requirement: Visibility filters combine and persist
The user SHALL be able to independently show or hide each attention state and hide or restore individual projects. Search, attention-state visibility, and project visibility SHALL combine. Visibility choices SHALL persist per source without changing source sessions, memberships, acknowledgments, or note positions. A temporary creation reveal SHALL follow session-actions without changing these saved choices.

#### Scenario: Hide multiple attention states
- **WHEN** the user unchecks Running and Finished
- **THEN** sessions in either state are hidden while sessions in other enabled states remain eligible
- **AND** subsequent state changes reevaluate visibility using the current derived note state

#### Scenario: A project has no visible sessions
- **WHEN** no session in a project matches the current search and visibility choices
- **THEN** the project is omitted from the sidebar, canvas, overview, accessibility navigation, and Fit to Content bounds

#### Scenario: Hide and restore one project
- **WHEN** the user hides a project
- **THEN** its sessions and region disappear from the workspace
- **AND** the Hidden projects menu offers an individual restore action
- **AND** restoration retains its original geometry and still respects search and attention filters

#### Scenario: Everything is filtered out
- **WHEN** the current filters hide all known sessions and no creation reveal is active
- **THEN** an explicit empty view offers Show all sessions to reset visibility and search
- **AND** an open viewer for a hidden session is closed

#### Scenario: Reopen a filtered workspace
- **WHEN** the app reopens the same connected source
- **THEN** saved attention and project visibility choices are restored
- **AND** another source's choices remain independent

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

### Requirement: Explicit visible-session rearrangement
Rearrange SHALL reflow visible notes by Attention order, newest activity, then stable ID, with visible projects first and unassigned notes below. Hidden members SHALL retain project-relative offsets while receiving its displacement; other hidden notes SHALL stay fixed. The command SHALL preserve source facts, acknowledgment, filters, selection, history, and viewport, validate membership/collisions, and save before applying the whole layout.

#### Scenario: Compact holes and repair overlaps explicitly
- **WHEN** status/filter changes left gaps or visible notes overlap hidden notes, and the user invokes Rearrange
- **THEN** visible notes are ordered Running, Waiting for you, Permission required, Finished, Idle, Archived, Unknown, with newer activity first inside each group
- **AND** visible project areas form a compact block before unassigned notes; the same Attention/activity/identity ordering applies within each project
- **AND** reflowed visible notes do not overlap any other note, including hidden ones, and all notes retain their actual memberships

#### Scenario: Carry hidden members without reflowing them
- **WHEN** notes are excluded by attention, project, search, or age filters
- **THEN** hidden members of a participating visible project move by exactly the project's displacement while preserving their internal offsets
- **AND** hidden unassigned notes and projects with no visible notes are unchanged
- **AND** visible notes avoid hidden member footprints, and the project envelope avoids other projects/fixed notes including any protruding hidden footprints
- **AND** preexisting hidden-hidden overlaps within one project remain unchanged

#### Scenario: Persist or reject a complete rearrangement
- **WHEN** rearrangement succeeds
- **THEN** placements and project bounds survive restart, pan/zoom and the viewer stay unchanged, and another invocation with unchanged input produces the same geometry
- **AND** status/activity/filter updates alone do not invoke rearrangement

#### Scenario: A complete plan cannot be saved
- **WHEN** fixed geometry blocks a valid plan or storage rejects it
- **THEN** no partial layout is applied, no member is independently displaced, and an actionable error is shown

#### Scenario: No eligible rearrangement
- **WHEN** there are no visible notes, no connection/storage, or a refresh/create/membership operation is in progress
- **THEN** Rearrange is disabled and invoking its command leaves the workspace unchanged

### Requirement: Compact square-oriented layout
Rearrange SHALL form separate compact project and unassigned-session blocks using adaptive physical-card grids and non-rotating project packing. Candidates SHALL prefer the smallest longer side, then bounding area, then wider orientation. Hidden geometry MAY constrain shape or displace whole blocks. Exact squares and globally minimum area are not required.

#### Scenario: Equal cards form a compact block
- **WHEN** Rearrange arranges six visible unassigned cards without obstacles
- **THEN** it uses two columns and three rows for the current physical card proportions instead of a six-card ribbon
- **AND** larger note sets adapt their columns instead of retaining a fixed six-column limit
- **AND** the same physical-size rule applies inside each project, including its header and padding

#### Scenario: Differently sized projects form one compact block
- **WHEN** visible projects have different envelope dimensions
- **THEN** a bounded set of deterministic packing candidates reuses free spaces and selects by longer side, area, then orientation
- **AND** placement uses descending height, then width, with source/sidebar order breaking equal-size ties
- **AND** projects retain their orientation, membership, and hidden-member offsets while geometric order may differ from sidebar order
- **AND** repeating Rearrange with unchanged input yields the same coordinates

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
The system SHALL retain known notes during disconnects, incomplete discovery, or unavailable inventory pages. Source removal SHALL require authoritative evidence of deletion or internal-agent exclusion. Archive visibility SHALL use confirmed source archive state and the lifecycle visibility settings, preserving geometry for restoration.

#### Scenario: Refresh fails partway through discovery
- **WHEN** the source disconnects before the final inventory page is read
- **THEN** previously known notes are retained and affected execution state is marked unavailable

#### Scenario: Archive and restore outside the canvas
- **WHEN** the source confirms a known session was archived and subsequently restored
- **THEN** its note follows archive visibility settings and is restored to its saved position if that position still matches its membership

### Requirement: Persisted archive and idle-age visibility
Attention SHALL include an Archived checkbox immediately above Unknown, unchecked by default, using the same state filtering as other rows. Visibility SHALL retain Hide Idle after with Never, 15 minutes, 1 hour, 1 day, 1 week, or 1 month (30 days). Choices SHALL persist per source without changing geometry, membership, or acknowledgment. Show all sessions SHALL clear all filters.

#### Scenario: Hide or show archived sessions with missing history
- **WHEN** the user toggles Archived under Attention while an archived session has unavailable execution or local history
- **THEN** its note is hidden or shown using Archived, independently of the Unknown checkbox and the Idle timeout
- **AND** its result remains unacknowledged and its geometry is preserved

#### Scenario: Migrate the former archive visibility control
- **WHEN** saved visibility contains the former hideArchived option or predates archive visibility
- **THEN** the Archived checkbox preserves that option, defaulting to unchecked for older payloads
- **AND** other state/project/age choices are retained, with no second archive visibility control

#### Scenario: Expire an idle session
- **WHEN** a known Idle session reaches the chosen interval since its source activity timestamp
- **THEN** its note leaves the visible set on the next clock update within 30 seconds and its viewer closes
- **AND** new source activity or a higher-priority state makes it eligible again without changing its saved placement

#### Scenario: Protect work and unreviewed results
- **WHEN** age hiding would exclude running execution, a pending input/permission request, or a known unacknowledged result
- **THEN** the age filter keeps it eligible regardless of age, including when the displayed state is Unknown
- **AND** existing explicit attention/project/search filters retain their established semantics

#### Scenario: Restore visibility
- **WHEN** the user checks Archived, chooses Never, or selects Show all sessions
- **THEN** the corresponding hidden notes and nonempty project areas return at their saved positions

### Requirement: Optional age hiding for Unknown
Visibility SHALL include Hide unknown directly below Hide Idle after, checked by default including for old preferences. Its per-source choice SHALL persist and apply the same source-activity cutoff to Unknown. Never SHALL disable age hiding for both Idle and Unknown. Hiding SHALL NOT change source state, acknowledgment, membership, or geometry. The Attention Unknown choice SHALL remain independent.

#### Scenario: Expire stale Unknown sessions by default
- **WHEN** an Unknown session with no active work, pending request, or unacknowledged result reaches the selected activity-age limit
- **THEN** it leaves the visible set within 30 seconds and its open viewer closes
- **AND** counts and project visibility use the same projection without changing its Unknown state or saved placement

#### Scenario: Retain Unknown when age hiding is disabled or unavailable
- **WHEN** Hide unknown is unchecked, the timeout is Never, or the activity timestamp is missing or in the future
- **THEN** Unknown sessions remain eligible under the age filter
- **AND** unchecking Hide unknown restores expired Unknown notes and their project areas at their saved positions

#### Scenario: Restore the saved Unknown preference
- **WHEN** visibility is loaded for the same source after reopening
- **THEN** the saved Hide unknown choice is retained independently of other sources and Attention choices
- **AND** a preference without that field starts checked

### Requirement: Compact source activity age
Each detailed session note SHALL show last source activity using one largest unit: whole minutes, hours, days, then the capped label 1 month ago at 30 days and beyond. Polling, viewing, acknowledgment, and archive changes SHALL NOT manufacture a newer activity timestamp. Labels SHALL refresh within 30 seconds without requiring manual refresh; missing timestamps SHALL display Activity unavailable and SHALL NOT expire a session by age.

#### Scenario: Format activity age
- **WHEN** activity was 15 minutes, 75 minutes, or 25 hours ago
- **THEN** the labels are 15m ago, 1h ago, and 1d ago respectively, with no smaller unit
- **AND** activity from 30 or more days ago displays 1 month ago, and future timestamps clamp to 0m ago

### Requirement: Notes remain understandable without color
Every note SHALL expose its full title and note-state text to assistive technology. The UI SHALL provide a state legend and a keyboard action to open a focused note. Truncated visual titles SHALL have a way to reveal the full title.

#### Scenario: Open a session using the keyboard
- **WHEN** the user focuses a note and invokes its open action
- **THEN** the corresponding session viewer opens and exposes the session's title and state
- **AND** color is not required to determine the note's state
