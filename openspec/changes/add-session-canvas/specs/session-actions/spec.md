# Session Actions

## Purpose

Let the user inspect and acknowledge existing session results, continue in Codex, and create sessions in the spatial context where work belongs.

Canvas geometry, visible populations, filters, overview, and gestures below refer to the selected layer defined by [session-layers](../../../add-session-layers/specs/session-layers/spec.md). Source identities, actual memberships, results, and acknowledgments remain shared; explicitly source-wide actions keep that scope.

Explicit creation reveal selects only the confirmed session's derived layer before opening its viewer. Same-layer/same-project creation retains clicked placement and viewport; crossing layers uses destination geometry and explicit focus. An unexpectedly Unknown creation is revealed in Inactive.

## ADDED Requirements

### Requirement: Viewer displays source activity time
The session viewer SHALL display relative last activity and its exact local date and time, using the same source timestamp as the note. Opening the viewer SHALL NOT update source activity or acknowledge the result.

#### Scenario: Inspect last activity
- **WHEN** the user clicks a session note
- **THEN** the viewer shows the same relative activity label plus the full timestamp when available

### Requirement: Archive and restore from the canvas
Session menus and the viewer SHALL offer Archive session or Unarchive session using the source API. Archiving SHALL require a connected capable source and refreshed Idle eligibility with no unreviewed latest result. Local archive state SHALL change only after confirmation. History, geometry, membership, and acknowledgment SHALL be preserved; errors SHALL retain the note.

#### Scenario: Archive reviewed work
- **WHEN** the user archives a currently Idle session with its latest result acknowledged
- **THEN** the same source identity becomes archived and follows the saved visibility settings
- **AND** selecting Inactive allows restoring it to its derived layer, using valid remembered destination geometry

#### Scenario: Archive is unsafe or rejected
- **WHEN** the session is active, Unknown, Finished with an unreviewed result, changes before submission, or the source rejects archive
- **THEN** no optimistic archive or acknowledgment is saved and the current note is retained

### Requirement: Clicking opens the existing session viewer
A primary click on a note, or its keyboard open action, SHALL open a viewer for that same session identity. Returning to the canvas SHALL preserve the viewport and layout. A completed drag SHALL NOT trigger the open action.

#### Scenario: Open and return
- **WHEN** the user clicks a session note and later closes the viewer
- **THEN** the viewer has displayed that existing session and the canvas returns to its previous viewport
- **AND** no new conversation has been created

### Requirement: Session context menus prioritize native opening
The context menu of a real Codex session note SHALL begin with Open in Codex and SHALL omit Open session. Primary click and the keyboard open action SHALL continue to open the local session viewer. Demo notes SHALL omit native Codex navigation because they have no real Codex identity.

#### Scenario: Right-click a session note
- **WHEN** the user right-clicks a real Codex session note
- **THEN** Open in Codex is the first menu item, followed by the other available actions
- **AND** no duplicate local-viewer Open session item appears
- **AND** opening or dismissing the menu alone does not open either viewer or start execution

### Requirement: Viewer shows source history and outcomes
The viewer SHALL show the session title, current note state, and read-only source history/results, ordered from newest at the top to oldest at the bottom. It SHALL distinguish Completed, Failed, and Stopped outcomes, support loading older pages, and report missing content rather than represent it as a successfully loaded result.

#### Scenario: Open the newest messages
- **WHEN** the user opens a session or reloads history with newer entries
- **THEN** the viewer shows the newest entry at the top and older entries below it
- **AND** scrolling the transcript does not move its controls away

#### Scenario: Inspect a failed result
- **WHEN** the user opens a session whose latest turn failed
- **THEN** the viewer shows the available result/error and labels its outcome Failed

#### Scenario: Load older history
- **WHEN** a session's history spans multiple pages and the user requests an earlier page
- **THEN** the viewer loads the requested history without starting or resuming execution
- **AND** older entries are appended below the newer entries without jumping to the bottom

#### Scenario: Result content cannot be loaded
- **WHEN** fetching a result fails
- **THEN** the viewer shows an error and a retry action
- **AND** it does not offer acknowledgment for the unloaded result

### Requirement: Read-only history has a bounded display contract
The viewer SHALL show selectable dialogue, plans, and terminal outcomes with role labels, omitting arbitrary tool payloads and hidden reasoning. Missing response text SHALL use an error or explicit fallback. History SHALL prefer paged API, then unsupported-method legacy fallback, then validated exact local rollout on read failure. Empty loaded history SHALL be explained. Old selection/source replies SHALL NOT replace the current viewer.

