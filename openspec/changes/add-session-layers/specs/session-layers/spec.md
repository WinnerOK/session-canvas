# Session Layers

## Purpose

Separate sessions into exclusive lifecycle layers with independent spatial layouts while preserving their source identity and actual project membership across transitions.

## ADDED Requirements

### Requirement: Every session has one derived layer
Each eligible session SHALL belong to exactly one of Active sessions, Stale sessions, or Inactive sessions. Archived and Unknown note states SHALL classify as Inactive first. Otherwise, Idle sessions excluded by the configured idle-age policy SHALL classify as Stale; all remaining sessions SHALL classify as Active. Layer membership SHALL be derived independently of search and visibility filters.

#### Scenario: Classify the session inventory
- **WHEN** the inventory contains Running, Waiting for you, Permission required, Finished, recent Idle, expired Idle, Archived, and Unknown sessions
- **THEN** the first five categories belong to Active, expired Idle belongs to Stale, and Archived and Unknown belong to Inactive
- **AND** the three populations are disjoint and together contain every eligible session

#### Scenario: Inactive takes precedence over age and cached evidence
- **WHEN** an Archived or Unknown session has an old or recent timestamp, a cached unread result, or last-known work or requests
- **THEN** it belongs only to Inactive until authoritative evidence changes its derived note state
- **AND** classification neither acknowledges a result nor invents execution evidence

### Requirement: Idle age routes sessions to Stale
Hide Idle after SHALL retain Never, 15 minutes, 1 hour, 1 day, 1 week, and 1 month (30 days), persisted per source. Eligible Idle sessions SHALL become Stale when activity age reaches the cutoff, within 30 seconds. Execution, pending requests, and unread results SHALL prevent age classification as Stale. Never, missing activity, and future activity SHALL leave otherwise Idle sessions Active.

#### Scenario: Reach the cutoff
- **WHEN** an otherwise eligible Idle session reaches exactly one week of source inactivity with one week selected
- **THEN** it moves from Active to Stale within 30 seconds without source mutation or manufactured activity
- **AND** it remains available when Stale is selected

#### Scenario: Change the cutoff or protect attention
- **WHEN** the user selects Never, extends the cutoff beyond a session's age, or new work, a request, or an unread result makes a Stale session ineligible for age classification
- **THEN** that session becomes Active and Never leaves Stale empty
- **AND** Unknown and Archived remain Inactive independently of the cutoff

#### Scenario: Activity cannot establish age
- **WHEN** an otherwise Idle session has no activity timestamp or a timestamp in the future
- **THEN** it remains Active and normal activity labels retain their established unavailable or zero-age behavior

### Requirement: Exactly one layer is selected
The workspace SHALL expose a single-choice layer selector with all three labels and population counts. Exactly one layer SHALL supply canvas content, project rows, overview, keyboard/accessibility targets, and Fit to Content bounds. First use SHALL select Active; later openings SHALL restore the selected layer per source. There SHALL be no combined-layer mode.

#### Scenario: Switch to Inactive
- **WHEN** the user selects Inactive while Active is displayed
- **THEN** only matching Inactive sessions and their nonempty project regions are rendered and navigable
- **AND** the other layers' content is absent from hit testing, accessibility, and fit bounds

#### Scenario: Reopen a selected layer
- **WHEN** the app reopens a source whose selected layer was Stale
- **THEN** Stale is selected even if it is empty, and another source retains its independent selection
- **AND** an empty layer offers the other layers without selecting one automatically

### Requirement: Project geometry is independent per layer
The same actual project SHALL have independent region position and size on each layer where it has sessions. Region interiors SHALL not overlap or nest within a layer, including regions hidden by that layer's filters. Regions on different layers SHALL impose no mutual constraints. Moving or resizing one layer's region SHALL preserve other layers' geometry and all source memberships.

#### Scenario: Hidden archived sessions no longer block an Active project
- **WHEN** an Inactive project's region or note occupies coordinates where the user moves or enlarges an Active project region
- **THEN** the edit succeeds if it satisfies Active-layer geometry rules
- **AND** the Inactive layout is unchanged, even when the regions now share coordinates across layers

