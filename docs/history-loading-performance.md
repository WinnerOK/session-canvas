# History loading performance investigation

Investigation date: 2026-10-26. The reported symptom is a long session freezing the **Session Canvas viewer**, with high CPU usage, especially after it has not been opened recently.

## Confirmed cause

`RPCConnection.receive` runs on `MainActor`. Each pipe fragment is appended to a JSONL buffer, then `buffer.firstIndex(of: 10)` searches **from the beginning again**. A history response is one large JSON line, so no delimiter is available until the last fragment. For a response of B bytes arriving in fixed-size C fragments, the scans visit approximately B²/(2C) bytes. The UI actor performs this repeated work; a turn-count page limit does not bound it.

The defect reproduces through the production `CodexSource.history` and `RPCConnection` without constructing a SwiftUI viewer, querying user sessions, observing the desktop, or running model work. A temporary Python server returns prebuilt synthetic JSON; fixture construction and connection initialization are outside the measurement. The test samples a 10 ms `MainActor` heartbeat and asserts a 250 ms maximum gap.

## Measurements

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

At 4 MiB, bytes visited fell from 543,162,661 to 4,194,597 and process CPU from 1.755 s to 0.0252 s. All four heartbeat cases passed with the prototype. This isolates delimiter rescanning as the cause in this fixture. The prototype and phase instrumentation were then removed; this investigation delivers the diagnosis and regression, with application repair still open. The twelve-turn original fixture and real UI were not rerun against the prototype, so its small-fixture pass does not establish complete repair acceptance.

## Repair order

| Priority | Change | Expected benefit and required checks |
| --- | --- | --- |
| First | Retain an incremental delimiter-search offset, inspecting only bytes received since the preceding unsuccessful search; reset correctly after complete frames and reconnect | Removes the reproduced quadratic scan. Cover split delimiters, multiple lines per chunk, incomplete frames, size limits, and connection replacement. Preserve ordered delivery. |
| Next | Move framing and decoding to a serial worker, with bounded queued bytes and a small UI handoff | Protects the UI from large frames, many small frames, JSON decoding, and allocation even after the search fix. Moving the existing quadratic loop alone would keep the wasted CPU and slow load. Validate disconnect/order/cancellation races. |
| Next | Limit useful history work by bytes/content as well as turns; project only supported dialogue/result fields, and use a verified lighter server view if available | `itemsView: full` currently transfers hidden tool data that is later discarded. One turn can still be huge. Preserve result IDs, errors, plans, and outcome evidence; do not assume an unverified protocol option exists. |
| Next | Add bounded revision-aware latest-page caching and in-flight deduplication/cancellation | Reopening currently requests the latest page again. Invalidate by source/session revision, file revision and live changes; explicit Reload must revalidate. Bound cache memory and prevent stale results/acknowledgment targets. |
| Separate compatibility work | Page legacy/local history without materializing every entry first | Legacy `thread/read(includeTurns: true)` loads all turns before a forty-entry local slice. The detached rollout fallback also builds the full transcript, up to its 128 MiB limit, before slicing. A validated byte-offset/index or incremental reader needs its own correctness checks. |
| Separate UI work | Exercise exceptionally long visible messages; split or progressively expand oversized text where needed | `LazyVStack` limits rows, not the layout cost of one huge selectable `Text`. The transport reproduction contains tiny visible strings and establishes no text-layout performance result. |

The smallest first repair is incremental framing. The longer-term boundary is a serial history pipeline that delivers a bounded presentation model to the UI actor.

## Why old, long sessions make it noticeable

Opening a session clears the model history and calls the source again. Modern latest pages are not cached for viewer reuse. Legacy cached entries are also reread whenever the cursor is nil. Long histories can contain large outputs that the viewer never displays, and twelve full turns can therefore form a large JSON line. These code paths explain repeated expensive Canvas work.

There is no age-based branch in this viewer-loading path. A cold server cache or remote/lazy history hydration could add latency for sessions unused for a long time, but was not measured here. The exact contribution on the user's session remains unverified. The UI freeze already reproduces with a prebuilt local reply.

`ApplicationModel` rejects stale replies after source/selection changes, but cancellation does not stop `RPCConnection` parsing. Its 20-second timeout task also needs the UI actor and cannot preempt a synchronous scan/decode running there. The 64 MiB transport-buffer cap is a size guard, not a responsiveness guarantee.

## Reproduction and acceptance

```sh
python3 /Users/d-manakovskiy/personal/session-canvas/scripts/verify-local.py test --configuration release --history-performance --jobs 1
```

This explicit command selects `HistoryPerformanceTests`; its performance assertions currently fail against the unchanged production transport. Normal tests skip the suite, even if its environment switch was inherited. The fixture-only mode cannot be combined with installed-source checks. Output contains synthetic byte/count/time measurements, never user history.

The final replay after removing the prototype/instrumentation failed again on 2 and 4 MiB: wall times were 0.463 s and 1.897 s, with maximum heartbeat gaps of 463 ms and 1897 ms. Those cases used 0.426 s and 1.722 s of process CPU, respectively. The four-case run took 3.78 s excluding compilation. This is the delivered regression baseline, not a successful responsiveness check.

Application behavior has not been changed by this investigation. The [OpenSpec tasks](../openspec/changes/add-session-canvas/tasks.md#25-long-history-viewer-responsiveness) keep the repair, cancellation/cache work, huge visible text, and a specifically authorized representative installed-session check open. The responsiveness requirement is [session-actions](../openspec/changes/add-session-canvas/specs/session-actions/spec.md#requirement-history-loading-preserves-ui-responsiveness); the diagnostic contract is [local-verification](../openspec/changes/add-session-canvas/specs/local-verification/spec.md#requirement-synthetic-history-responsiveness-regression).

For immediate use, choose **Open in Codex** from the note's context menu. That bypasses Canvas's viewer history path; this investigation makes no performance claim about Codex's own viewer. Changing layer/age filters or increasing timeouts does not remove the repeated scan.