#### Scenario: Inspect dialogue alongside tool work
- **WHEN** source history contains user/assistant dialogue, plans, and tool calls
- **THEN** the viewer shows the supported dialogue/plan entries as selectable text and omits arbitrary tool inputs/outputs
- **AND** the terminal outcome remains reviewable even when it has only an error or no recorded response text

#### Scenario: An empty session loads successfully
- **WHEN** history loads successfully without messages
- **THEN** the viewer shows No messages have been recorded yet rather than a load failure or fabricated result

#### Scenario: The history API is older than paginated history
- **WHEN** the server rejects the paged method as unsupported
- **THEN** the adapter uses legacy reading and presents local pages of the returned history through the same viewer controls
- **AND** a rollout fallback validates source path and session identity before showing content

#### Scenario: Switch selection while loading
- **WHEN** the user opens another session or switches sources before a history request returns
- **THEN** the old reply cannot populate or acknowledge the newly selected viewer

### Requirement: Viewer controls remain above history
Acknowledge result or Mark as unread, Open in Codex, Reload history, and pagination controls SHALL remain in a fixed panel above the transcript. The panel SHALL adapt to narrow viewer widths without clipping button labels.

#### Scenario: Scroll in a narrow viewer
- **WHEN** the viewer is narrow and the user scrolls through its transcript
- **THEN** the controls remain visible above the transcript and wrap into additional rows when needed

### Requirement: Acknowledge is available in the viewer header
The top panel SHALL enable Acknowledge only for a Finished session's newest loaded, unacknowledged terminal result. It SHALL remain disabled during history loading and for every other session state. The panel SHALL indicate acknowledged results and announce newer results without silently changing the loaded result targeted by the action. The command SHALL recheck the current state before saving acknowledgment.

#### Scenario: Reverse acknowledgment from the same control
- **WHEN** the targeted result is already acknowledged
- **THEN** the same header button reads Mark as unread and permits reversal in any session state after loading ends
- **AND** when no result is loaded, the known acknowledged latest result can be used without enabling acknowledgment of an unshown unread result

#### Scenario: Latest-history recovery enables explicit review
- **WHEN** opening or reloading the latest history establishes Finished for an Unknown session
- **THEN** the note and viewer share that Finished state and enable Acknowledge after loading the result
- **AND** explicit acknowledgment returns the verified inactive session to Idle, allowing the chosen age filter to hide it without moving its note

#### Scenario: Explicitly acknowledge a result
- **WHEN** the session is Finished, the user chooses Acknowledge for the loaded latest result, and persistence succeeds
- **THEN** that result is shown as acknowledged and its note becomes Idle if no higher-priority state applies

#### Scenario: Another result arrives while reviewing
- **WHEN** a newer result arrives while an older result is being displayed
- **THEN** the viewer indicates that a newer result is available and lets the user view it
- **AND** the currently displayed action continues to target the older result

### Requirement: Open in Codex preserves identity
The viewer SHALL provide Open in Codex using a verified native-navigation mechanism for the exact existing session. Opening in Codex SHALL NOT create or fork a session, start a turn, acknowledge a result, or resolve a request. Navigation failures SHALL be shown with a retry action.

#### Scenario: Continue a waiting session in Codex
- **WHEN** the user invokes Open in Codex for a session waiting for input
- **THEN** the app requests native navigation to that exact session
- **AND** its note remains Waiting for you until the source reports a change

#### Scenario: The native navigation request fails
- **WHEN** Open in Codex cannot dispatch through the configured navigation mechanism
- **THEN** the viewer shows a retryable navigation error and preserves the session's acknowledgment and execution state

#### Scenario: Native navigation settings are invalid
- **WHEN** the configured template omits {id}, yields a scheme other than codex, or no application handles the resulting URL
- **THEN** navigation is rejected with guidance to correct Connection Settings
- **AND** valid navigation percent-encodes the exact session identity before substituting it into the template

### Requirement: Context menu starts creation at the clicked location
Right-clicking canvas background or a project area SHALL offer New session, including in the distant overview when project labels are hidden. Choosing it SHALL open a creation dialog that remembers the clicked world-coordinate location, with the containing region's project selected or no project outside all regions. A keyboard-accessible New session action SHALL provide the same flow.

#### Scenario: Start within a project region
- **WHEN** the user right-clicks empty space inside project A's region and chooses New session
- **THEN** the creation dialog identifies project A and remembers the clicked canvas location

#### Scenario: Start from an area without a readable label
- **WHEN** the user right-clicks a distant project area too small to display text and chooses New session
- **THEN** the same project is selected in the dialog and the world-coordinate creation location is preserved

#### Scenario: Start outside all regions
- **WHEN** the user opens New session in unassigned space
- **THEN** the dialog has no project selected and remembers that location

