# Session Attention

## Purpose

Show which sessions are working or need attention, and preserve notice of a terminal result until the user explicitly acknowledges that result.

Canvas geometry, visible populations, filters, overview, and gestures below refer to the selected layer defined by [session-layers](../../../add-session-layers/specs/session-layers/spec.md). Source identities, actual memberships, results, and acknowledgments remain shared; explicitly source-wide actions keep that scope.

## ADDED Requirements

### Requirement: Deterministic note state
The system SHALL derive note state in this order: Archived for confirmed archive status; Unknown when execution is unavailable; Permission required; Waiting for you; Running; Finished for an unacknowledged latest result; otherwise Idle. Each state SHALL have a distinct visual treatment, label, and icon. Archived SHALL retain history and acknowledgment independently of its display state.

#### Scenario: Archived with unavailable execution or history
- **WHEN** Codex confirms a session is archived, including when local history is missing or cached execution/request evidence exists
- **THEN** its note and viewer show Archived with the archive icon, and its Attention count belongs to Archived rather than Unknown
- **AND** an unread terminal result remains unacknowledged

#### Scenario: Restore an archived session
- **WHEN** the source confirms Unarchive
- **THEN** its state is recalculated from execution/request/result evidence, including Unknown when unavailable or Finished for an unread result
- **AND** geometry, history, and acknowledgment are retained

#### Scenario: Read history without archive metadata
- **WHEN** a history response omits archive status and a later inventory page omits the known archived session
- **THEN** its confirmed Archived state is retained until authoritative unarchive evidence arrives
- **AND** reading history alone neither restores nor acknowledges the session

#### Scenario: Permission takes priority over activity
- **WHEN** an executing session has both an unresolved permission request and an unresolved input request
- **THEN** its note displays Permission required

#### Scenario: Acknowledged session is idle
- **WHEN** a non-archived session has no active turn or pending request and its latest result is acknowledged
- **THEN** its note displays Idle

#### Scenario: A session has never executed
- **WHEN** a non-archived session has no active turn, pending request, or terminal result
- **THEN** its note displays Idle

### Requirement: Terminal evidence creates Finished
The system SHALL recognize completion, failure, and interruption as terminal outcomes only from authoritative source evidence. For a non-archived session, when no active work or request takes priority, a newly observed terminal result SHALL make the note Finished with a Completed, Failed, or Stopped outcome label.

#### Scenario: Successful work ends
- **WHEN** the source confirms a turn completed and no later work or request is active
- **THEN** the note displays Finished with the Completed outcome

#### Scenario: Work fails or is interrupted
- **WHEN** the source confirms that the latest turn failed or was interrupted
- **THEN** the note displays Finished with the Failed or Stopped outcome respectively
- **AND** the result requires acknowledgment

### Requirement: Project overview summarizes visible attention
When space permits an attention dot, a project overview SHALL summarize only its visible members using Permission required, Waiting for you, Running, Finished, Archived, Unknown, then Idle priority. This project-level urgency order SHALL NOT replace the deterministic per-session state rules or Attention row order. Its count SHALL be the number of visible member sessions.

#### Scenario: Hidden work does not dominate a visible overview
- **WHEN** a project's permission-requesting session is filtered out and its visible members are Running and Finished
- **THEN** its overview summarizes Running and counts only the visible members
- **AND** restoring the permission-requesting member makes Permission required the overview summary

### Requirement: Waiting is not finishing
The system SHALL use source-reported unresolved input and permission requests to identify waiting states. Pausing for such a request SHALL NOT create a terminal result. It SHALL NOT infer a request solely from words in an assistant message.

#### Scenario: Codex asks a blocking question
- **WHEN** the source reports an unresolved user-input request during a turn
- **THEN** the note displays Waiting for you without creating a Finished result

#### Scenario: A completed answer contains a question
- **WHEN** a turn completes with an ordinary question in its response and the source reports no pending request
- **THEN** the note displays Finished rather than Waiting for you

### Requirement: Requests remain until resolved
An unresolved request SHALL remain part of the note-state calculation until the source confirms resolution or the turn terminates. Resolving one request SHALL NOT clear other unresolved requests. State SHALL be recalculated from the remaining requests and current execution.

#### Scenario: One of several requests is resolved
- **WHEN** the source confirms one permission request was resolved while another permission remains pending
- **THEN** the note remains Permission required

