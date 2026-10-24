# Desktop shell research

Initial investigation on 2026-10-24 against official framework documentation and first-party release information. The framework facts and recommendation below describe that research stage; no application or session bridge was exercised during that investigation.

Subsequent decision: the user selected native Swift for a Mac-only application, now implemented with SwiftUI/AppKit and SQLite. This document is retained as research history. See the [native guide](native-application.md), [current integration evidence](integration-compatibility.md), and [correction coverage](../openspec/changes/add-session-canvas/verification.md) for the implemented design and remaining gates.

## Initial recommendation

**Project-specific inference:** Electron with React and TypeScript is the lowest-complexity first-release choice if the team is comfortable with web development. One language can cover the canvas, domain rules, typed bridge, and protocol client; Chromium behavior is controlled by the application release. Tauri 2 with the same frontend and a thin Rust backend is the strongest alternative when avoiding a bundled browser matters enough to accept a second language and platform webview testing.

Wails is compelling for an existing Go team, but its stable-v2/beta-v3 split matters for this background companion. Native SwiftUI/AppKit is compelling for an explicitly macOS-only product whose priority is native integration; it requires more custom work for the interactive canvas and reduces later UI reuse.

No shell establishes access to existing Codex desktop sessions. The existing-session integration gate remains the first prerequisite for every option.

Tray behavior, autostart, and automatic updates are optional delivery considerations, not confirmed MVP requirements.

## Verified release and support position