#### Scenario: Context menu alone has no side effects
- **WHEN** the user opens the context menu and dismisses it without choosing New session
- **THEN** no session is created and no execution begins

### Requirement: Desktop creation confirms project and working context
The desktop creation dialog SHALL accept an optional name and projectless working folder, with explained defaults. Submission SHALL create an empty durable session using confirmed project identity and roots, then show its viewer with Open in Codex. Blank names SHALL become New session; blank projectless folders SHALL receive separate Canvas-owned workspaces. No model turn SHALL start. Canceling SHALL create no session.

#### Scenario: Submit a session in a project
- **WHEN** the user confirms creation in a project whose server identity and roots are available
- **THEN** creation is requested from the same Codex source used for existing sessions
- **AND** saved membership is verified and the viewer offers Open in Codex for the initial instruction
- **AND** no turn, permission override, or approval response is submitted by the canvas

#### Scenario: The connection does not support project creation
- **WHEN** the connected server cannot negotiate the required project APIs
- **THEN** the dialog explains why creation is unavailable without sending an unverified create request

#### Scenario: No execution context is available
- **WHEN** the source cannot resolve a valid working context for the requested session
- **THEN** the dialog asks the user to select one or explains why submission is unavailable
- **AND** no session is silently created in an unrelated directory

#### Scenario: Create without a project
- **WHEN** the user confirms creation with no project and an explicitly selected existing working folder
- **THEN** the session is created without project membership in that folder and opens automatically in Codex without a turn after verification

#### Scenario: Omit both name and folder
- **WHEN** the user submits a projectless session with a blank name and working folder
- **THEN** the app creates a separate working folder in its own application data and assigns the default name New session
- **AND** the session has persisted history that another Codex process can load under the same identity

#### Scenario: An explicit folder is invalid
- **WHEN** the user provides a non-directory or nonexistent working folder
- **THEN** creation fails before submitting a new-session request and does not silently substitute a default folder

#### Scenario: The chosen project is no longer available
- **WHEN** submission cannot confirm the selected project's server identity or working roots
- **THEN** creation fails before submitting a new-session request and the dialog remains available for correction

#### Scenario: Cancel the dialog
- **WHEN** the user cancels a creation dialog before submission
- **THEN** no source session or running turn is created

### Requirement: Creation releases ownership before native continuation
Creation SHALL use a short-lived server process separate from inventory/history. Before reporting readiness, the app SHALL persist history, await creator exit, verify independent resume of the same session without a turn, and await verifier exit. Metadata reads and unsubscribe alone SHALL NOT prove resumability or released ownership.

#### Scenario: Open while the canvas remains connected
- **WHEN** creation and resumability verification succeed while the inventory client remains connected
- **THEN** another Codex process can acquire the same session without a missing-rollout or competing-owner error
- **AND** Canvas offers Open in Codex without closing its own inventory connection or creating another session

### Requirement: Verified creation automatically opens Codex
After verified desktop creation, the app SHALL automatically open the exact returned session in Codex after releasing ownership. The viewer SHALL retain Open in Codex for retries. Unverified creation SHALL report a warning without automatic navigation.

#### Scenario: Automatically continue a newly created session
- **WHEN** creation verifies saved history and releases both child processes
- **THEN** Canvas requests native opening of the same session once, including when its note would otherwise be filtered out
- **AND** the canvas note/viewer remain available on return and no extra session or model turn is created

#### Scenario: Persistence could not be verified
- **WHEN** creation returns an identity with a naming or saved-history verification warning
- **THEN** Canvas retains the note/viewer and shows the warning without automatically opening an unverified session

### Requirement: Created notes use the confirmed session
After creation is confirmed, the canvas SHALL show one note for that source identity on its derived layer within confirmed membership. Same-layer creation SHALL retain valid clicked placement or the nearest vacancy; cross-layer creation SHALL use destination geometry and explicit focus. The note SHALL derive state from actual evidence and remain synchronized with Codex.

#### Scenario: Create and discover the same session
- **WHEN** creation returns a session identity and later inventory synchronization returns that session
- **THEN** the canvas retains a single note at the creation location or its nearest valid placement

#### Scenario: An empty session is omitted from inventory
- **WHEN** the server confirms a durable session but omits it from inventory before its first message
- **THEN** its single note and confirmed project membership remain on the canvas

### Requirement: Created sessions remain visible and actionable
After confirmed creation, the app SHALL select that session's derived layer, reveal it despite that layer's filters, and open its viewer with Open in Codex and a success notice. Saved filters SHALL remain unchanged. Reveal SHALL survive refresh and end on layer/filter/search changes, Apply filters, another creation, or reconnect. The notice SHALL explain filter exceptions and empty-session omission from Codex's list.

