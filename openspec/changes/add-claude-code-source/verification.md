# Verification

Environment: macOS 28 (Darwin 27.0.0), Apple Swift 6.3.2, Claude Code 2.1.317, 2026-11-03.

| Check | Result |
| --- | --- |
| `swift build` | Passes |
| `swift test --disable-xctest` (Xcode toolchain) | 151 of 152 pass (98 + 54 in the two test runs), including all 15 `ClaudeCodeTests`. The one failure, `SemanticZoomTests.projectLabelsUseAvailableSpaceAtEachZoom(zoom: 0.3)`, fails identically on unmodified `main` on this machine (OCR), so it is unrelated |
| `SessionCanvasProbe --claude` on a real home | about 80 sessions with dialogue; first full scan 1.7 s (release build), later scans re-read only changed files |
| Live hooks: `claude -p` with `--settings` from `--hook-settings` and an isolated status folder, running `sleep 6` through Bash | Observed sequence `SessionStart → UserPromptSubmit → PreToolUse (6 s) → PostToolUse → SessionEnd`; the recorded PID was the `claude` process itself and was dead after `SessionEnd` |
| `SessionCanvasProbe --claude` after projects were moved into a nested folder layout | Moved launch folders resolve to their new location; most sessions started in the home folder join the project they worked in; the rest never left home or worked only in internal folders and can be dragged into a project |
| Project rules on a real home | Folder, container, split and keyword rules group nearly all home-started sessions; sessions where rules were wrong were corrected by dragging (stored locally, not in Claude Code) |
| App bundle (`scripts/build-app.py`) launched with the Claude Code source | Lists 80 sessions, shows the fallback explanation before hooks are installed (read via Accessibility; screen capture was not permitted) |

Not yet verified live: `PermissionRequest` / `Notification: permission_prompt` / `elicitation_dialog`
in an interactive session (mapping is covered by unit tests against the documented payloads).
