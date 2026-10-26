# History loading performance: diagnosis and repair

Investigation date: 2026-10-26. The reported symptom is a long session freezing the **Session Canvas viewer**, with high CPU usage, especially after it has not been opened recently.

## Implemented behavior

Modern history requests **at most twelve descending turn summaries** (`itemsView: summary`). Only **Load older history** follows the next source cursor; there is no eager full-item request. Existing newest-first display and result identities are preserved. Busy/exhausted-page guards prevent duplicate loads or accidentally reloading the latest page after history ends.

`RPCStreamReader` now reads at most 64 KiB on a dedicated serial dispatch queue, searches only unexamined bytes, and decodes JSON outside the UI actor. Individual frames are bounded to 64 MiB. It waits for each decoded value's UI handoff before continuing; connection generations reject old-reader callbacks. EOF delivers the final complete reply before disconnecting. Blocking I/O does not occupy Swift's cooperative executor.

The original 12,688,490-byte / 36-entry reproduction now takes **0.0943 s**, with a **12.6 ms** maximum UI-actor heartbeat gap and **0.0909 s** of process CPU. Before repair it took 29.91–47.37 s, with 26.45–27.12 s gaps. The performance fixture deliberately still returns the large payload despite summary requests, independently checking the transport repair. All five minimized/original payload cases pass the 250 ms heartbeat budget. These are synthetic transport/adapter measurements, not a live user-session or huge visible-text benchmark.

## Original cause

Previously, `RPCConnection.receive` appended each pipe fragment and searched its growing JSONL buffer **from the beginning again** on `MainActor`. A history response is one large JSON line, so no delimiter is available until the last fragment. For a response of B bytes arriving in fixed-size C fragments, the scans visited approximately B²/(2C) bytes. The UI actor performed this repeated work; a turn-count page limit did not bound it.

The defect was reproduced through the production `CodexSource.history` and `RPCConnection` without constructing a SwiftUI viewer, querying user sessions, observing the desktop, or running model work. A temporary Python server returns prebuilt synthetic JSON; fixture construction and connection initialization are outside the measurement. The test samples a 10 ms `MainActor` heartbeat and asserts a 250 ms maximum gap.

## Baseline measurements and initial prototype

Release build, Apple Silicon, macOS 26.6.2, local development machine. Wall times depend on machine load. Process CPU time measures the test process, excluding the fixture child. Response-byte counts below refer to the encoded result; the JSON-RPC envelope adds 18 bytes.

The original reproduction contained twelve turns with 128 tool outputs of 8192 bytes per turn, but only **36 displayed entries**. Its 12,688,490-byte response took **47.37 s**, with a **27.12 s** heartbeat gap. A second run took **29.91 s**, with a **26.45 s** gap. Both failed the 250 ms assertion. This demonstrates a Canvas-side freeze; it does not measure cold history hydration in the installed Codex server.

Minimizing to one completed turn, one tool-output string, and three displayed entries retains the defect. Removing the tool output leaves the same three displayed entries and a fast control:

| Hidden output | Result bytes | Wall time | Process CPU | Maximum heartbeat gap | Bytes visited by delimiter searches | Search time | JSON decode time |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| None | 208 | 0.0009 s | 0.0005 s | 11 ms | Small control | — | — |
| 1 MiB | 1,048,850 | 0.116 s | 0.106 s | 124 ms | 35,127,589 | 0.114 s | 0.0008 s |
| 2 MiB | 2,097,426 | 0.577 s | 0.457 s | 380 ms | 137,363,749 | 0.569 s | 0.0036 s |
| 4 MiB | 4,194,578 | 2.143 s | 1.755 s | 2135 ms | 543,162,661 | 2.130 s | 0.0034 s |

The four minimized cases completed in 5.43 s, excluding compilation. The 2 and 4 MiB cases failed. Doubling the payload from 2 to 4 MiB roughly quadrupled both scanned bytes and search time. Search dominates this reproduction; generic decoding and transcript projection are not its dominant cost. Temporary instrumentation recorded only byte/count/time values and is removed from the delivered application code.

A temporary prototype changed only delimiter-search progress: unsuccessful scans retained the current buffer length; later fragments searched `buffer.dropFirst(searchOffset)`, and complete frames/connection stop reset the offset. Input, decoder, source, actor, and assertions stayed the same:

| Hidden output | Baseline wall time / maximum UI gap | Incremental-search wall time / maximum UI gap |
| --- | --- | --- |
| 1 MiB | 0.116 s / 124 ms | 0.0098 s / 13 ms |
| 2 MiB | 0.577 s / 380 ms | 0.0245 s / 14 ms |
| 4 MiB | 2.143 s / 2135 ms | 0.0516 s / 30 ms |

At 4 MiB, bytes visited fell from 543,162,661 to 4,194,597 and process CPU from 1.755 s to 0.0252 s. All four heartbeat cases passed with that initial prototype, isolating delimiter rescanning as the fixture cause. The prototype and phase instrumentation were removed at the diagnosis stage. The subsequent permanent repair above also moves framing/decoding off the UI and passes the original twelve-turn fixture; real UI/installed-session acceptance remains separate.

## Protocol and repair status

### Server-side reverse pagination

The 2026-10-26 follow-up regenerated the desktop-bundled **0.164.0-alpha.11.1** schema with `app-server generate-json-schema --experimental`. It declares:

- `thread/turns/list`: `sortDirection: "desc"` (also the default), turn `limit`, opaque `cursor`/`nextCursor`, and `itemsView: "notLoaded" | "summary" | "full"`. The default items view is `summary`.
- `thread/items/list`: `sortDirection: "desc"`, item `limit`, optional `turnId`, and cursor-based continuation. Its default direction is ascending, so descending must be explicit. Each returned item carries its `turnId`.

