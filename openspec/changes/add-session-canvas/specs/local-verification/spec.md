## ADDED Requirements

### Requirement: Stable authorized local verification command
Development tooling SHALL provide one direct Python launcher for building, testing, and previewing the current checkout. A user-authorized Codex command-prefix rule SHALL cover its absolute path with varying supported arguments, while retaining the workspace sandbox and other command rules. The launcher SHALL accept a bounded set of operations without arbitrary shell-command passthrough.

#### Scenario: Change verification parameters
- **WHEN** Codex changes a test filter, selected session, SQLite path, or PNG path within the launcher's supported options
- **THEN** the same saved launcher-prefix rule applies without a new per-invocation permission

#### Scenario: Different executable or opaque shell wrapper
- **WHEN** a command substitutes another script or introduces a shell wrapper that cannot be safely decomposed into the permitted command
- **THEN** the launcher permission does not authorize that different command prefix

#### Scenario: An existing chat still requests approval
- **WHEN** a matching rule was saved after a chat loaded its execution policy
- **THEN** setup explains the required Codex restart and distinguishes file-rule matching from the active chat policy; it does not claim that saving the file dismisses an existing approval dialog

### Requirement: Isolated explicit verification outputs
The launcher SHALL direct SwiftPM and compiler module caches under the checkout's `.build` directory. Native preview SHALL default to demo mode with a fresh separate Canvas SQLite file. Explicit output paths SHALL resolve within verification, temporary, or Codex visualization directories and use the expected file type. Installed-source tests and desktop preview SHALL require explicit options.

#### Scenario: Preview without options
- **WHEN** the preview command runs without source or output options
- **THEN** it rebuilds the app and captures an isolated demo using a fresh verification database

#### Scenario: Output would overwrite production state
- **WHEN** an output points outside the permitted directories, including through a symlink, or uses the wrong file type
- **THEN** the launcher rejects the request before building or launching the app

#### Scenario: A previous shell enabled installed-source checks
- **WHEN** a normal test command inherits the installed-source environment switch
- **THEN** the launcher clears it unless the command explicitly opts in

### Requirement: Verification success requires execution evidence
The launcher SHALL propagate build/test/process failures and bound native capture time. Preview SHALL succeed only when the current invocation writes a new PNG and the native process exits successfully.

#### Scenario: App exits without rendering
- **WHEN** the app exits successfully but produces no new capture or leaves an old image untouched
- **THEN** the launcher reports failed verification