#### Scenario: Same-layer overlap is rejected
- **WHEN** a project edit intersects another project region on the selected layer, including a filtered region
- **THEN** the edit is rejected and its prior geometry is retained

#### Scenario: Give one project different layouts
- **WHEN** project A is compact and near the origin in Active, large and distant in Stale, and elsewhere in Inactive
- **THEN** switching layers restores each independent region and does not resize or move its counterparts

### Requirement: Spatial operations use current layer occupants
Placement, drop targets, containment checks, region editing, and Rearrange SHALL consider current occupants and regions of the affected layer, including notes hidden by its filters. Region movement SHALL carry only current member notes on that layer. Retained layouts of departed sessions or empty regions SHALL not reserve space. Unassigned notes SHALL remain outside project interiors on their current layer.

#### Scenario: Move a region with filtered and cross-layer members
- **WHEN** the user moves an Active region containing one visible and one filtered Active member while the same project has Stale and Inactive members
- **THEN** both Active members receive the displacement and Stale and Inactive placements stay unchanged
- **AND** shrinking past a filtered Active member or enclosing an Active nonmember remains invalid

#### Scenario: Reuse space after a session leaves
- **WHEN** a session leaves Active and its former placement is retained for a possible return
- **THEN** that placement no longer blocks Active placement, project edits, or Rearrange
- **AND** a retained region with no current members is likewise not an obstacle

### Requirement: Transitions preserve actual project membership
Layer changes SHALL preserve session identity, actual project or unassigned membership, history, activity, execution, requests, and result acknowledgment. An assigned session SHALL appear inside the same project's region on the destination layer, creating that region when absent. An unassigned session SHALL enter destination unassigned space. No layer change SHALL submit a source membership operation.

#### Scenario: Restore an archived session through Stale to Active
- **WHEN** an archived project A session is restored as acknowledged old Idle and later starts new work
- **THEN** it moves from Inactive to Stale to Active, remaining inside project A's region on each destination layer
- **AND** it retains identity and acknowledgment, with no project-assignment request

#### Scenario: Recover Unknown to Finished
- **WHEN** authoritative latest-history evidence changes an Unknown session to Finished for its unread result
- **THEN** it moves from Inactive to Active in its actual project's region
- **AND** it remains unread without opening its viewer

#### Scenario: Change project while on another layer
- **WHEN** Codex authoritatively moves an Inactive session from A to B and the session later becomes Active
- **THEN** it appears inside B on both current and later destination layers as applicable
- **AND** a remembered A placement cannot restore obsolete membership

### Requirement: Destination placement restores valid spatial context
A transitioning session SHALL restore its remembered destination-layer placement only when valid for current membership and occupants. Otherwise it SHALL receive a non-overlapping placement within its destination project or unassigned space. A missing project SHALL be created in free space. An existing full project SHALL expand downward, retaining its origin, width, and current member positions. Blockers SHALL follow the downward cascade below without changing source membership.

#### Scenario: Return to an independently moved project
- **WHEN** a session returns to a destination project whose region moved while the session was away
- **THEN** its remembered project-relative position is restored if valid in the current region
- **AND** the source layer's region size and position are not copied over the destination project

#### Scenario: A saved position was reused or the project is full
- **WHEN** the remembered slot is occupied, outside resized bounds, or associated with an obsolete project, or no destination slot is free
- **THEN** a valid destination slot is allocated, growing the existing project downward when required
- **AND** only blocking same-layer geometry is displaced downward; no note overlaps a current note and all current member centers remain within their project

#### Scenario: First arrival to a layer
- **WHEN** a project session enters a layer with no remembered region for its project
- **THEN** a nonconflicting region is created there and the session is placed inside it
- **AND** existing geometry on other layers is unchanged

