# Project instructions

## Keep changes reflected in Spec Driven Development (SDD)

For every feature, bug fix, or user correction, review its impact on SDD and update the affected artifacts in the same task:

- Update requirements and scenarios in the relevant OpenSpec specifications. Align `proposal.md` and `design.md` when scope, behavior, or architecture changes.
- Keep `tasks.md` and `verification.md` synchronized with implementation and actual verification evidence. Leave incomplete or unverified acceptance gates explicitly open.
- Update affected guides in `docs/` and `README.md` so they agree with the contract.

Follow `openspec/config.yaml`. The current change is `openspec/changes/add-session-canvas/`; its `verification.md` maps user corrections to requirements and checks.

Before completing the task, account for every behavior change in SDD, run `openspec validate --all --strict` and `git diff --check`, and verify affected local document links. Documentation and application changes are complete together.

## Local verification in Codex

Use `python3 /Users/d-manakovskiy/personal/session-canvas/scripts/verify-local.py` with `build`, `test`, or `preview` for local code checks. Invoke it directly with literal arguments. A general prefix allow rule is saved in `~/.codex/rules/default.rules`; use `sandbox_permissions="require_escalated"` for these runs. If an approval amendment is needed, propose `prefix_rule=["python3", "/Users/d-manakovskiy/personal/session-canvas/scripts/verify-local.py"]`, covering all supported arguments rather than a single test.

Rule files load at Codex startup. An already-running chat can retain an older policy and an existing approval prompt; explain that Codex needs to reload the rules rather than claiming a file check updated the active chat. `codex execpolicy check --rules ...` proves file matching only.

Preview defaults to a fresh demo database and verifies a newly written PNG. Use `--source desktop` for actual saved-session inspection and `test --real-source` for the opt-in installed-source checks. Read [the native guide](docs/native-application.md#codex-verification-launcher) for options and permission setup. Report command or capture failures as failed verification.

## Protect the running desktop during verification

Use fixtures and demo captures first. Installed inventory checks must disable desktop observation. Running `test --live-desktop` or `preview --source desktop` requires explicit user authorization for that specific run; standing build/test permissions do not grant it. After a hung live check, stop its proven test-owned processes and continue with fixtures. Preserve ChatGPT and unrelated processes. See [verification safety](docs/native-application.md#verification-safety) before any live check.
