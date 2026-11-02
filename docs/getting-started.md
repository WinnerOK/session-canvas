# Getting started

[Overview](../README.md) · [All documentation](README.md)

## Requirements

- macOS 14 or later on Apple Silicon. Published app archives and automated builds
  currently support `arm64` only.
- Codex desktop installed and signed in. Canvas reads that installation's saved
  sessions and prefers its bundled CLI; a separate CLI installation is not needed
  when that executable is available.
- Keep Codex running for live attention updates. Without its live feed, Canvas
  can read saved history but cannot claim a current Running or pending-request
  state.

You can explore the isolated demo without connecting a Codex source.

## Install and open

1. Open [GitHub Releases](https://github.com/WinnerOK/session-canvas/releases/latest).
2. Download the `SessionCanvas-…-macos-arm64.zip` asset and its matching
   `.zip.sha256` file into the same folder.
3. Optionally verify the archive in Terminal before extracting. For `v0.0.1`:

   ```sh
   cd ~/Downloads
   shasum -a 256 -c SessionCanvas-v0.0.1-macos-arm64.zip.sha256
   ```

   Use the filename from your downloaded release and check that the command
   reports `OK`.
4. Unzip the archive, move **Session Canvas.app** to **Applications**, and open it.

Releases use an ad-hoc signature, without Developer ID signing or Apple
notarization. If macOS blocks the app, verify that it came from this repository's
release. Where offered, use **System Settings → Privacy & Security → Open Anyway**
and confirm the specific app. A checksum verifies the archive against the
published checksum; it does not replace notarization. See the
[distribution details](ci-cd.md#create-a-release-in-github).

To update, quit Session Canvas, replace the application with the new release,
and reopen it. Your Canvas data lives outside the app bundle. Before a downgrade,
read the [database compatibility and recovery notes](native-application.md#persistence-and-recovery).

## Connect or explore

On a normal launch, Canvas selects **Codex desktop** and discovers saved sessions
and projects. Use the source menu at the bottom of the sidebar to switch to
**Demo workspace**. The source choice is not remembered at startup.

The demo contains fictional Running, Waiting for you, Permission required, and
Finished sessions. It simulates work and project moves without submitting model
turns. **Open in Codex** is unavailable for these sample sessions.

If Canvas cannot find your executable, open **Connection Settings…** (⌘,).
Choose the Codex executable and select **Connect**. Shared-server connections and
custom navigation templates are described in [Source modes](native-application.md#source-modes).

## Find and review work

1. Select **Active sessions**, then **Fit to Content** (⌘0).
2. Pan by scrolling or dragging the background; pinch to zoom. Move a card or
   project header to arrange the selected layer. **Rearrange** compacts its
   visible content without changing your pan or zoom.
3. Click a card to open read-only history, newest first. Choose **Load older
   history** when needed. Reading does not acknowledge the result.
4. For Finished work, choose **Acknowledge result** after reviewing it. Choose
   **Mark as unread** to bring that result back to your attention. **Acknowledge
   all** includes hidden Finished cards in the current source.
5. Use **Open in Codex** to reply, approve a request, or continue working.

Use **Hide Idle after** to move old eligible Idle sessions into **Stale sessions**.
Archived sessions and sessions whose current execution is **Unknown** appear in
**Inactive sessions**. Search and attention/project filters apply within the
selected layer. **Show all in this layer** clears those filters and search.

For creation, archive/restore, exact state rules, and every shortcut, see
[Controls](native-application.md#controls).

## Connection and status help

| What you see | What to do |
| --- | --- |
| An empty canvas | Check the selected layer, clear search with **Show all in this layer**, and check the source menu. Try the demo to distinguish an empty source from a rendering problem. |
| Saved history only / desktop unavailable | Open Codex and check the executable in Connection Settings. Saved history does not establish current execution. |
| Unknown after reconnecting or reopening | Use **Refresh Sessions** (⌘R). Unknown means unverified current state; a **Last known** hint is historical. Check Codex itself for an outstanding permission or input request. |
| Refresh failures or remaining Unknown sessions | The progress window reports these separately. Retry explicitly after checking the source; a partial refresh is not proof that every session is current. |
| A card cannot move into another project | Change its project in Codex. Canvas follows actual desktop membership; real-source cross-project moves are currently disabled. |
| Open in Codex fails | Check the registered Codex application and navigation settings. Demo sessions have no native navigation target. |

Codex compatibility can change with desktop updates. The
[compatibility report](integration-compatibility.md) distinguishes verified
behavior from remaining integration gates. Shared-server mode is advanced and
requires an already-reachable control socket; it does not start a daemon for you.

## Data and privacy

Canvas works with your local Codex source and has no hosted Canvas backend.
It reads session metadata, history, and available live observations; reading and
refreshing do not submit model turns or approve requests. Explicit session
creation and archive/restore use Codex's supported source operations.

Canvas owns:

```text
~/Library/Application Support/Session Canvas/canvas.sqlite
```

This database contains layouts, filters, a narrow session/result cache, and
explicit review records. It can contain session titles and cached result text;
treat a copy as private. Full transcript history is loaded on demand rather than
copied into a second complete history store. Connection preferences are local.

To back up Canvas state, quit the app and copy its Application Support folder.
This is not a backup of your Codex conversations. Read the
[recovery and migration notes](native-application.md#persistence-and-recovery)
before restoring an older database or app version.

For help, [open an issue](https://github.com/WinnerOK/session-canvas/issues) with
the macOS, app, and Codex versions, steps to reproduce, and visible error/status.
Remove private session content and local paths from screenshots. Do not attach
the Canvas database or Codex history to a public report.
