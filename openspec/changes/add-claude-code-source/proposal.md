# Proposal

## Why

The canvas is useful for any local coding agent with many parallel sessions, not only Codex. Claude Code
users run many interactive and background sessions at once and have the same need: see what is running,
what waits for them and which results are unread. Claude Code exposes no app-server protocol, so a
separate source is needed.

## What Changes

- Add a **Claude Code** source mode beside Codex desktop, Shared Codex server and Demo. Codex sources are
  unchanged; the source boundary (`SessionSource`) is reused as designed.
- Discover sessions from Claude Code transcripts, group them by working folder (worktrees join their
  repository; moved folders are found again; sessions started in `~` join the project they worked in;
  a dragged note keeps a locally remembered project; an optional rules file names projects, splits
  container folders into products and matches keywords for sessions without a folder) and present prompts, assistant text and terminal results in the viewer.
- Establish live state from three layers of evidence, most authoritative first: documented status hooks,
  undocumented runtime files as a labeled fallback, then saved transcript state. Unverifiable state stays
  Unknown. A self-check reports hooks that stop reporting.
- Install/remove the status hook from Connection settings with an explicit button and a settings backup.
- Open sessions in a configurable terminal (`claude --resume`, or `claude attach` for background jobs)
  and create sessions with a known identity (`claude --session-id`).
- Remember the last selected source between launches.

## Capabilities

### New Capabilities

- `claude-code-source`: discovery, history, layered live state, hook installation, terminal handoff.

### Modified Capabilities

None. Source selection gains one entry; acknowledgment, layers, geometry and storage are shared and
unchanged. Each source keeps its own workspace identity (`claude-local:<home>`).

## Impact

New: `CanvasCore/ClaudeCode.swift`, `SessionCanvas/ClaudeCodeSource.swift`, `CanvasCoreTests/ClaudeCodeTests.swift`,
`docs/claude-code.md`. Small additive edits: `SessionSource.swift` (mode + optional settings fields),
`ApplicationModel.swift` (source construction, open/create dispatch, hook toggle), `ContentView.swift` and
`NativeCanvasView.swift` (app name in labels, Claude settings section), `SessionCanvasProbe` (count-only probe).
No new dependencies.
