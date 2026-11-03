# Claude Code source

Session Canvas can show local [Claude Code](https://docs.claude.com/en/docs/claude-code) sessions on
the same canvas, alongside the existing Codex sources. Choose **Claude Code** in the source menu at the
bottom of the sidebar or in **Connection settings**. The Codex sources are unchanged.

## What it reads

| Need | Where it comes from |
| --- | --- |
| Session list, title, working folder | Transcripts in `~/.claude/projects/*/<session-id>.jsonl` (only the head and the last 4 MB of each file are read; unchanged files are cached by size and modification time) |
| Projects | The session's launch folder; Claude Code worktrees (`…/.claude/worktrees/<name>`) are grouped with their repository. A folder moved since the session was recorded is found again through the history location. Sessions started in the home folder are grouped with the project they mostly worked in (see below) |
| History in the viewer | User prompts and assistant text from the transcript. Tool payloads and reasoning are excluded. Very long sessions show their most recent 48 MB |
| Latest result | The last assistant answer whose turn ended (`stop_reason` other than `tool_use`); an interrupted turn is *Stopped*, an API error *Failed* |
| Live state | See below |

Session Canvas never writes Claude Code transcripts or runtime files. The only Claude Code file it can
change is `~/.claude/settings.json`, and only when you press **Install status hooks** / **Remove status
hooks** (a timestamped backup is written next to it first).

## Live state: three layers of evidence

Claude Code updates frequently and has no public API for third-party status. Session Canvas therefore
prefers its documented extension point and treats everything else as a fallback:

1. **Status hooks (recommended).** [Hooks](https://docs.claude.com/en/docs/claude-code/hooks) are a
   documented, versioned contract. The installer adds one tiny shell script
   (`~/Library/Application Support/Session Canvas/claude-status-hook.sh`) to these events:
   `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `Notification`
   (`permission_prompt`, `elicitation_dialog`, `idle_prompt`), `Stop`, `SubagentStop`, `PreCompact`,
   `SessionEnd`. For each event it atomically writes the raw hook payload plus the Claude Code process
   ID to `~/Library/Application Support/Session Canvas/claude-status/<session-id>.json`. It never prints
   output, never blocks, and always exits 0, so it cannot change Claude Code's behavior.
   The canvas watches that folder and updates immediately.

   | Last event | Note state |
   | --- | --- |
   | `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `SubagentStop`, `PreCompact`, `SessionStart(compact)` | Running |
   | `PermissionRequest`, `Notification: permission_prompt` | Permission required |
   | `Notification: elicitation_dialog` | Waiting for you |
   | `Stop`, `Notification: idle_prompt`, `SessionStart` | Idle / Finished (unread result) |
   | `SessionEnd`, or the recorded process is gone | Not live: saved transcript state |

   Unknown future events establish nothing and fall through to the next layer.

2. **Claude Code runtime files (fallback).** Without a hook record from a live process, the canvas reads
   `~/.claude/sessions/<pid>.json` (`status: busy|idle`) and, for background sessions,
   `~/.claude/jobs/<id>/state.json` (`state: blocked` means the job asked you something). These files
   are undocumented; any unrecognized value makes the note **Unknown** rather than guessing. The viewer
   labels such notes "Live state from Claude Code runtime files (fallback)".

3. **Transcript.** A session without a live process shows its saved state: Idle, or Finished while its
   last result is unacknowledged.

**Self-check.** If a live session's hook record says Idle but its transcript has an open turn and kept
changing for more than 90 seconds after the last hook event, the canvas reports
"status hooks are not reporting" and shows that session as Running from transcript evidence. This catches
hooks disabled by policy, removed settings, or a changed hook contract after an update.

Sessions that were already running when hooks were installed only start reporting through hooks after
they are restarted; until then they use the fallback layer.

## Opening and creating sessions

- **Open in Claude Code** opens a terminal in the session's folder and runs `claude --resume <id>`. A
  background session (one with a job in `~/.claude/jobs`) is opened with `claude attach <id>` instead.
- **New session** runs `claude --session-id <new-uuid> [--name …] ["first instruction"]` in the chosen
  project folder, so the canvas knows the identity before the first message is saved. With hooks, the
  note appears immediately from `SessionStart`.
- The terminal tab is named after the session: the launcher sets the terminal title and its `.command`
  file carries the session name (cmux and similar terminals show the file name until a title arrives).
- The terminal app is configurable (Terminal by default; any app that opens `.command` files works,
  such as iTerm). The `claude` executable and Claude Code home folder are configurable too.

### Sessions started in the home folder

Many sessions are started in `~` and `cd` into a project. Transcripts record the working folder of every
message, so such a session is grouped with the project where at least 10% of its messages (and at least
three) were recorded. Hidden folders (`~/.claude`, `~/.cache`, …) and `~/Library` never count. The project
is the nearest folder above that another session was started in, else the nearest git root, else the
folder itself. Folders moved since then are found through moves known from other sessions, or by name a
few levels below home. The session still resumes from `~`, where Claude Code keeps its history.

### Project rules

`~/Library/Application Support/Session Canvas/claude-project-rules.json` (optional) names projects and
says what belongs to them. Each project has a `name`, a `folder`, optional `include` folders, optional
`keywords` and optional `split` (each subfolder becomes its own project):

```json
{"projects": [
  {"name": "Mobile app", "folder": "~/Projects/work/mobile", "include": ["~/Projects/work/mobile-test"], "keywords": ["widget"]},
  {"name": "Work", "folder": "~/Projects/work"},
  {"name": "Side projects", "folder": "~/Projects/side", "split": true}
]}
```

A session joins the rule with the longest folder that holds its working folder. A folder that holds
other projects (such as `Work` above) is a container: sessions started there are grouped by the folder
they worked in, like sessions started in `~`. A session that never left `~` or a container is matched
by keywords in its title and first prompts (most distinct words wins, ties go to the earlier rule; in a
container only projects inside it). Paths of files that tools read or changed count like working folders.
Rules are read at every refresh; restart the app after editing them so cached groupings are recomputed.

### Moving a session to another project

Dragging a note into another project is remembered by Session Canvas in
`~/Library/Application Support/Session Canvas/claude-project-assignments.json`; Claude Code itself is not
changed. Dragging a note out of every project returns it to automatic grouping.

## Checking it without the UI

`SessionCanvasProbe --claude [CLAUDE_HOME] [STATUS_DIR]` prints counts only (sessions, projects and session count per project name, states,
evidence per layer, timings) and never prints conversation content. With `--groups` it also lists each
session id with its project folder (manual assignments are not applied).

`SessionCanvasProbe --hook-settings STATUS_DIR SCRIPT_PATH` writes the hook script and prints a settings
fragment, so hooks can be tested in isolation with `claude --settings <fragment>` without touching the
user's settings. This is how the live hook sequence was verified (see the
[OpenSpec change](../openspec/changes/add-claude-code-source/verification.md)).
