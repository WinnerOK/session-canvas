# Session Attention

## Purpose

Show which sessions are working or need attention, and preserve notice of a terminal result until the user explicitly acknowledges that result.

## ADDED Requirements

### Requirement: Deterministic note state
The system SHALL derive note state in this priority order: Unknown when current execution cannot be established; Permission required for unresolved permissions; Waiting for you for unresolved input; Running for active execution; Finished for an unacknowledged latest terminal result; otherwise Idle. Each state SHALL have a distinct visual treatment, text label, and icon.

#### Scenario: Permission takes priority over activity
- **WHEN** an executing session has both an unresolved permission request and an unresolved input request
- **THEN** its note displays Permission required

#### Scenario: Acknowledged session is idle
- **WHEN** a session has no active turn or pending request and its latest result is acknowledged
- **THEN** its note displays Idle

#### Scenario: A session has never executed
- **WHEN** a session has no active turn, pending request, or terminal result
- **THEN** its note displays Idle

### Requirement: Terminal evidence creates Finished
The system SHALL recognize completion, failure, and interruption as terminal outcomes only from authoritative source evidence. When no active work or request takes priority, a newly observed terminal result SHALL make the note Finished with a Completed, Failed, or Stopped outcome label.

#### Scenario: Successful work ends
- **WHEN** the source confirms a turn completed and no later work or request is active
- **THEN** the note displays Finished with the Completed outcome

#### Scenario: Work fails or is interrupted
- **WHEN** the source confirms that the latest turn failed or was interrupted
- **THEN** the note displays Finished with the Failed or Stopped outcome respectively
- **AND** the result requires acknowledgment

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
A Finished note SHALL retain its Finished state when its session viewer is opened, focused, scrolled, or closed. The system SHALL require a distinct Acknowledge action while a particular terminal result is displayed.

#### Scenario: Inspect and return without acknowledgment
- **WHEN** the user opens a Finished note, reads its result, and returns to the canvas without choosing Acknowledge
- **THEN** the note remains Finished

### Requirement: Acknowledgment targets the displayed result
The Acknowledge action SHALL record only the identity of the terminal result displayed in the session viewer when the action is taken. It SHALL NOT acknowledge a different result that arrives concurrently. Acknowledgment SHALL be unavailable when no terminal result is displayed.

#### Scenario: A newer result arrives during review
- **WHEN** result A is displayed and result B completes before the user acknowledges A
- **THEN** the action acknowledges only A
- **AND** B remains unacknowledged until displayed and explicitly acknowledged

#### Scenario: There is no result to acknowledge
- **WHEN** the viewer shows a session that has never produced a terminal result
- **THEN** no enabled Acknowledge action is offered

### Requirement: Acknowledgment preserves live attention
Acknowledging a result SHALL clear Finished only when the latest result is acknowledged and no higher-priority state applies. It SHALL NOT change execution, answer an input request, grant permission, or dismiss another unacknowledged result.

#### Scenario: A new turn starts while an older result is viewed
- **WHEN** the user acknowledges the displayed older result while a newer turn is running
- **THEN** the acknowledgment is recorded and the note remains Running

#### Scenario: A permission request remains pending
- **WHEN** the user acknowledges an older result while a permission request is unresolved
- **THEN** the note remains Permission required and no approval is sent

### Requirement: Acknowledgment is durable and repeatable
The system SHALL persist acknowledgment per user, session, and result identity. Repeated acknowledgment of the same result SHALL have no additional effect. A failed save SHALL retain the unacknowledged state and show a retryable error.

#### Scenario: Restart after acknowledgment
- **WHEN** the app restarts after a result was successfully acknowledged
- **THEN** that result remains acknowledged and is not reintroduced as Finished by a repeated source event

#### Scenario: Acknowledgment cannot be saved
- **WHEN** storage fails while saving an acknowledgment
- **THEN** the result remains unacknowledged and the viewer offers retry

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
When execution state is stale or unavailable, the note SHALL show Unknown and indicate its last-known state separately. Disconnects, silence, and source unloading SHALL NOT create terminal results or acknowledgments. Reconnection SHALL reconcile against authoritative current state.

#### Scenario: Lose the source during execution
- **WHEN** observation is lost while a note is Running
- **THEN** it displays Unknown with Running as last known
- **AND** no Finished result is created

#### Scenario: Recover a turn completed while disconnected
- **WHEN** reconnection establishes a previously unseen terminal result
- **THEN** that result is recorded and the note displays Finished if no higher-priority state applies

### Requirement: Repeated and stale observations do not regress state
The system SHALL reconcile observations by source session, turn, result, and revision identity. Duplicate terminal observations SHALL NOT create extra results or reset acknowledgment. A stale observation SHALL NOT override newer authoritative execution or request state.

#### Scenario: A delayed event arrives after another turn starts
- **WHEN** a terminal observation for turn A arrives after turn B is known to be running
- **THEN** A's result is retained without changing B's Running state