#### Scenario: Creation would match a hidden state or project
- **WHEN** a new session would be hidden by Unknown, search, or its selected project's visibility
- **THEN** only that session is temporarily revealed and its viewer remains open after refresh
- **AND** other filtered sessions remain hidden and saved visibility/search choices are unchanged

#### Scenario: Apply the saved filters again
- **WHEN** the user chooses Apply filters, changes search/visibility, creates another session, or reconnects
- **THEN** the previous creation exception ends and any now-hidden viewer closes

#### Scenario: Continue an empty session in Codex
- **WHEN** the created session is absent from Codex's normal list because it has no first message
- **THEN** the creation notice explains this and Open in Codex targets its exact saved identity
- **AND** Canvas does not fabricate a first user message or start a model turn to populate that list

### Requirement: Context creation preserves the clicked location
Same-layer creation SHALL retain valid clicked placement or the nearest vacancy using current-layer geometry, including filtered notes. Within that layer and context project, pan/zoom SHALL survive collision adjustment and viewer resizing. A changed project, changed classified layer, or explicit focus SHALL allow automatic focus; other layers SHALL not supply obstacles or overwrite destination bounds.

#### Scenario: Create a projectless session at a free point
- **WHEN** the user chooses New session here outside projects at a free location on the confirmed session's layer
- **THEN** the note's top-left position is that clicked world coordinate and its screen position remains anchored there
- **AND** creating the session and opening its viewer do not pan or zoom the canvas

#### Scenario: Create while zoomed out or panned
- **WHEN** the user creates on the same classified layer at a valid clicked location with an existing pan or distant zoom
- **THEN** creation preserves that viewport rather than centering or enlarging the note automatically

#### Scenario: A visible or hidden note occupies the requested placement
- **WHEN** the requested placement intersects a visible or hidden note
- **THEN** the new note uses the closest collision-free placement with confirmed membership near the clicked coordinate
- **AND** existing notes, viewport pan, and zoom remain unchanged; the new note does not jump to the global discovery grid
- **AND** refreshing inventory or restarting the app retains that placement

#### Scenario: The chosen project differs from the creation context
- **WHEN** the user changes the project in the dialog or creation confirms different membership
- **THEN** placement is adjusted to the closest valid position with that membership and can be focused at readable detail zoom without moving unrelated geometry

#### Scenario: Opening the viewer changes canvas width
- **WHEN** viewer layout resizes the canvas immediately after explicit focus or focus for a changed project
- **THEN** the note stays centered in the remaining canvas rather than slipping under the viewer
- **AND** a subsequent user pan is not undone by later resizing

### Requirement: Creation failures are shown in the active dialog
A failed creation SHALL keep the dialog open and show its error within that dialog. The app SHALL preserve the form's inputs for correction when retry is permitted, without relying on an alert behind the modal sheet.

#### Scenario: Correct an invalid working folder
- **WHEN** submission rejects a nonexistent explicit folder
- **THEN** the dialog displays the error inline and remains available for correction
- **AND** no source session or replacement session is created

### Requirement: Confirmed creation failures retain identity
After confirmation, naming, saved-history, or navigation failures SHALL retain the existing note and report the failure without creating a replacement.

#### Scenario: Naming fails after creation
- **WHEN** creation returns a session identity but saving its optional name fails
- **THEN** the app retains the existing session's single note and reports the naming failure
- **AND** it does not create a replacement session

#### Scenario: Saved history or native opening cannot be confirmed
- **WHEN** a session identity was returned but independent history resume or native opening fails
- **THEN** the existing note is retained and the failure is shown
- **AND** the app does not invent project membership, claim successful navigation, or create a replacement session

### Requirement: Ambiguous creation is reconciled before retry
The UI SHALL prevent duplicate submission while creation is pending. If a create request may have succeeded but no confirmation arrives, it SHALL show an indeterminate state and reconcile the operation before permitting another creation attempt. It SHALL NOT blindly retry a possibly applied create request.

#### Scenario: A create response is lost
- **WHEN** the source creates a session but its response is lost
- **THEN** the app shows that creation is unconfirmed and attempts to identify the original operation's session
- **AND** it does not automatically create a replacement session

### Requirement: Viewer delegates further execution to Codex
The first-version viewer SHALL provide Open in Codex to continue work, answer input requests, or approve permissions. Reading history and acknowledging a result SHALL perform no such execution actions.

#### Scenario: Inspect a pending permission
- **WHEN** the user opens a Permission required session
- **THEN** the viewer shows the available request information and Open in Codex
- **AND** it does not grant permission through viewing or acknowledgment