### Requirement: Anchored growth displaces a downward cascade
Automatic placement SHALL keep the destination project's origin, width, and existing members fixed. Blocking projects SHALL move as rigid groups; blocking unassigned notes SHALL move individually. Only downward displacement SHALL occur. Planning SHALL include current filtered occupants and full card footprints, exclude other layers and dormant records, preserve viewport and source facts, and publish one complete layout through existing save/retry semantics.

#### Scenario: Propagate collisions through projects and notes
- **WHEN** downward growth or a pushed blocker intersects another current same-layer project or card
- **THEN** affected blocks are resolved in original top-edge order with stable identity ties, each shifted only far enough to clear earlier blocks with a 24-unit gap on a collision
- **AND** each project carries all its current members with unchanged offsets and dimensions, including cards protruding beyond its region
- **AND** blocks outside the cascade retain exact coordinates

#### Scenario: Preserve independent layouts and filters
- **WHEN** a cascade encounters filtered same-layer occupants while another layer or a dormant record uses the same coordinates
- **THEN** filtered occupants participate and the other layer and dormant records remain unchanged
- **AND** search, filters, selection, pan/zoom, execution, requests, memberships, and acknowledgments retain their existing meaning

#### Scenario: Repeat discovery or remove arrivals
- **WHEN** the same inventory is reconciled again, reopened, or arrivals later depart
- **THEN** valid placements and expanded bounds are retained without another cascade or automatic shrink
- **AND** the saved complete layout remains restorable through the existing SQLite snapshot

### Requirement: Automatic transitions preserve layer navigation
Source observations, acknowledgment changes, idle-timeout changes, and clock updates SHALL reclassify affected sessions without switching the selected layer or invoking Rearrange. A viewer SHALL close when its session leaves the selected visible population; stale asynchronous history replies SHALL not reopen it. A drag or resize based on an obsolete layer, population, or geometry SHALL be cancelled or rejected.

#### Scenario: Work resumes while Stale is selected
- **WHEN** a visible Stale session becomes Running
- **THEN** it moves into its Active project layout while Stale remains selected with its existing viewport
- **AND** its viewer closes if open, and Active's population count updates

#### Scenario: Layer membership changes during a gesture
- **WHEN** a note transitions layers or the selected layer changes before a drag or resize commits
- **THEN** the old gesture cannot write coordinates into either layer or trigger a membership mutation
- **AND** the authoritative session state and independently saved layouts remain intact

### Requirement: Visibility controls stay within a layer
Search SHALL remain transient and apply within the selected layer. Attention-state and project visibility choices SHALL persist independently per source and layer, without changing classification or layout. Active SHALL offer its five possible note states, Stale Idle, and Inactive Archived then Unknown. Hide unknown SHALL be removed because Unknown always belongs to Inactive.

#### Scenario: Hide a state in one layer
- **WHEN** the user hides Idle or project A on Active and switches to Stale
- **THEN** Stale retains its own visibility choices and can display its Idle or project A sessions
- **AND** returning to Active restores its saved exclusions

#### Scenario: Reset filters without combining layers
- **WHEN** the user invokes the former All sessions or Show all sessions reset, including Command + 1
- **THEN** the clearly layer-scoped action clears search and selected-layer attention/project exclusions only
- **AND** it preserves the selected layer, global idle cutoff, other layers' choices, and geometry

### Requirement: Counters explain layer and action scope
Layer-selector counts SHALL count each derived population before search and visibility exclusions. The inventory total SHALL remain source-wide. Canvas, project, attention, and review counters SHALL use the selected layer with their existing filter-before-state-exclusion semantics. Acknowledge all SHALL retain its source-wide Finished scope, explicitly explained even when another layer is selected.

#### Scenario: Filter the selected layer
- **WHEN** search or a state/project choice hides selected-layer notes
- **THEN** the layer population counts remain unchanged while visible counts and attention counts follow their documented filter scopes
- **AND** unread Unknown or Archived results do not become Finished bulk-acknowledgment targets

#### Scenario: Acknowledge from Inactive
- **WHEN** the user invokes Acknowledge all while Inactive is selected and source-wide eligible Finished results exist
- **THEN** exactly those Finished results are acknowledged under the established atomic snapshot contract
- **AND** any resulting age transition occurs in the affected layouts without selecting another layer

