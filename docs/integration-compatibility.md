# Codex integration compatibility

Verified on 2026-10-24 using Codex CLI 0.146.1 on this Mac. The native application implements the available subset and exposes the remaining limits directly in its connection UI.

## Evidence

- Generated the installed CLI's app-server JSON schema with `codex app-server generate-json-schema --out /private/tmp/session-canvas-protocol`.
- Ran `python3 scripts/probe-codex.py` outside the sandbox after the initial sandbox denied local socket access. The shared proxy reported no reachable existing control socket. No daemon was started or reconfigured.
- Ran `python3 scripts/probe-codex.py --history --all-pages`: initialization and all five pages in the queried source set succeeded, returning 390 unique session identities. Every observed runtime status was `notLoaded`.
- The installed stable schema exposes `thread/list` and `thread/read(includeTurns:)`, but no project-list or project-membership mutation method. Regenerating with `--experimental` reveals `thread/turns/list`; it needs experimental-capability negotiation. Actual newer desktop histories still failed CLI decoding, while legacy `thread/read` rejected their paginated format.
- Verified the native compatibility reader against an inventory-identified existing session: it checked the session identity and returned 26 dialogue/result entries, including two terminal outcomes. Only counts were printed.
- `/Applications/ChatGPT.app/Contents/Info.plist` registers the `codex` URL scheme. The app dispatches `codex://threads/{id}` through the registered handler. URL registration confirms dispatch capability; it does not prove that every installed host version resolves that route to the intended conversation.

The probe prints only connection/capability information and counts; it never prints conversation contents. No real turn, project mutation, or permission approval was submitted during these checks.

## Implemented sources

| Source | Discovery/history | Current execution | Project mutation | Creation |
| --- | --- | --- | --- | --- |
| Saved Codex sessions (default) | Real existing sessions via the installed CLI; complete inventory pagination; history read without resuming a turn | Unknown: a separate reader cannot establish the desktop runtime's current state | Unavailable | Unavailable |
| Shared Codex server | Connects using `codex app-server proxy [--sock PATH]`; requires a reachable server | Maps authoritative loaded-thread runtime states; `notLoaded` remains Unknown | Unavailable in the verified public protocol | Disabled until same-desktop-source creation and request ownership can be verified |
| Demo workspace | Isolated native sample workspace, clearly labeled | Simulated states, including a short new-session completion | Simulated confirmed moves, with the same canvas-domain rules | Simulated only; never invokes a model |

Actual Codex projects are not inferred from `cwd` and are not written into private databases. As a result, saved-session mode has no project regions. Demo mode contains sample regions for evaluating interaction behavior. A real cross-region operation is rejected instead of becoming a local tag.

## History compatibility

The adapter negotiates experimental APIs and tries paginated history first, then legacy `thread/read`. For incompatible desktop records, it reads the exact local rollout path supplied by the inventory. The reader resolves symlinks, restricts the file to the connected Codex home's session directories, and checks its session identity before displaying content. It never enumerates the home directory, writes source files, or derives live activity from file timestamps.

Legacy/local fallback entries are shown in pages of 40. Local reading is bounded at 128 MB per file and 16 MB per record, with incomplete trailing appends ignored. A missing file, identity mismatch, path escape, or size limit produces an error without an acknowledgment action for unloaded content. The local fallback shows dialogue actually recorded in that file; a fork's separately referenced ancestral history is not synthesized.

Only user messages, assistant messages, plans, and terminal outcomes are presented. Arbitrary tool payloads and hidden reasoning are excluded. The app never calls `thread/resume`, `turn/start`, or an approval-response method in either real source mode.

## Remaining integration gate

The original full desktop integration gate has **not passed**. Real existing-session discovery and saved history are implemented. Live desktop observation, actual project membership, same-source session creation, and exact native route resolution still need a supported host connection and end-to-end verification.

The native UI/domain/storage implementation can be evaluated independently through demo mode. Do not report the demo as a completed desktop integration. To complete the remaining work, provide a supported shared/host interface for actual project operations and session creation; the narrow `SessionSource` boundary is the integration point.

Official protocol reference: [App Server](https://learn.chatgpt.com/docs/app-server). Installed generated schemas take precedence when choosing methods for CLI 0.146.1.
