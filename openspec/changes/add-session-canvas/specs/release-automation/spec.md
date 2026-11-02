## ADDED Requirements

### Requirement: Application documentation supports first use
The root README SHALL explain the application's purpose, platform and Codex prerequisites, release installation, and first-use workflow. It SHALL include inspected native screenshots with descriptive alternative text and explicit demo-data labeling, link to a docs index, and disclose relevant distribution and integration limits. Detailed technical behavior, developer operations, research, and verification evidence SHALL remain accessible through that index.

#### Scenario: A new user opens the repository
- **WHEN** a user reads the root README
- **THEN** they can understand the app, find the release download, install it, and identify how to review a result or continue in Codex
- **AND** the docs index links to detailed onboarding, controls, troubleshooting, data handling, compatibility, source builds, and SDD evidence

#### Scenario: Refresh application illustrations
- **WHEN** maintainers replace the README screenshots
- **THEN** they use the documented isolated demo capture commands, inspect newly written PNGs, and retain working relative image links and descriptive alternative text
- **AND** demo screenshots are not presented as proof of real-source integration or as the user's conversations

### Requirement: Pull requests verify the native application
Pull requests and pushes to `main` SHALL run normal Swift Testing suites, Python tooling tests, release bundle compilation, and signature verification only on a GitHub-hosted arm64 macOS runner with a selected Swift 6 toolchain. CI SHALL validate all OpenSpec artifacts strictly. Pull-request jobs SHALL use read-only repository permissions and SHALL NOT require Codex, user session data, or signing secrets.

#### Scenario: A pull request changes application or tooling code
- **WHEN** a pull request is opened, reopened, or updated
- **THEN** the arm64 application check and the specification check run and failures are visible as failing GitHub checks
- **AND** no x86_64 build or test job is scheduled

#### Scenario: Tests require an installed desktop source
- **WHEN** the normal suite runs on a clean hosted runner
- **THEN** installed-source opt-in tests remain disabled while fixture-based core, runtime, and native rendering tests run

#### Scenario: The test process exits without finishing its run
- **WHEN** the test command exits without Swift Testing reporting a completed successful run
- **THEN** CI fails even if the process exit status is zero

### Requirement: Failed hosted tests retain evidence
CI SHALL retain the failed application-test log and generated fixture PNGs as architecture-specific workflow artifacts for seven days. This evidence SHALL come from the isolated normal suite with installed-source checks disabled.

#### Scenario: A native rendering regression fails on a hosted runner
- **WHEN** the application-test step fails after producing a log or fixture captures
- **THEN** the job uploads those available files for diagnosis

### Requirement: Release creation uses the verified source revision
The repository SHALL provide a manually dispatched GitHub Actions release workflow and a `v*` tag-push trigger. Releases SHALL accept only `vMAJOR.MINOR.PATCH` numeric versions. An existing tag SHALL resolve to its commit; a new manually requested tag SHALL target the selected workflow revision. The arm64 application check and strict specification validation MUST pass for that exact revision before creating or updating a draft release.

#### Scenario: Create a release entirely in GitHub
- **WHEN** a maintainer runs Release from Actions with a new valid version tag
- **THEN** the workflow verifies the selected revision, creates that tag at the verified commit, and prepares a draft GitHub Release containing the arm64 archive and its SHA-256 file

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
Release automation SHALL produce one macOS 14-or-later `.app` ZIP archive for `arm64` with architecture and tag in its filename, plus a SHA-256 checksum file. The packaging CLI SHALL accept only arm64, and the upload job SHALL download only its arm64 artifact. Bundle metadata SHALL match the tag's numeric version and record the workflow run number. Documentation SHALL disclose the absence of Developer ID signing and notarization.

#### Scenario: Download a release asset
- **WHEN** a user downloads the arm64 ZIP for an Apple Silicon Mac
- **THEN** it contains Session Canvas.app with the advertised version, minimum OS, executable, and a verifiable checksum

#### Scenario: Request an unsupported release architecture
- **WHEN** packaging is invoked with an architecture other than arm64
- **THEN** argument validation rejects the request before building or archiving

### Requirement: Native app bundles use the selected application icon
Local and release macOS app bundles SHALL use the selected blue session-cards artwork with its mint activity indicator. Each bundle SHALL contain its multi-resolution ICNS resource in `Contents/Resources`, referenced by `CFBundleIconFile` before signing. The resource SHALL provide the standard 16, 32, 128, 256, and 512-point representations at 1× and 2×.

#### Scenario: Build a local or release app
- **WHEN** the shared app builder assembles a macOS app bundle
- **THEN** its icon metadata resolves to the bundled ICNS export of the selected blue session-cards PNG before the signature is applied

#### Scenario: The selected icon resource is missing
- **WHEN** the shared app builder cannot copy the required icon resource
- **THEN** the build fails before signing or reporting a successful bundle

### Requirement: Packaging verifies distributable integrity
Packaging SHALL verify the executable architecture and ad-hoc bundle signature before archiving, preserve executable permissions, and propagate failures. macOS tooling tests SHALL exercise the real packaging tools with an arm64 fixture executable, including an app path containing spaces, and verify the extracted bundle and checksum. The upload job SHALL verify archive checksums before modifying a GitHub Release.

#### Scenario: Valid arm64 packaging on the selected hosted toolchain
- **WHEN** macOS tooling tests package a valid arm64 fixture with the selected hosted toolchain
- **THEN** native architecture verification succeeds, the ZIP and matching SHA-256 file are produced, and the extracted executable retains its permissions and valid bundle signature

#### Scenario: Binary or signature verification fails
- **WHEN** the executable has the wrong architecture or its bundle signature is invalid
- **THEN** packaging fails before producing an archive

### Requirement: Release publication remains explicit
Only the release upload job SHALL request repository write permission. Automation SHALL create drafts, allow replacement of assets only in drafts, and SHALL NOT publish releases or replace published assets. Publishing SHALL remain an explicit maintainer action after reviewing the completed draft.

#### Scenario: Rerun a completed release
- **WHEN** the target GitHub Release is already published
- **THEN** the upload job fails without replacing its assets