#### Scenario: Execution resumes after a response
- **WHEN** the source confirms the final pending input request was resolved and execution resumed
- **THEN** the note changes from Waiting for you to Running

### Requirement: Opening never acknowledges
A Finished note SHALL retain its Finished state when its session viewer is opened, focused, scrolled, or closed. The system SHALL require a distinct viewer Acknowledge action or the explicit top-bar Acknowledge all action.

#### Scenario: Inspect and return without acknowledgment
- **WHEN** the user opens a Finished note, reads its result, and returns to the canvas without choosing Acknowledge
- **THEN** the note remains Finished

### Requirement: Acknowledgment targets the displayed result
The viewer Acknowledge action SHALL record only the identity of the terminal result displayed when the action is taken. It SHALL NOT acknowledge a different result that arrives concurrently. Viewer acknowledgment SHALL be unavailable when no terminal result is displayed; explicit bulk acknowledgment follows its separate contract.

#### Scenario: A newer result arrives during review
- **WHEN** result A is displayed and result B completes before the user acknowledges A
- **THEN** the action acknowledges only A
- **AND** B remains unacknowledged until separately acknowledged in its viewer or included in a later explicit bulk action

#### Scenario: There is no result to acknowledge
- **WHEN** the viewer shows a session that has never produced a terminal result
- **THEN** no enabled Acknowledge action is offered

### Requirement: Acknowledgment preserves live attention
An accepted acknowledgment SHALL clear Finished only when the latest result is acknowledged. It SHALL NOT change execution, answer an input request, grant permission, or dismiss another unacknowledged result. Existing stored acknowledgments SHALL remain independent of later execution and request states.

#### Scenario: A new turn starts while an older result is viewed
- **WHEN** a newer turn starts while an older result is displayed and an acknowledgment is attempted
- **THEN** the action is unavailable, no new acknowledgment is recorded, and the note remains Running

#### Scenario: A permission request remains pending
- **WHEN** acknowledgment of an older result is attempted while a permission request is unresolved
- **THEN** no acknowledgment or approval is sent and the note remains Permission required

### Requirement: Acknowledgment is available only for Finished sessions
The viewer Acknowledge action SHALL require the selected session to be Finished and the targeted result to be loaded and unacknowledged. Running, Waiting for you, Permission required, Idle, Archived, and Unknown SHALL disable it. The command SHALL recheck eligibility before writing. Explicit bulk acknowledgment may use known latest results without loading viewers; reversing acknowledgment follows Mark as unread.

#### Scenario: An older result remains loaded in another state
- **WHEN** a result remains loaded while the session is Running, Waiting for you, Permission required, Idle, Archived, or Unknown
- **THEN** Acknowledge is disabled and invoking its command does not record an acknowledgment
- **AND** the current session state and pending requests are preserved

#### Scenario: Return to Finished
- **WHEN** a session returns to Finished with a loaded unacknowledged result
- **THEN** Acknowledge becomes available again after history loading completes

### Requirement: Acknowledgment is durable and repeatable
The system SHALL persist acknowledgment per user, session, and result identity until explicitly reversed. Repeated acknowledgment of the same result SHALL have no additional effect. A failed save SHALL retain the previous acknowledgment state and show a retryable error.

#### Scenario: Restart after acknowledgment
- **WHEN** the app restarts after a result was successfully acknowledged
- **THEN** that result remains acknowledged and is not reintroduced as Finished by a repeated source event

#### Scenario: Acknowledgment cannot be saved
- **WHEN** storage fails while saving an acknowledgment
- **THEN** the result remains unacknowledged and the viewer offers retry

### Requirement: Explicit bulk acknowledgment
Acknowledge all SHALL atomically record the latest known unread result of every current-source Finished session, including filtered sessions, without opening history. It SHALL recheck eligibility at invocation, capture exact session/result identities, and exclude every other state. Failure SHALL preserve all prior records and UI state. The action SHALL NOT change execution, requests, activity, membership, geometry, filters, or results arriving after the captured snapshot.

#### Scenario: Review all known Finished results
- **WHEN** the user invokes Acknowledge all with Finished sessions hidden by search, attention, or project filters
- **THEN** each eligible latest result is recorded in one transaction without requiring viewer selection/history
- **AND** eligible notes derive Idle and normal age/visibility filters apply, while Running, requests, Unknown, Archived, no-result sessions, and other sources remain untouched

