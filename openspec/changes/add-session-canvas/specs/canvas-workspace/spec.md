# Canvas Workspace

## Purpose

Give existing Codex sessions stable spatial homes in a persistent free-roam workspace that the user can navigate and rearrange.

Canvas geometry, visible populations, filters, overview, and gestures below refer to the selected layer defined by [session-layers](../../../add-session-layers/specs/session-layers/spec.md). Source identities, actual memberships, results, and acknowledgments remain shared; explicitly source-wide actions keep that scope.

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

#### Scenario: Project and session content share a zoom boundary
- **WHEN** the user zooms through the point where a session note can no longer fit its compact whole-line text
- **THEN** project member notes switch to their project overview at that same point, while unassigned notes become shapes
- **AND** both decisions account for the minimum scale, title font line height, padding, and reserved state line
- **AND** project members remain drawn, individually clickable, and accessible at every scale where an unassigned note still shows text
- **AND** zooming back in restores member notes at the same boundary without changing saved geometry, membership, or the viewport beyond the requested zoom

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
The user SHALL independently hide applicable attention states and projects within the selected layer. Search, state, and project choices SHALL combine without changing classification, source facts, acknowledgment, or layout. Choices SHALL persist per source and layer. Temporary creation reveal SHALL bypass only its classified layer's filters.

#### Scenario: Filter a layer
- **WHEN** the user hides Running and a project on Active
- **THEN** those exclusions compose with search, while Stale and Inactive keep independent choices
- **AND** state counts ignore their own state exclusions

#### Scenario: Hide and restore a project
- **WHEN** the user hides a project on the selected layer
- **THEN** its region and notes disappear from drawing, sidebar, overview, accessibility, and fit bounds
- **AND** Hidden projects offers restoration with the same saved geometry and remaining filters

#### Scenario: Everything is filtered out
- **WHEN** the selected layer has no visible sessions
- **THEN** the empty state offers Show all in this layer and other layers remain selectable
- **AND** reset clears search and only selected-layer state/project exclusions, preserving selection and the idle cutoff

#### Scenario: Reopen a filtered workspace
- **WHEN** the same source is reopened
- **THEN** its selected layer and per-layer exclusions are restored independently of other sources
- **AND** projects with no visible matching sessions are omitted

### Requirement: Layout survives reopening
The system SHALL persist independent note positions, project bounds, and viewport for each layer within a source. Reopening SHALL restore those layouts and selected layer without resetting to source order. Save failure SHALL be explicit and retryable under session-layers; source-driven failures SHALL not regress authoritative source facts.

#### Scenario: Restore independent layouts
- **WHEN** a project has different bounds and note positions across the three layers
- **THEN** restart restores each layout with current source membership and shared acknowledgment

#### Scenario: A layout cannot be saved
- **WHEN** durable storage rejects an edit or automatic transition
- **THEN** no partial layout is saved and the error identifies unsaved state or a rejected user edit
- **AND** retry retains the prior durable snapshot

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
Title, execution, and acknowledgment changes SHALL preserve position while a session stays on the same layer. Classification changes SHALL use session-layers destination placement within the same actual project. Authoritative project changes SHALL invalidate obsolete remembered membership and relocate the affected note without rearranging unrelated projects.

#### Scenario: Finish and rename within Active
- **WHEN** an Active session receives a terminal result and title change
- **THEN** its note updates at the same Active position

#### Scenario: Return from another layer
- **WHEN** state or age changes a session's layer
- **THEN** its destination uses a valid remembered position or free space inside the same actual project

### Requirement: Inventory gaps do not remove notes
The system SHALL retain known notes during disconnects, incomplete discovery, or unavailable inventory pages. Source removal SHALL require authoritative evidence of deletion or internal-agent exclusion. Archive visibility SHALL use confirmed source archive state and the lifecycle visibility settings, preserving geometry for restoration.

#### Scenario: Refresh fails partway through discovery
- **WHEN** the source disconnects before the final inventory page is read
- **THEN** previously known notes are retained and affected execution state is marked unavailable

#### Scenario: Archive and restore outside the canvas
- **WHEN** the source confirms a known session was archived and subsequently restored
- **THEN** its note enters Inactive and then its derived destination layer, restoring a valid remembered position within current membership or allocating a free one

### Requirement: Persisted archive and idle-age visibility
The selected layer SHALL offer applicable state filters: five Active states, Idle for Stale, and Archived immediately above Unknown for Inactive. Fresh filters SHALL enable applicable states; migration SHALL retain exclusions. Hide Idle after SHALL be shared per source and route eligible Idle to Stale, retaining all existing interval options.

#### Scenario: Show archived sessions
- **WHEN** Inactive is selected and Archived is enabled
- **THEN** confirmed archives appear regardless of missing history, independently of Unknown and the cutoff
- **AND** their result acknowledgment is unchanged

#### Scenario: Expire an Idle session
- **WHEN** eligible Idle activity reaches the configured cutoff
- **THEN** it moves from Active to Stale within 30 seconds without changing source activity or project membership
- **AND** its viewer closes if it leaves the selected layer

