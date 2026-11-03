# Session Canvas documentation

Session Canvas is a native macOS workspace over existing local Codex sessions.
For the overview and screenshots, see the [application README](../README.md).

## Using the app

| I want to… | Read |
| --- | --- |
| Install, connect, or try the demo | [Getting started](getting-started.md) |
| Learn gestures, shortcuts, layers, filters, and result review | [Controls](native-application.md#controls) |
| Understand connection choices and refresh behavior | [Source modes](native-application.md#source-modes) |
| Find local data and understand backup/recovery | [Data and privacy](getting-started.md#data-and-privacy), [persistence and recovery](native-application.md#persistence-and-recovery) |
| Check supported Codex integration and current limits | [Compatibility report](integration-compatibility.md) |
| Use Claude Code sessions and status hooks | [Claude Code source](claude-code.md) |
| Report a bug or suggest a feature | [GitHub issues](https://github.com/WinnerOK/session-canvas/issues) |

## Building and maintaining

| Topic | Guide |
| --- | --- |
| Build from source, run tests, and package a local app | [Native application](native-application.md#build-and-run) |
| Agent build/test/capture commands and permissions | [Verification launcher](native-application.md#codex-verification-launcher) |
| Isolated checks and protection of the running desktop | [Verification safety](native-application.md#verification-safety) |
| Reproduce the README screenshots | [Screenshots](screenshots.md) |
| GitHub checks, arm64 releases, checksums, and signing | [CI/CD](ci-cd.md) |
| Branches, commits, and pull-request delivery | [Git workflow](git-workflow.md) |
| Application icon and retained alternatives | [Branding](../assets/branding/README.md), [light concepts](../assets/branding/LIGHT-CONCEPTS.md) |

## Behavior and design

- [Domain glossary](../GLOSSARY.md) and [domain model](domain-model.md)
- [Long-history performance investigation and repair](history-loading-performance.md)
- [OpenSpec proposal](../openspec/changes/add-session-canvas/proposal.md) and [design](../openspec/changes/add-session-canvas/design.md)
- [Implementation tasks](../openspec/changes/add-session-canvas/tasks.md), [verification evidence and remaining gates](../openspec/changes/add-session-canvas/verification.md), and [function inventory](../openspec/changes/add-session-canvas/functional-coverage.md)
- Behavioral specifications: [canvas](../openspec/changes/add-session-canvas/specs/canvas-workspace/spec.md), [attention](../openspec/changes/add-session-canvas/specs/session-attention/spec.md), [projects](../openspec/changes/add-session-canvas/specs/project-regions/spec.md), [actions](../openspec/changes/add-session-canvas/specs/session-actions/spec.md), [connections](../openspec/changes/add-session-canvas/specs/source-connection/spec.md), [verification](../openspec/changes/add-session-canvas/specs/local-verification/spec.md), and [releases and documentation](../openspec/changes/add-session-canvas/specs/release-automation/spec.md)
- The [session-layers change](../openspec/changes/add-session-layers/proposal.md) owns the current independent layer geometry and classification, with its own [specification](../openspec/changes/add-session-layers/specs/session-layers/spec.md) and [verification](../openspec/changes/add-session-layers/verification.md).

Validate all specifications with OpenSpec 1.15.0:

```sh
openspec validate --all --strict
```

## Earlier research

These documents record options explored before selecting the native Mac
companion. Use the compatibility report above for current support.

- [Local companion versus an in-app view](delivery-options.md)
- [Technical stack comparison](technical-stack-options.md)
- [Desktop shell research](desktop-shell-research.md)