### Requirement: Creation reveals one classified layer
Creating a session from any layer SHALL retain the chosen actual project and place the confirmed session on its derived layer. If necessary, creation SHALL select that layer before revealing its note and viewer. Temporary reveal SHALL bypass only that layer's filters, never display content from another layer, and leave saved filters unchanged. Native continuation and no-turn creation rules SHALL remain in force.

#### Scenario: Create from an Inactive project area
- **WHEN** the user creates a confirmed Idle session from project A while Inactive is selected
- **THEN** Active is selected and the new session is placed in Active's project A region
- **AND** Inactive's geometry is unchanged and no archived or Unknown notes are revealed on Active

#### Scenario: Create in the selected destination layer
- **WHEN** creation's derived layer and confirmed project match the clicked context
- **THEN** valid clicked placement and current pan/zoom are preserved under the existing nearest-free-placement rules scoped to that layer

### Requirement: Layer layouts and preferences survive reopening
The application SHALL durably save independent per-source layer geometry, viewports, selection, and visibility, with shared source facts and acknowledgments. Save errors SHALL be explicit and retryable. Failed user geometry edits SHALL retain prior geometry. A failed automatic-transition save SHALL retain authoritative source state, publish only a complete valid in-memory layout marked unsaved, and preserve the previous durable snapshot for retry.

#### Scenario: Restore independent layouts
- **WHEN** the user moves or resizes the same project differently on each layer, changes their viewports, and reopens the app
- **THEN** all layer layouts and choices are restored without conflating project identities or duplicating sessions
- **AND** current authoritative source evidence determines which population occupies each saved layout

#### Scenario: Storage fails during a transition
- **WHEN** storage rejects a source-driven transition or a user geometry edit
- **THEN** the app reports the failure without claiming durable success or applying a partial layout
- **AND** source facts do not regress, retry is available, and the previous saved snapshot remains readable

### Requirement: Existing single-layout workspaces migrate safely
Migration SHALL preserve the original workspace, project identities, note coordinates, shared acknowledgment records, idle cutoff, and applicable filter choices. Existing notes SHALL enter their derived layers with valid same-layer geometry. First layered selection SHALL be Active. Hide unknown SHALL not influence classification. Migration SHALL be atomic and repeatable, retaining the original payload for recovery.

#### Scenario: Migrate the current filtered workspace
- **WHEN** a saved workspace contains independent attention/project exclusions, one-week Hide Idle after, and hidden Archived and Unknown sessions
- **THEN** sessions split into their derived layers while each preserves its original coordinates and corresponding project bounds when valid
- **AND** relevant state exclusions and project exclusions are copied to layer preferences, the idle cutoff is retained, and the user can explicitly reveal Inactive states

#### Scenario: Retry or reopen migration
- **WHEN** migration fails to save or an already migrated workspace is reopened
- **THEN** failure retains the readable original without partially converted data, and reopening a migrated workspace does not seed or reset layouts again
- **AND** acknowledgments and other sources are unchanged

### Requirement: Rearrange and overview remain layer scoped
Rearrange SHALL retain its compact square-oriented ordering, packing, validation, and save-before-apply behavior using only the selected layer. Filtered current members SHALL retain offsets while travelling with their participating project; other filtered current geometry SHALL remain fixed. Overview summary and zoom behavior SHALL use only that layer's visible members and saved bounds.

#### Scenario: Rearrange Active with other layers at the same coordinates
- **WHEN** Active is rearranged while Stale and Inactive geometry shares its coordinates
- **THEN** only Active notes and regions are changed, and other layers impose no packing obstacles
- **AND** the selected viewport and source facts remain unchanged

#### Scenario: Summarize a project at distant zoom
- **WHEN** a project has visible Active members and additional members on Stale and Inactive
- **THEN** its Active overview counts and summarizes only its visible Active members using Active's region bounds
- **AND** switching layers uses the destination's independent bounds without an overview-specific reflow
