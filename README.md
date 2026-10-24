# Session Canvas

A free-roam canvas for existing Codex sessions: movable session notes, project regions, live attention states, and explicit result acknowledgment.

The application is implemented in SwiftUI/AppKit for macOS 14 and later, with SQLite persistence and no third-party package dependencies. Real saved-session discovery/history work through the installed Codex source. Live desktop state, actual project mutations, and desktop session creation remain limited by the available host interfaces; a clearly labeled, isolated demo exercises those canvas interactions.

```sh
swift run SessionCanvas
swift run SessionCanvas --demo
swift test --disable-xctest
python3 scripts/build-app.py
```

The local app bundle is written to `dist/Session Canvas.app`. See the [native app guide](docs/native-application.md) for controls, packaging, and the opt-in workaround for this machine's SwiftPM installation.

- [Domain glossary](GLOSSARY.md)
- [Native application and build instructions](docs/native-application.md)
- [Verified Codex integration and remaining limits](docs/integration-compatibility.md)
- [Domain model, state rules, and edge cases](docs/domain-model.md)
- [Separate local app vs. in-app Codex view](docs/delivery-options.md)
- [Technical stack comparison](docs/technical-stack-options.md)
- [OpenSpec proposal](openspec/changes/add-session-canvas/proposal.md)
- [Design and integration gate](openspec/changes/add-session-canvas/design.md)
- [Implementation tasks](openspec/changes/add-session-canvas/tasks.md)

The selected delivery is a native Mac-only companion with a session/result viewer, Acknowledge, and Open in Codex. The remaining desktop integration gate is tracked explicitly; demo interactions are not presented as verified desktop mutations.

The behavioral specifications are [canvas-workspace](openspec/changes/add-session-canvas/specs/canvas-workspace/spec.md), [session-attention](openspec/changes/add-session-canvas/specs/session-attention/spec.md), [project-regions](openspec/changes/add-session-canvas/specs/project-regions/spec.md), and [session-actions](openspec/changes/add-session-canvas/specs/session-actions/spec.md).

Validate the proposal with OpenSpec 1.15.0:

```sh
openspec validate add-session-canvas --strict
```