Canvas already requests descending turn pages and uses `nextCursor` for older history. It reverses each received page into the model's chronological order; the viewer reverses the accumulated entries for newest-first display. Loading older pages prepends them to the model and therefore places them below newer entries in the viewer. This is already server-side latest-page loading, not downloading oldest-first and reversing an entire transcript.

The user selected **summary-only turn pages**. The adapter now uses that mode; it does not request full item detail or add an item-detail viewer. A three-page fixture/model test checks supplied dialogue, plans, result text/IDs, newest-first presentation, manual cursor continuation, duplicate/exhausted actions, and acknowledgment of the newest result after older pages load. A summary is not a claim to include all underlying tool/item detail. A single summary item may still be large, so page counts do not replace frame bounds or off-UI processing.

Protocol capabilities were checked against generated local schemas (`ThreadTurnsListParams`, `ThreadTurnsListResponse`, `ThreadItemsListParams`, `ThreadItemsListResponse`), not a live user session. The schema does not establish whether a cold server internally scans or hydrates the full saved transcript before producing its page. Summary content integration has fixture coverage; actual installed-session presentation remains an acceptance gate.

### Completed and remaining work

| Status | Change | Evidence or remaining checks |
| --- | --- | --- |
| Implemented | Incremental delimiter search and per-frame bounds | Functional checks cover fragmented/coalesced frames, split UTF-8, empty lines, compaction, and complete/incomplete oversized frames. Performance cases include the original twelve-turn reply. |
| Implemented | Serial off-UI framing/decoding and paced handoff | Connection tests verify ordered replies/notifications, old-reader isolation, final response before EOF, and cancellation of a silent reader. Bounded pipe polling lets idle workers observe cancellation. |
| Implemented | Descending summary pages, requested on demand | Model/protocol fixture checks three pages, supplied dialogue/plans/results, no eager full/detail request, duplicate/exhausted-load protection, and stable acknowledgment. |
| Remaining | Revision-aware latest-page caching and per-request cancellation | Reopening revalidates the latest page. Shared-connection cancellation and cache invalidation by source/file/live revision need separate work. |
| Separate compatibility work | Page legacy/local history without materializing every entry first | Legacy `thread/read(includeTurns: true)` loads all turns before a forty-entry local slice. The detached rollout fallback also builds the full transcript, up to its 128 MiB limit, before slicing. A validated byte-offset/index or incremental reader needs its own correctness checks. |
| Separate UI work | Exercise exceptionally long visible messages; split or progressively expand oversized text where needed | `LazyVStack` limits rows, not the layout cost of one huge selectable `Text`. The transport reproduction contains tiny visible strings and establishes no text-layout performance result. |

The shipped boundary now uses linear framing and serial decoding with one paced UI delivery at a time. A broader presentation-model byte limit or huge visible-text layout policy remains separate work.

## Why old, long sessions make it noticeable

Opening a session clears the model history and calls the source again. Modern latest pages are not cached for viewer reuse. Legacy cached entries are also reread whenever the cursor is nil. At diagnosis, twelve full turns could contain large hidden tool outputs; modern summary mode now avoids requesting that full detail.

There is no age-based branch in this viewer-loading path. A cold server cache or remote/lazy history hydration could add latency for sessions unused for a long time, but was not measured here. The exact contribution on the user's session remains unverified. The UI freeze already reproduces with a prebuilt local reply.

`ApplicationModel` rejects stale source/selection replies and uses per-load tokens to preserve the current viewer's loading state. Closing/replacing a connection cancels its reader and invalidates callbacks. Per-request cancellation of a response already arriving over the shared connection is not implemented. The 20-second timeout can run while decoding proceeds off the UI actor; the 64 MiB frame cap remains a size guard rather than a text-layout guarantee.

## Reproduction and acceptance

```sh
python3 /Users/d-manakovskiy/personal/session-canvas/scripts/verify-local.py test --configuration release --history-performance --jobs 1
```

This explicit command selects `HistoryPerformanceTests`; all minimized and original-payload assertions now pass. Normal tests skip this timing suite, even if its environment switch was inherited, while functional transport/pagination checks remain enabled. The fixture-only mode cannot be combined with installed-source checks. Output contains synthetic byte/count/time measurements, never user history.

Before the permanent repair, the uninstrumented baseline failed again on 2 and 4 MiB: wall times were 0.463 s and 1.897 s, with maximum heartbeat gaps of 463 ms and 1897 ms. In the final performance-only run, the same sizes took 0.0128 s and 0.0217 s, with gaps of 12.6 ms each; process CPU was 0.0121 s and 0.0208 s. The original rich 12.1 MiB case took 0.0943 s / 12.6 ms gap. The full ordinary run reported 94 runtime and 56 core tests passing with timing/installed-source opt-ins skipped; a separate performance-only run passed two tests covering all five payload cases.

The [OpenSpec tasks](../openspec/changes/add-session-canvas/tasks.md#25-long-history-viewer-responsiveness) record completed summary pagination, transport repair, and synthetic regressions, while retaining cache/legacy work, huge visible text, and a specifically authorized representative installed-session check. The responsiveness requirement is [session-actions](../openspec/changes/add-session-canvas/specs/session-actions/spec.md#requirement-history-loading-preserves-ui-responsiveness); the diagnostic contract is [local-verification](../openspec/changes/add-session-canvas/specs/local-verification/spec.md#requirement-synthetic-history-responsiveness-regression).

**Open in Codex** remains available from the note's context menu. This report makes no performance claim about Codex's own viewer.
