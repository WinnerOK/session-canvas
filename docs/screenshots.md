# README screenshots

[All documentation](README.md)

The README uses actual view-backed PNG captures from the native application,
with its built-in fictional demo sessions. They are not mockups or captures of
the user's live desktop. No conversation was started to produce them.

| File | Scene |
| --- | --- |
| [canvas-overview.png](images/canvas-overview.png) | Active layer, two projects, attention states, and sidebar |
| [result-review.png](images/result-review.png) | A Finished session and its loaded result, with the sidebar collapsed |

## Reproduce

From this checkout, run the authorized launcher with a fresh demo database for
each scene:

```sh
python3 /Users/d-manakovskiy/personal/session-canvas/scripts/verify-local.py preview --jobs 1 --capture .build/verification/readme-canvas.png
python3 /Users/d-manakovskiy/personal/session-canvas/scripts/verify-local.py preview --skip-build --show-result --hide-sidebar --capture .build/verification/readme-review.png
```

The first command rebuilds/signs the app; the second captures that same bundle.
Both use the default demo source, isolated storage, and a bounded native capture.
They print the capture and storage paths, and fail if the app does not exit
successfully with a newly written PNG. See the [launcher guide](native-application.md#codex-verification-launcher)
for permission setup and supported output directories.

Inspect both PNGs before copying them into `docs/images/`. Keep titles, attention
labels, and result controls readable; verify that no personal data is present.
Use descriptive alternative text and label the scenes as demo data in the
README. Demo states illustrate the UI and do not establish real-source
integration acceptance.

```sh
mkdir -p docs/images
cp .build/verification/readme-canvas.png docs/images/canvas-overview.png
cp .build/verification/readme-review.png docs/images/result-review.png
```

Do not use `--source desktop` for routine documentation captures. It requires
separate authorization for that specific run under the project's
[verification safety rules](native-application.md#verification-safety).
