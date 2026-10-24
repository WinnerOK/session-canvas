# Session Canvas

A personal spatial workspace for observing and organizing Codex sessions and noticing when they need attention.

## Language

**Session**:
A persistent Codex conversation that can contain many successive turns.
_Avoid_: Note, run, task

**Turn**:
One cycle of work in a session, from a submitted instruction until Codex completes, fails, or is stopped; requests for input or permission may pause that work.
_Avoid_: Session, result

**Session note**:
The movable sticky note representing one session on the canvas.
_Avoid_: Session, card, task

**Canvas**:
The spatial workspace containing session notes and project regions.
_Avoid_: Board, project

**Project**:
A named grouping to which a session may belong.
_Avoid_: Region, working directory, repository

**Project region**:
The bounded area on the canvas representing a project.
_Avoid_: Project, folder

**Execution state**:
The current condition of a session's work, including whether Codex is working, needs input, needs permission, or has stopped.
_Avoid_: Note color, acknowledgment

**Result**:
The terminal outcome of a turn, including completion, failure, or interruption.
_Avoid_: Session, successful completion

**Acknowledgment**:
The user's explicit recognition of a particular result as seen while viewing that session; opening it alone is not acknowledgment.
_Avoid_: Permission approval, task completion

**Note state**:
The attention signal shown by a session note, derived from its archive status, execution state, and whether its latest result has been acknowledged.
_Avoid_: Execution state, note color

**Archived**:
A session state confirmed by Codex that takes precedence over execution and result attention until the session is restored.
_Avoid_: Unknown, acknowledged result, deleted session

**Session viewer**:
The view of an existing session and its results within Session Canvas, where the user can explicitly acknowledge a displayed result.
_Avoid_: New session, Codex desktop

**Unassigned space**:
Canvas space outside every project region, representing sessions with no project membership.
_Avoid_: Default project, projectless working directory