#### Scenario: A result arrives after the bulk action
- **WHEN** another result appears after the action captured its targets
- **THEN** it remains unacknowledged and derives Finished when no higher-priority state applies
- **AND** repeated bulk invocation with no eligible targets has no effect

#### Scenario: A bulk write fails partway
- **WHEN** storage rejects one acknowledgment after earlier inserts in the same batch
- **THEN** all inserts from that batch roll back, existing records remain, and the UI reports a retryable failure without clearing attention

### Requirement: Reverse explicit acknowledgment
The viewer SHALL offer Mark as unread on the same button for an acknowledged displayed result, or its known latest result when history is unavailable. It SHALL remove only that source/session/result record in any session state after rechecking identity and acknowledgment. It SHALL be disabled during loading and preserve all source facts, other acknowledgments, and geometry. A failed deletion SHALL preserve the previous record and show an error.

#### Scenario: Mark an acknowledged result unread
- **WHEN** the user selects Mark as unread for an acknowledged result
- **THEN** that acknowledgment is durably removed and an inactive latest result becomes Finished again
- **AND** Running, pending requests, Unknown, and Archived keep their derived state; newer/other results are unchanged
- **AND** the same control offers Acknowledge result again when its normal Finished/loaded eligibility applies

#### Scenario: History is unavailable for an acknowledged session
- **WHEN** the viewer knows the acknowledged latest result but cannot load transcript history
- **THEN** Mark as unread remains available after loading ends without requiring a history RPC or source mutation
- **AND** an unrelated unshown result cannot be used as its target

### Requirement: Each new result needs acknowledgment
Starting a later turn SHALL give current execution or requests display priority without erasing prior acknowledgments. A later terminal result SHALL require its own acknowledgment. On first discovery, the latest known terminal result SHALL be unacknowledged unless this app already holds its acknowledgment.

#### Scenario: A session runs again
- **WHEN** a previously acknowledged session starts and completes another turn
- **THEN** the note displays Running during execution and Finished for the new result after it ends

#### Scenario: Import historical sessions
- **WHEN** the app first discovers an inactive existing session with a known terminal result
- **THEN** the note displays Finished until that result is explicitly acknowledged
- **AND** merely having opened it in Codex previously is not treated as acknowledgment

### Requirement: Missing execution evidence is Unknown
When neither current execution nor verified latest-history evidence establishes a non-archived session's state, the note SHALL show Unknown and indicate its last-known state separately. A confirmed archived session SHALL remain Archived. Disconnects, silence, and source unloading SHALL NOT create terminal results or acknowledgments. Reconnection SHALL reconcile against authoritative current state.

#### Scenario: Reopen while a permission request was pending
- **WHEN** Canvas restarts or loses observation after recording work or input/permission requests
- **THEN** the same-source cache retains last-known execution, each request identity/kind, and the active turn identity separately from current evidence
- **AND** metadata-only inventory, failed refresh, and repeated restarts do not erase that observation
- **AND** an unverified session remains Unknown in Inactive, with its last-known state on the note, in accessibility text, and in the viewer with guidance to check Codex
- **AND** a fresh current observation supersedes that hint; history can resolve its pending requests only when the terminal result belongs to the recorded active turn
- **AND** missing turn identity or an older terminal result does not silently convert the cached waiting session to Idle or Finished

#### Scenario: Recover saved terminal state during discovery
- **WHEN** an unloaded session has identity-verified saved evidence whose latest work is terminal
- **THEN** discovery loads its stable result identity before opening the viewer and displays Finished until explicit acknowledgment, then Idle
- **AND** the viewer identifies saved-history provenance and a current desktop observation overrides it
- **AND** a later start, ambiguous tail, incomplete terminal append, missing history, or unsupported evidence remains Unknown
- **AND** bulk file reads are bounded, cache invalidates on file changes as well as source revision, and no turn is resumed or submitted

#### Scenario: Recover Finished while reading the latest history
- **WHEN** the latest paged or legacy history response confirms its last turn completed, failed, or was interrupted, with no newer work or pending request
- **THEN** a non-archived Unknown session becomes Finished for that unacknowledged result even if its local rollout is unavailable
- **AND** the viewer identifies saved-history provenance, explicit acknowledgment becomes available after loading, and opening alone never acknowledges the result
- **AND** unchanged source revision/file evidence retains the recovered state across ordinary refresh without per-session discovery RPCs or manufactured activity