| Option | Current verified position | Consequence for this project (inference) |
| --- | --- | --- |
| Electron | Major 45 became stable on October 20; majors 43–45 are the supported stable lines. Electron supports its latest three stable releases. [Schedule](https://releases.electronjs.org/schedule), [support policy](https://www.electronjs.org/docs/latest/tutorial/electron-timelines) | Choose a currently supported stable version and budget for regular upgrades. |
| Tauri | Tauri 2 is stable; first-party releases show 2.12.5 on October 21. Its docs release index was still showing 2.12.3 when checked. [Upstream releases](https://github.com/tauri-apps/tauri/releases), [release index](https://v2.tauri.app/release/), [stable announcement](https://tauri.app/blog/tauri-20/) | Use the stable v2 line and lock a tested combination of runtime, CLI, and plugins; do not infer stability from a v3 documentation URL. |
| Wails | v2 is the current stable release, documented as v2.17.0. v3 remains beta; its current changelog lists beta.34 on October 20. The v3 desktop API is described as stable, with some advanced/platform features still unstable. [v2 docs](https://wails.io/docs/introduction/), [v3 FAQ](https://v3.wails.io/faq/), [changelog](https://v3.wails.io/changelog/), [API status](https://v3.wails.io/reference/overview/) | Evaluate stable v2 and beta v3 separately instead of combining their feature lists. |
| SwiftUI/AppKit | These are Apple platform SDKs rather than one independently versioned desktop shell. Xcode 27.1 is released; 27.2 is an RC. The Swift 6.4 release includes the stable Subprocess 1.0 library. [Xcode requirements](https://developer.apple.com/xcode/system-requirements), [Swift release](https://www.swift.org/blog/swift-6.4-released/) | Select a deployment baseline according to the APIs used, rather than assuming users need the development machine's newest macOS. |

## Comparison for Session Canvas

The trade-off assessments in this table are project-specific inferences. Mechanisms are substantiated in the following sections.

| Concern | Electron + React/TS | Tauri 2 + React/TS + Rust | Wails + React/TS + Go | SwiftUI/AppKit |
| --- | --- | --- | --- | --- |
| Canvas and result viewer | Reuse web libraries and Markdown rendering directly | Same frontend; test against OS webviews | Same frontend; test against OS webviews | Build interactive scene and transcript presentation in native UI, or embed a webview |
| Bridge implementation | Node process/socket APIs; no extra backend language | Rust process/socket client and typed commands | Go process/socket client and generated bindings | Foundation/Subprocess client and native state model |
| Background lifetime | Main process owns connection while canvas window is closed | Rust core owns connection while window is hidden | Go backend can outlive hidden window; tray convenience depends on version | App lifecycle and menu-bar APIs directly accessible |
| Browser behavior | Bundle a controlled Chromium version | WebView2 on Windows; WebKit on macOS/Linux | Native webviews; OS/runtime variability | No browser dependency for native UI |
| Packaging/updates | Established Forge path; ships Chromium and Node | Built-in bundling and signed-updater plugin; no bundled browser | Stable v2 needs additional tray/update integration; v3 supplies them in beta | Xcode signing/notarization; direct updates commonly use an added framework |
| Development cost | Lowest language-boundary cost for a TS team | TS plus Rust toolchains, IPC and async lifetime | TS plus Go; easiest alternative for a Go team | Swift/Xcode plus custom canvas interaction; strongest platform coupling |
| Likely reason to choose | Fastest path to proving the complete workflow | Long-running companion without a bundled browser | Reuse Go expertise or a substantial Go bridge | Deliberate macOS-only scope and native UX priority |

## Local integration and lifetime

**Verified:** Electron's main process has Node APIs; utility processes also run Node. Node supports spawning executables with piped streams and IPC sockets, using Unix-domain sockets on Unix and named pipes on Windows. [Electron process model](https://www.electronjs.org/docs/latest/tutorial/process-model), [child processes](https://nodejs.org/api/child_process.html), [IPC sockets](https://nodejs.org/api/net.html#ipc-support). Electron exposes a system tray and lets an application decide whether closing all windows should quit. [Tray](https://www.electronjs.org/docs/latest/api/tray), [app lifecycle](https://www.electronjs.org/docs/latest/api/app#event-window-all-closed).

**Verified:** Tauri has a Rust core with webview message passing. Its sidecar mechanism supports child stdout/stdin; Rust supports Unix stream sockets. Tauri supplies tray APIs and an optional autostart plugin. [Architecture](https://v2.tauri.app/concept/architecture/), [sidecars](https://v2.tauri.app/develop/sidecar/), [UnixStream](https://doc.rust-lang.org/std/os/unix/net/struct.UnixStream.html), [tray](https://v2.tauri.app/learn/system-tray/), [autostart](https://v2.tauri.app/plugin/autostart/).

**Verified:** Wails exposes Go methods to JavaScript and generates TypeScript models. Go supplies executable/stream handling and Unix-domain socket support. Stable Wails v2 can hide its window instead of quitting. [Wails bindings](https://wails.io/docs/introduction/), [Go exec](https://pkg.go.dev/os/exec), [Go net](https://pkg.go.dev/net#Dial), [v2 window lifetime](https://wails.io/docs/reference/options/#hidewindowonclose). The migration guide explicitly marks system tray as unavailable in v2 and shows the v3 API; v3's FAQ documents a built-in updater. These are v3 capabilities, not evidence that stable v2 includes them. [Migration](https://v3.wails.io/migration/v2-to-v3/), [v3 updater](https://v3.wails.io/faq/).

**Verified:** Foundation `Process` runs and monitors subprocesses with configurable stdin/stdout/stderr; sandboxed children inherit the parent sandbox. Apple exposes menu-bar scenes and a delegate choice to keep the app alive after the last window closes. [Process](https://developer.apple.com/documentation/foundation/process?changes=_8), [MenuBarExtra introduction](https://developer.apple.com/videos/play/wwdc2022/10061/?time=357), [lifecycle](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminateafterlastwindowclosed(_:)).

**Design inference for every shell:** Keep the Codex connection, reconciliation, and durable writes outside the canvas component. Closing the window may leave the application running; explicit Quit ends monitoring unless a separate service is deliberately added. A service is unnecessary if ordinary close-to-tray behavior is desired. Reconnect must reconcile authoritative state after sleep, disconnect, or restart. JSON-RPC framing, reconnect logic, request IDs, and capability validation remain application code; choosing a shell does not supply them. Prefer the supported local transport established by the integration gate. Do not start a second agent runtime merely to obtain a convenient child process.

## Rendering and platform differences

**Verified:** Electron bundles Chromium and Node. Tauri uses Windows WebView2 and WebKit on macOS/Linux; macOS WebKit updates follow OS updates. Wails uses native webviews as well. [Electron process model](https://www.electronjs.org/docs/latest/tutorial/process-model), [Tauri webviews](https://v2.tauri.app/reference/webview-versions/), [Wails FAQ](https://v3.wails.io/faq/).

**Inference:** Electron reduces the browser-engine compatibility matrix; it does not eliminate OS differences. Tauri and Wails avoid shipping a full browser, which is a meaningful packaging advantage for an always-available companion. Actual idle memory, battery cost, startup time, and pan/zoom performance must be measured on this application. No measured ranking or resource figures were established here. On macOS, test pinch zoom, trackpad scrolling, text rendering, drag thresholds, and context menus in WebKit before committing to a webview shell.

**Verified native limitation:** SwiftUI `Canvas` is an immediate-mode drawing surface and does not give individual drawn elements built-in interaction or accessibility. [Apple Canvas documentation](https://developer.apple.com/documentation/swiftui/canvas?changes=__5_7). **Inference:** Interactive notes should use actual views or an AppKit-backed scene with explicit hit testing and accessibility; simply selecting the API named `Canvas` does not implement this product.

## Persistence, distribution, and trust boundary

**Verified:** Tauri's SQL plugin supports SQLite and migrations. Go's `database/sql` requires an additional database driver. Native Swift has SwiftData as a managed persistence option; SQLite also exposes a C interface. [Tauri SQL](https://v2.tauri.app/plugin/sql/), [Go SQL](https://pkg.go.dev/database/sql#Open), [SwiftData](https://developer.apple.com/documentation/swiftdata/), [SQLite interface](https://www.sqlite.org/cintro.html). Native Node addons need Electron-compatible builds because Electron's ABI differs from ordinary Node. [Native Node modules](https://www.electronjs.org/docs/latest/tutorial/using-native-node-modules).

**Inference:** SQLite is appropriate for canvas-owned layout, region geometry, acknowledgment identities, and synchronization bookkeeping across these shells. Keep storage behind domain commands rather than granting the viewer generic SQL access. For Electron, validate the SQLite driver against the selected Electron release and packaged architectures. Do not choose `node:sqlite` solely from current standalone Node documentation: Electron bundles a specific Node version, and that module's documented stability differs by version. [Node SQLite history](https://nodejs.org/api/sqlite.html).

**Verified:** Electron recommends Forge for packaging; built-in autoUpdater supports macOS/Windows, requires a signed macOS app, and has no built-in Linux support. Tauri provides platform bundles, macOS signing instructions, and a signed updater. Native macOS distribution uses Developer ID signing/notarization; Sparkle is an additional update framework with its own setup. [Forge path](https://www.electronjs.org/docs/latest/tutorial/tutorial-packaging), [Electron updater](https://www.electronjs.org/docs/latest/api/auto-updater/), [Tauri distribution](https://v2.tauri.app/distribute/), [Tauri signing](https://v2.tauri.app/distribute/sign/macos/), [Tauri updater](https://v2.tauri.app/plugin/updater/), [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [Sparkle](https://sparkle-project.org/documentation/).

**Inference:** Start with direct local distribution, then add signing and updates when distributing beyond the developer machine. App Store sandbox compatibility needs separate proof for a bridge accessing an existing installation. Every shell must sanitize session content and expose narrow bridge methods. For Electron, retain renderer sandboxing/context isolation and keep process/filesystem operations behind preload IPC. For Tauri, configure scoped capabilities rather than exposing unrestricted shell execution. [Electron security guidance](https://www.electronjs.org/docs/latest/tutorial/security), [Tauri capabilities](https://v2.tauri.app/security/capabilities/).

## Decision-changing evidence still needed

1. Prove the existing-session bridge, project mutation, terminal-result identity, and native navigation before treating any stack as integrated.
2. Establish whether cross-platform delivery is a requirement and whether the implementation team is stronger in TypeScript, Rust, Go, or Swift.
3. Run the same representative canvas/viewer workload on Electron and Tauri if idle footprint is a deciding factor; do not extrapolate from framework marketing.
4. Package a minimal application and verify close/reopen, sleep/reconnect, native context menus, signed updates, and its local transport on each target OS.

These checks can reverse the recommendation. Until then, Electron is the pragmatic first implementation candidate; Tauri 2 is the alternative to retain in the architecture discussion.
