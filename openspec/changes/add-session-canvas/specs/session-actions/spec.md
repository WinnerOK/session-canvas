# Session Actions

## Purpose

Let the user inspect and acknowledge existing session results, continue in Codex, and create sessions in the spatial context where work belongs.

## ADDED Requirements

### Requirement: Clicking opens the existing session viewer
A primary click on a note, or its keyboard open action, SHALL open a viewer for that same session identity. Returning to the canvas SHALL preserve the viewport and layout. A completed drag SHALL NOT trigger the open action.

#### Scenario: Open and return
- **WHEN** the user clicks a session note and later closes the viewer
- **THEN** the viewer has displayed that existing session and the canvas returns to its previous viewport
- **AND** no new conversation has been created

### Requirement: Viewer shows source history and outcomes
The viewer SHALL show the session title, current note state, and read-only history/results from the connected Codex source. It SHALL distinguish Completed, Failed, and Stopped outcomes and support loading older history when paginated. Missing content SHALL be reported rather than represented as a successfully loaded result.

#### Scenario: Inspect a failed result
- **WHEN** the user opens a session whose latest turn failed
- **THEN** the viewer shows the available result/error and labels its outcome Failed

#### Scenario: Load older history
- **WHEN** a session's history spans multiple pages and the user requests an earlier page
- **THEN** the viewer loads the requested history without starting or resuming execution

#### Scenario: Result content cannot be loaded
- **WHEN** fetching a result fails
- **THEN** the viewer shows an error and a retry action
- **AND** it does not offer acknowledgment for the unloaded result

### Requirement: Acknowledge is available beside the displayed result
The viewer SHALL offer an explicit Acknowledge action for a loaded terminal result, applying session-attention's result-specific persistence rules. It SHALL indicate whether that result is already acknowledged. A newly arrived result SHALL be announced without silently changing the identity targeted by the currently displayed action.

#### Scenario: Explicitly acknowledge a result
- **WHEN** the user chooses Acknowledge beside the displayed latest result and persistence succeeds
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

### Requirement: Context menu starts creation at the clicked location
Right-clicking canvas background SHALL offer New session. Choosing it SHALL open a creation dialog anchored to that canvas location, with the containing region's project selected or no project outside all regions. A keyboard-accessible New session action SHALL provide the same flow.

#### Scenario: Start within a project region
- **WHEN** the user right-clicks empty space inside project A's region and chooses New session
- **THEN** the creation dialog identifies project A and remembers the clicked canvas location

#### Scenario: Start outside all regions
- **WHEN** the user opens New session in unassigned space
- **THEN** the dialog has no project selected and remembers that location

#### Scenario: Context menu alone has no side effects
- **WHEN** the user opens the context menu and dismisses it without choosing New session
- **THEN** no session is created and no execution begins

### Requirement: Creation requires a submitted instruction and execution context
The creation dialog SHALL accept an initial instruction and show the intended project and source execution context before submission. It SHALL resolve a valid working context through the source's existing defaults or explicit user selection. Canceling SHALL create no session. An empty instruction SHALL NOT be submitted.

#### Scenario: Submit a valid session
- **WHEN** the user submits a nonempty instruction with valid project and execution context
- **THEN** creation is requested from the same Codex source used for existing sessions
- **AND** the initial instruction is submitted once to that session

#### Scenario: No execution context is available
- **WHEN** the source cannot resolve a valid working context for the requested session
- **THEN** the dialog asks the user to select one or explains why submission is unavailable
- **AND** no execution is silently started in an unrelated directory

#### Scenario: Cancel the dialog
- **WHEN** the user cancels a creation dialog before submission
- **THEN** no source session or running turn is created

### Requirement: Created notes use the confirmed session
After creation is confirmed, the canvas SHALL show one note for the returned source session at the requested location, adjusted only as needed to avoid note collisions and match confirmed membership. The note SHALL derive its state from actual execution evidence and remain synchronized with the same session visible in Codex.

#### Scenario: Create and discover the same session
- **WHEN** creation returns a session identity and later inventory synchronization returns that session
- **THEN** the canvas retains a single note at the creation location or its nearest valid placement

#### Scenario: The session exists but its first turn did not start
- **WHEN** creation returns a session identity but initial-instruction submission fails
- **THEN** the app retains the existing session's single note and shows the submission failure
- **AND** retrying the instruction does not create another session

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
