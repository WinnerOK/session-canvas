## ADDED Requirements

### Requirement: Pull requests verify the native application
Every pull request and push to `main` SHALL run the normal Swift Testing suites, Python tooling tests, release bundle compilation, and signature verification on GitHub-hosted Apple Silicon and Intel macOS runners with a selected Swift 6 toolchain. CI SHALL also validate all OpenSpec artifacts strictly. Pull-request jobs SHALL use read-only repository permissions and SHALL NOT require Codex installation, user session data, or signing secrets.

#### Scenario: A pull request changes application or tooling code
- **WHEN** a pull request is opened, reopened, or updated
- **THEN** both architecture checks and the specification check run and failures are visible as failing GitHub checks

#### Scenario: Tests require an installed desktop source
- **WHEN** the normal suite runs on a clean hosted runner
- **THEN** installed-source opt-in tests remain disabled while fixture-based core, runtime, and native rendering tests run

#### Scenario: The test process exits without finishing its run
- **WHEN** the test command exits without Swift Testing reporting a completed successful run
- **THEN** CI fails even if the process exit status is zero

### Requirement: Release creation uses the verified source revision
The repository SHALL provide a manually dispatched GitHub Actions release workflow and a `v*` tag-push trigger. Releases SHALL accept only `vMAJOR.MINOR.PATCH` numeric versions. An existing tag SHALL resolve to its commit; a new manually requested tag SHALL target the selected workflow revision. Both architecture checks and strict specification validation MUST pass for that exact revision before creating or updating a draft release.

#### Scenario: Create a release entirely in GitHub
- **WHEN** a maintainer runs Release from Actions with a new valid version tag
- **THEN** the workflow verifies the selected revision, creates that tag at the verified commit, and prepares a draft GitHub Release containing both architecture archives and their SHA-256 files

#### Scenario: Retry an existing tagged release
- **WHEN** a version tag is pushed or manually selected for another run
- **THEN** the workflow tests and packages the tag's commit rather than the current tip of the selected branch

#### Scenario: Verification fails or the version is invalid
- **WHEN** a version is malformed or any required check fails
- **THEN** the workflow fails without creating or updating a GitHub Release

#### Scenario: A tag moves during verification
- **WHEN** the existing version tag no longer resolves to the tested commit at upload time
- **THEN** the workflow fails without replacing the tag or uploading release assets

### Requirement: Release assets identify their version and architecture
Each release SHALL contain separate macOS 14-or-later `.app` ZIP archives for `arm64` and `x86_64` with architecture and tag in their filenames, plus SHA-256 checksum files. Bundle metadata SHALL match the tag's numeric version and record the workflow run number. Documentation SHALL disclose the absence of Developer ID signing and notarization.

#### Scenario: Download a release asset
- **WHEN** a user selects the ZIP matching their Mac
- **THEN** it contains Session Canvas.app with the advertised version, minimum OS, executable, and a verifiable checksum

### Requirement: Packaging verifies distributable integrity
Packaging SHALL verify the executable architecture and ad-hoc bundle signature before archiving, preserve executable permissions, and propagate failures. The upload job SHALL verify archive checksums before modifying a GitHub Release.

#### Scenario: Binary or signature verification fails
- **WHEN** the executable has the wrong architecture or its bundle signature is invalid
- **THEN** packaging fails before producing an archive

### Requirement: Release publication remains explicit
Only the release upload job SHALL request repository write permission. Automation SHALL create drafts, allow replacement of assets only in drafts, and SHALL NOT publish releases or replace published assets. Publishing SHALL remain an explicit maintainer action after reviewing the completed draft.

#### Scenario: Rerun a completed release
- **WHEN** the target GitHub Release is already published
- **THEN** the upload job fails without replacing its assets