#### Scenario: A historical result is not the latest work
- **WHEN** the newest raw turn is unfinished or unsupported, the latest response is empty, or a terminal result occurs only in an older page
- **THEN** that result alone does not establish saved Idle or Finished
- **AND** an older terminal turn cannot hide newer work or a pending input/permission request

#### Scenario: State changes during a history read
- **WHEN** a history reply predates known source metadata, source metadata/results or the exact rollout change in flight, or the workspace session changes while loading
- **THEN** the reply does not replace newer execution, requests, or result identity with saved completion
- **AND** known archive status, project membership, placement, and acknowledgments remain intact

#### Scenario: Observe the active desktop runtime
- **WHEN** an existing session runs or changes its pending requests in Codex desktop
- **THEN** the default connection follows that runtime's snapshots and incremental changes automatically
- **AND** a saved-inventory response of `notLoaded` from a separate reader does not erase current live observations
- **AND** observation does not claim thread ownership, resume a thread, submit a turn, or answer a request

#### Scenario: Desktop echoes subscriptions
- **WHEN** the desktop echoes this observer's subscription or another observer repeats its following announcement
- **THEN** this observer ignores its own echo and refollows at most once per other owner until that owner disconnects or stops following
- **AND** socket writes do not block the main UI thread

#### Scenario: Reconnect to the desktop feed
- **WHEN** the desktop observation socket closes or a revision gap is detected
- **THEN** affected sessions become Unknown until a fresh authoritative snapshot is received
- **AND** reconnection happens automatically while saved history remains available
- **AND** unsupported desktop stream versions are not treated as live-state evidence

#### Scenario: Lose the source during execution
- **WHEN** observation is lost while a note is Running
- **THEN** it displays Unknown with Running as last known
- **AND** no Finished result is created

#### Scenario: Recover a turn completed while disconnected
- **WHEN** reconnection establishes a previously unseen terminal result
- **THEN** that result is recorded and the note displays Finished if no higher-priority state applies

### Requirement: Automatic recovery for cached terminal results
After discovery, the system SHALL automatically recheck non-archived Unknown sessions with a cached terminal result and missing local evidence. It SHALL use one sequential worker with at least one second between logical checks, reuse latest-history validation, cache attempts by source/file/result revision, and cancel on disconnect. Updates SHALL NOT open viewers, acknowledge results, or reload the full inventory per check.

#### Scenario: Resolve unopened cached-result sessions
- **WHEN** the confirmed source inventory contains Unknown sessions with saved Completed results but no local history
- **THEN** discovery returns before background checks, and each verified terminal latest turn updates its note to Finished without opening that session
- **AND** counts and visibility update immediately while selection, history, activity, project membership, geometry, and acknowledgment are preserved
- **AND** cached results come only from the same source identity and do not themselves prove completion

#### Scenario: Bound automatic history recovery
- **WHEN** multiple cached-result sessions need checking
- **THEN** at most one check is in flight, checks start at least one second apart, and repeated snapshots coalesce queued sessions
- **AND** paged APIs request one latest turn; legacy fallback discards full transcript entries instead of retaining a second history cache
- **AND** active/requesting, archived/internal, no-result, and known later-local-work sessions are excluded
- **AND** an explicit verification session scope also limits background checks

#### Scenario: Cache errors and invalidate changed evidence
- **WHEN** an automatic check succeeds or fails for the same source revision, rollout fingerprint, and result identity
- **THEN** ordinary refresh does not repeat it; a failure leaves the note Unknown without an automatic retry loop
- **AND** changed evidence or reconnect permits a new check; manual latest-history reload remains available

#### Scenario: Close during automatic recovery
- **WHEN** the source closes, reconnects, or loses its RPC connection with queued or in-flight checks
- **THEN** the worker stops and delayed replies do not publish into the current workspace
- **AND** background recovery never resumes a turn, navigates to Codex, answers a request, or acknowledges a result

### Requirement: Repeated and stale observations do not regress state
The system SHALL reconcile observations by source session, turn, result, and revision identity. Duplicate terminal observations SHALL NOT create extra results or reset acknowledgment. A stale observation SHALL NOT override newer authoritative execution or request state.

#### Scenario: A delayed event arrives after another turn starts
- **WHEN** a terminal observation for turn A arrives after turn B is known to be running
- **THEN** A's result is retained without changing B's Running state
