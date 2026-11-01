# GitHub Actions checks and releases

## Pull-request checks

[CI](../.github/workflows/ci.yml) runs for every pull request and push to `main`. It runs the normal Swift Testing suites, the Python tooling tests, and a release app build with signature verification on Apple Silicon (`arm64`, `macos-15`). Xcode 16.4 is selected explicitly, with Python 3.12 for tooling. A separate job validates all OpenSpec artifacts with OpenSpec 1.15.0. Build, test, and release automation supports arm64 only.

The Python tooling suite also compiles a minimal arm64 fixture and packages it with the real `lipo`, `codesign`, and `ditto` tools, without launching an application. It checks version metadata and the archive checksum, extracts the ZIP, and verifies executable permissions, architecture, and bundle signature. This exercises release packaging on the selected hosted toolchain during ordinary PR checks, including paths containing spaces.

Hosted checks use fixtures and native AppKit rendering/events. They do not require an installed Codex desktop, account credentials, saved sessions, or Developer ID secrets. The three installed-source tests remain opt-in local checks; CI does not claim to verify the remaining real-desktop integration gates. See [local verification](native-application.md#codex-verification-launcher) and the [evidence ledger](../openspec/changes/add-session-canvas/verification.md).

The first hosted run exposed a Swift 6.1 overload ambiguity in project-focus geometry that local Swift 6.4 accepted. The canvas now converts AppKit dimensions to the domain's `Double` before that arithmetic, retaining the same positioning formula. The arm64 job continues using Xcode 16.4 so CI verifies this compatibility boundary.

The native submit-button test uses the form's actual Return/default-button route. Synchronous mouse injection entered macOS 15 button tracking, and pumping its release event could prematurely drain Swift's async main runner. Keyboard activation keeps the real SwiftUI submit action, exactly one session creation, visible note/viewer, and automatic-navigation assertions. Other canvas interaction tests retain native mouse events. OCR checks render at a fixed 2× pixel density with English recognition, the best candidate, exact complete-text assertions, and language correction disabled. The application-test step has a five-minute limit and requires both a completed-success summary and completion of the project-creation suite in addition to a zero exit status.

Failed test jobs retain their log and generated fixture PNGs as architecture-specific artifacts for seven days. These images belong to the isolated tests; installed-source checks stay disabled.

After these files reach GitHub, Actions must be enabled for the repository. To require checks before merging, select `Test and build (arm64)` and OpenSpec in the branch protection/ruleset after their first run, and remove any former Intel check requirement. Adding workflow files alone does not configure branch protection. Pull requests use `contents: read`, and checkout does not persist credentials.

## Create a release in GitHub

1. Merge the workflows and application changes into `main` so the Release workflow is available in Actions.
2. Open **Actions → Release → Run workflow**. Select the branch to release and enter a new tag such as `v0.2.0`.
3. Wait for the version-resolution, arm64 checks, packaging, and OpenSpec jobs to pass. The workflow creates the tag at the exact verified commit and prepares a **draft** under **Releases**.
4. Review the release notes and download/test the Apple Silicon app archive. Click **Publish release** when ready.

Versions must be `vMAJOR.MINOR.PATCH`, using numeric components without leading zeros. Prerelease suffixes are not currently supported. If the tag already exists, its commit is used even when a different branch was selected in the Actions form. The tagged revision must contain the packaging scripts introduced with these workflows. A new tag is created only after every required check succeeds. No tag or release is created by this repository change itself.

Alternatively, push an existing version tag to start the same workflow:

```sh
git tag v0.2.0
git push origin v0.2.0
```

[Release](../.github/workflows/release.yml) reuses the CI workflow for the resolved commit. Only its final draft job receives `contents: write`; the built-in `GITHUB_TOKEN` is sufficient, with no personal token or additional secrets. It rechecks an existing tag against the tested SHA before uploading and fails if the tag moved. Repeating a run updates assets only while the release is a draft. Published assets are never replaced. For a published version, choose a new version rather than rerunning an asset update. Automation never clicks Publish release. GitHub also recommends attaching assets to drafts before publication when [immutable releases are enabled](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository).

After fixing a release failure, use **Run workflow** from the branch containing the fix. **Re-run jobs** retains the original workflow revision and can repeat the same failure. If no tag was created, the same version can be entered again. If the tag already exists at the broken revision, choose a new version; selecting a newer branch does not change an existing tag's commit.

Each draft contains:

- `SessionCanvas-v0.2.0-macos-arm64.zip` for Apple Silicon.
- Its matching `SessionCanvas-v0.2.0-macos-arm64.zip.sha256` file.

The ZIP contains `Session Canvas.app` for macOS 14 or later on Apple Silicon. The bundle's `CFBundleShortVersionString` is the numeric tag version, and `CFBundleVersion` is the Actions run number. Architecture and ad-hoc signature are checked before archiving; the checksum is checked again before uploading. The release workflow downloads only the `release-arm64` artifact from its verification run.

The app bundle includes the selected [blue session-cards icon](../assets/branding/README.md) as `Contents/Resources/SessionCanvas.icns`, referenced by `CFBundleIconFile` before signing. Local builds use the same resource.

Download a ZIP and its checksum into the same directory, then verify before extracting:

```sh
shasum -a 256 -c SessionCanvas-v0.2.0-macos-arm64.zip.sha256
```

The ZIP preserves executable permissions and the app bundle structure. Extract it and move the app to Applications. These releases use an **ad-hoc signature**, without Developer ID signing or Apple notarization, so macOS Gatekeeper can block a downloaded app. This pipeline does not claim notarized distribution. Developer ID/notarization requires a separate signing setup.

## Local packaging verification

[build-app.py](../scripts/build-app.py) still supports ordinary local builds with version `0.1.0` and build `1`. `--version` and `--build-number` override the bundle metadata. [package-release.py](../scripts/package-release.py) builds, verifies, and archives arm64:

```sh
python3 -B -m unittest discover -s scripts/tests -v
python3 scripts/package-release.py --tag v0.2.0 --build-number 1 --arch arm64
```

Use `--binary PATH` to package an already built executable, including one built through the local toolchain workaround. Package on Apple Silicon; `--arch` accepts only `arm64`, and the script rejects an executable without arm64 support. Outputs are under ignored `dist/`. Local packaging does not create a GitHub release.

Architecture verification uses `lipo INPUT -verify_arch arm64`. Xcode 16.4 rejects a file path after `-verify_arch` as an unknown architecture, while newer local tools may accept that ordering. Keep the input first for compatibility with the hosted release toolchain.

Historical [hosted PR verification](https://github.com/WinnerOK/session-canvas/actions/runs/40198030452) passed on Apple Silicon and Intel before the arm64-only policy: 12 Python tests, the normal 71-test Swift run, release compilation, bundle signature verification, and OpenSpec with Xcode 16.4 / Swift 6.1.2. Current verification is recorded in the [evidence ledger](../openspec/changes/add-session-canvas/verification.md). Installed-source checks remain disabled. Actual draft-release creation/upload is a separate acceptance check.