#### Scenario: Protect work and unread results
- **WHEN** execution, a pending request, an unread result, Never, or unavailable/future activity prevents age classification
- **THEN** an otherwise non-Inactive session remains Active
- **AND** explicit layer filters still apply

#### Scenario: Migrate old visibility
- **WHEN** an unversioned workspace is converted
- **THEN** legacy archive/state/project exclusions and cutoff are preserved in the applicable per-layer preferences
- **AND** valid geometry and shared acknowledgments are retained atomically

### Requirement: Unknown sessions belong to Inactive
Unknown sessions SHALL belong to Inactive regardless of age, cached unread results, or last-known work. The former Hide unknown age toggle SHALL be removed. Authoritative state recovery SHALL reclassify the same session without acknowledgment or source membership mutation.

#### Scenario: Retain uncertain sessions in Inactive
- **WHEN** the cutoff changes, Never is selected, or Unknown has missing/future activity
- **THEN** Unknown remains in Inactive under that layer's Unknown filter

#### Scenario: Recover current state
- **WHEN** verified latest evidence establishes Running or Finished
- **THEN** the same session enters Active's region for its actual project without automatically selecting Active

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

### Requirement: Search matches session titles without changing stored organization
Find a session SHALL apply a localized case-insensitive substring match to session titles. Empty search SHALL match all titles. Search SHALL compose with attention/project/age visibility, remain transient rather than stored in SQLite, and leave geometry, membership, and acknowledgment unchanged. Changing search SHALL end the temporary creation reveal.

#### Scenario: Find matching titles
- **WHEN** the user enters part of a title with different capitalization
- **THEN** all matching sessions remain eligible under the other visibility filters, including separate sessions with the same title
- **AND** body text, working folders, and project names are not additional search fields

#### Scenario: Clear or restart search
- **WHEN** the user clears search or starts a new application instance
- **THEN** the title restriction is removed without restoring hidden attention states or projects
- **AND** Show all in this layer additionally resets selected-layer attention/project exclusions while preserving the cutoff

### Requirement: Workspace counters explain their scope
Layer counts SHALL show populations before filters; the source total SHALL count all known source sessions. Canvas/project/review counts SHALL use the selected visible layer. Attention counts SHALL apply search/project filters before state exclusions. Source-wide Finished bulk acknowledgment SHALL remain independent of layer selection and visible counts.

#### Scenario: Hide a state
- **WHEN** Finished is hidden on Active
- **THEN** its Attention count still reflects search/project matches, while visible counters exclude it
- **AND** layer population counts and the source total remain unchanged

#### Scenario: Bulk review from another layer
- **WHEN** Acknowledge all is invoked from Inactive
- **THEN** it captures source-wide eligible Finished results, excluding Unknown and Archived
- **AND** resulting Idle age transitions preserve the selected layer and viewport

### Requirement: Native navigation inputs remain discoverable
The app SHALL expose pan/zoom gestures and native shortcuts for creation, refresh, connection settings, fit, and visibility reset. Tab/Shift + Tab SHALL cycle rendered notes and overview projects; Return/keypad Enter SHALL activate focus. Escape SHALL cancel active canvas drag/resize previews. These controls SHALL preserve the corresponding pointer-command behavior.

#### Scenario: Use native gestures and commands
- **WHEN** the user scrolls, drags the background, or uses Space + drag
- **THEN** the canvas pans; pinch or Command + scroll instead zooms around the pointer
- **AND** Command + N creates, Command + R refreshes, Command + comma opens Connection Settings, Command + 0 fits content, and Command + 1 shows all sessions in the selected layer without changing its cutoff

#### Scenario: Navigate without clicking a note
- **WHEN** the canvas has keyboard focus and the user presses Tab or Shift + Tab followed by Return
- **THEN** focus cycles in the corresponding direction through the rendered items and opens the selected note's viewer or zooms into the selected overview project
- **AND** project members replaced by an overview are not separate focus targets

#### Scenario: Cancel a geometry preview
- **WHEN** the user presses Escape while moving a note, moving/resizing a region, or panning by drag
- **THEN** the uncommitted preview is discarded without changing stored geometry or source membership

### Requirement: Note detail adapts to available scale
Notes SHALL adapt from title/state/activity/footer to compact whole-line text or shapes without changing geometry or source facts. Project overviews and note-content omission SHALL share one compact-text fit decision. Detailed footers SHALL prioritize pending moves, result outcome/review status, then working folder/source label. Selection and keyboard focus SHALL have a visible outline.

#### Scenario: Zoom through note detail levels
- **WHEN** the user zooms out from detailed notes
- **THEN** intermediate notes use compact title/state/activity text, and very distant unassigned notes may show only their colored shape
- **AND** detailed notes show state text/icon/color and use the working folder's last component or source label when no result or move is known

#### Scenario: Inspect a reviewed or unread result without opening history
- **WHEN** a note has a known latest result at detailed zoom
- **THEN** it shows Result acknowledged or the terminal outcome with review result, while an archived note shows the outcome without implying acknowledgment
- **AND** a running or requesting note retains its higher-priority state even when its footer describes an older result
