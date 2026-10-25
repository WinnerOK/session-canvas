# GitHub Actions checks and releases

## Pull-request checks

[CI](../.github/workflows/ci.yml) runs for every pull request and push to `main`. It runs the normal Swift Testing suites, the Python tooling tests, and a release app build with signature verification on both Apple Silicon (`macos-15`) and Intel (`macos-15-intel`). Xcode 16.4 is selected explicitly, with Python 3.12 for tooling. A separate job validates all OpenSpec artifacts with OpenSpec 1.15.0.

Hosted checks use fixtures and native AppKit rendering/events. They do not require an installed Codex desktop, account credentials, saved sessions, or Developer ID secrets. The three installed-source tests remain opt-in local checks; CI does not claim to verify the remaining real-desktop integration gates. See [local verification](native-application.md#codex-verification-launcher) and the [evidence ledger](../openspec/changes/add-session-canvas/verification.md).

The first hosted run exposed a Swift 6.1 overload ambiguity in project-focus geometry that local Swift 6.4 accepted. The canvas now converts AppKit dimensions to the domain's `Double` before that arithmetic, retaining the same positioning formula. Both architectures continue using Xcode 16.4 so CI verifies this compatibility boundary.

The native submit-button test queues its mouse-up before synchronous mouse-down delivery. macOS 15 AppKit may wait for mouse-up inside button tracking; sequential synchronous delivery would hang before release could be sent. Newer SwiftUI controls can consume release after mouse-down returns. The same test verifies exactly one session creation and automatic navigation. The application-test step has a five-minute limit and requires Swift Testing's completed-success summary in addition to a zero exit status, so a stalled or prematurely terminated test cannot silently pass.

After these files reach GitHub, Actions must be enabled for the repository. To require checks before merging, add the two architecture jobs and OpenSpec to the branch protection/ruleset after their first run. Adding workflow files alone does not configure branch protection. Pull requests use `contents: read`, and checkout does not persist credentials.

## Create a release in GitHub

1. Merge the workflows and application changes into `main` so the Release workflow is available in Actions.
2. Open **Actions → Release → Run workflow**. Select the branch to release and enter a new tag such as `v0.2.0`.
3. Wait for the version-resolution, both architecture checks, packaging, and OpenSpec jobs to pass. The workflow creates the tag at the exact verified commit and prepares a **draft** under **Releases**.
4. Review the release notes and download/test the matching app archive. Click **Publish release** when ready.

Versions must be `vMAJOR.MINOR.PATCH`, using numeric components without leading zeros. Prerelease suffixes are not currently supported. If the tag already exists, its commit is used even when a different branch was selected in the Actions form. The tagged revision must contain the packaging scripts introduced with these workflows. A new tag is created only after every required check succeeds. No tag or release is created by this repository change itself.

Alternatively, push an existing version tag to start the same workflow:

```sh
git tag v0.2.0
git push origin v0.2.0
```

[Release](../.github/workflows/release.yml) reuses the CI workflow for the resolved commit. Only its final draft job receives `contents: write`; the built-in `GITHUB_TOKEN` is sufficient, with no personal token or additional secrets. It rechecks an existing tag against the tested SHA before uploading and fails if the tag moved. Repeating a run updates assets only while the release is a draft. Published assets are never replaced. For a published version, choose a new version rather than rerunning an asset update. Automation never clicks Publish release. GitHub also recommends attaching assets to drafts before publication when [immutable releases are enabled](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository).

Each draft contains:

- `SessionCanvas-v0.2.0-macos-arm64.zip` for Apple Silicon.
- `SessionCanvas-v0.2.0-macos-x86_64.zip` for Intel.
- A matching `.zip.sha256` file for each archive.

Each ZIP contains `Session Canvas.app` for macOS 14 or later. The bundle's `CFBundleShortVersionString` is the numeric tag version, and `CFBundleVersion` is the Actions run number. Architecture and ad-hoc signature are checked before archiving; checksums are checked again before uploading. Separate native archives keep build and test coverage aligned with each architecture. This is not a universal binary.

Download a ZIP and its checksum into the same directory, then verify before extracting:

```sh
shasum -a 256 -c SessionCanvas-v0.2.0-macos-arm64.zip.sha256
```

The ZIP preserves executable permissions and the app bundle structure. Extract it and move the app to Applications. These releases use an **ad-hoc signature**, without Developer ID signing or Apple notarization, so macOS Gatekeeper can block a downloaded app. This pipeline does not claim notarized distribution. Developer ID/notarization requires a separate signing setup.

## Local packaging verification

[build-app.py](../scripts/build-app.py) still supports ordinary local builds with version `0.1.0` and build `1`. `--version` and `--build-number` override the bundle metadata. [package-release.py](../scripts/package-release.py) builds, verifies, and archives one architecture:

```sh
python3 -B -m unittest discover -s scripts/tests -v
python3 scripts/package-release.py --tag v0.2.0 --build-number 1 --arch arm64
```

Use `--binary PATH` to package an already built executable, including one built through the local toolchain workaround. Package on the matching architecture; the script rejects an executable without the requested architecture. Outputs are under ignored `dist/`. Local packaging does not create a GitHub release.

The workflow configuration and packaging have local verification evidence. A successful local run does not prove that GitHub-hosted Intel/macOS jobs or release upload permissions have executed successfully; those acceptance checks remain open until the first hosted runs.
