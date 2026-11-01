# Agent Git and GitHub workflow

The user has granted standing authorization for routine Git delivery during coding tasks: create a working branch, stage task files, commit verified changes, push the working branch, and create or update a GitHub pull request without asking for conversation-level permission again. Global `~/.codex/AGENTS.md` and this project's `AGENTS.md` record the authorization. Operating-system/sandbox and plugin approvals are separate controls.

## Setup status, 2026-10-25

After renewed authorization, global instructions and the command-rule extension were installed in `~/.codex/AGENTS.md` and `~/.codex/rules/default.rules`. Eleven checks against the installed policy passed, covering add, commit, branch creation/switching, push, PR creation/update, and repository inspection; PR merge, hard reset, and arbitrary API mutation received no new allow rule. The SSH remote check succeeded, and GitHub CLI reported ADMIN access for `WinnerOK/session-canvas` with base branch `main`.

The GitHub plugin is installed and enabled. Plugin Management reports that it inherits **Allow low-risk actions**, which is not a Never ask setting. Its advertised publishing workflow combines the connector and CLI; local Git/CLI command rules are now installed separately. Subsequent user-authorized fetch and remote-branch cleanup on 2026-10-25 verified SSH read/write access independently; the permission installer also confirmed SSH reading and GitHub CLI repository access. No plugin permission setting was changed, and no additional skill is required for this workflow.

## Delivery sequence

1. Inspect the repository, current branch, remote, and unrelated local changes. Use the repository's current base branch and a `codex/<topic>` branch, or continue the task's existing working branch.
2. Implement the requested change, update its affected documentation/specifications, and run the necessary checks.
3. Review the diff and stage only files belonging to the task. Preserve unrelated work.
4. Make a focused commit, push the working branch, and create or update its PR. Publish completed GitHub PRs for review: create them without `--draft`, or run `gh pr ready <number>` after implementation and required checks finish. Use a draft while work or required verification remains incomplete. Ready for review does not authorize merging.
5. Attach a created PR to the Codex chat and report its URL, resulting behavior, and actual checks.

Invoke `git` and `gh` directly. Write a multiline PR description to a file and pass `--body-file`. The installed `mattpocock-skills:pr` skill can guide the description when applicable; no additional skill is needed to grant command permission.

## Saved command permissions

The routine allow list covers `git add`, `git commit`, `git switch -c`, `git switch --`, `git fetch`, `git push`, `git ls-remote`, `gh repo view`, and `gh pr create/edit/view/list/checks/diff/status`. For an existing branch, use `git switch -- BRANCH`. Read-only inspection normally stays inside the workspace; network operations or protected `.git` writes can use `sandbox_permissions="require_escalated"` with the corresponding loaded saved prefix. Match the command prefix rather than narrowing an approval amendment to one branch, PR title, or file list.

The user's standing authorization covers ordinary branch-and-PR delivery. Force-push, published-history rewrites, deleting remote branches, direct pushes to the main/protected branch, and merging a PR require a separate explicit instruction. Prefix rules match command names and do not enforce arbitrary flag/ref combinations; this boundary is part of the agent's standing instructions. There is no generic `git`, `gh`, or `gh api` allow rule.

Codex loads rule files at startup. Existing chats can retain an older policy until Codex restarts. An `execpolicy check --rules ...` result demonstrates matching against the supplied files; it does not demonstrate runtime reload or dismiss a visible approval prompt.

GitHub authentication and repository write access are independent of Codex's command permissions. The renewed permission installation completed read-only checks of the existing SSH remote and GitHub CLI repository access. No test commit, branch push, or PR was created during permission setup.
