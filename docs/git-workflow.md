# Agent Git and GitHub workflow

The user has granted standing authorization for routine Git delivery during coding tasks: create a working branch, stage task files, commit verified changes, push the working branch, and create or update a GitHub pull request without asking for conversation-level permission again. This project's `AGENTS.md` records the authorization. Operating-system/sandbox and plugin approvals are separate controls.

## Setup status, 2026-10-25

Global instructions and a command-rule extension have been prepared and passed eleven policy checks, but the system request to install them was declined. The prepared changes to `~/.codex/AGENTS.md` and `~/.codex/rules/default.rules` have not been applied. Existing rules already allow branch creation, commits, and fetch; the proposed general push and PR rules remain pending.

The GitHub plugin is installed and enabled. Plugin Management reports that it inherits **Allow low-risk actions**, which is not a Never ask setting. Its advertised publishing workflow combines the connector and CLI, so installing the plugin does not itself grant local Git command permissions. Repository/account access has not yet been verified. No additional skill is required to grant either kind of permission.

## Delivery sequence

1. Inspect the repository, current branch, remote, and unrelated local changes. Use the repository's current base branch and a `codex/<topic>` branch, or continue the task's existing working branch.
2. Implement the requested change, update its affected documentation/specifications, and run the necessary checks.
3. Review the diff and stage only files belonging to the task. Preserve unrelated work.
4. Make a focused commit, push the working branch, and create or update its PR. Use a draft while work or required verification remains incomplete.
5. Attach a created PR to the Codex chat and report its URL, resulting behavior, and actual checks.

Invoke `git` and `gh` directly. Write a multiline PR description to a file and pass `--body-file`. The installed `mattpocock-skills:pr` skill can guide the description when applicable; no additional skill is needed to grant command permission.

## Prepared command permissions

The proposed routine allow list covers `git add`, `git commit`, `git switch -c`, `git switch --`, `git fetch`, `git push`, `git ls-remote`, `gh repo view`, and `gh pr create/edit/view/list/checks/diff/status`. For an existing branch, use `git switch -- BRANCH`. Read-only inspection normally stays inside the workspace; network operations or protected `.git` writes can use `sandbox_permissions="require_escalated"` once the corresponding saved prefix is installed and loaded.

The user's standing authorization covers ordinary branch-and-PR delivery. Force-push, published-history rewrites, deleting remote branches, direct pushes to the main/protected branch, and merging a PR require a separate explicit instruction. Prefix rules match command names and do not enforce arbitrary flag/ref combinations; this boundary is part of the agent's standing instructions. There is no generic `git`, `gh`, or `gh api` allow rule.

Codex loads rule files at startup. Existing chats can retain an older policy until Codex restarts. An `execpolicy check --rules ...` result demonstrates matching against the supplied files; it does not demonstrate runtime reload or dismiss a visible approval prompt.

GitHub authentication and repository write access are independent of Codex's command permissions. The prepared installer includes read-only checks of the existing SSH remote and GitHub CLI repository access. These checks have not run because installation was declined. No test commit, branch push, or PR was created during preparation.
