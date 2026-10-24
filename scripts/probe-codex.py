#!/usr/bin/env python3
"""Read-only protocol probe. Prints capabilities/counts, never session contents."""
import argparse
import json
import selectors
import shutil
import subprocess
import time
import pathlib

parser = argparse.ArgumentParser()
parser.add_argument("--history", action="store_true")
parser.add_argument("--all-pages", action="store_true")
parser.add_argument("--read-first", action="store_true")
parser.add_argument("--read-index", type=int, default=0)
parser.add_argument("--paged", action="store_true")
parser.add_argument("--experimental", action="store_true")
parser.add_argument("--inspect-rollout-structure", action="store_true")
parser.add_argument("--native-reader", help="Path to the built SessionCanvasProbe; prints only native-parser counts")
args = parser.parse_args()
command = [shutil.which("codex") or "codex", "app-server"]
command += ["--listen", "stdio://"] if args.history else ["proxy"]
proc = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
selector = selectors.DefaultSelector()
selector.register(proc.stdout, selectors.EVENT_READ)
selector.register(proc.stderr, selectors.EVENT_READ)

def request(ident, method, params):
    proc.stdin.write((json.dumps({"id": ident, "method": method, "params": params}) + "\n").encode())
    proc.stdin.flush()
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            raise RuntimeError("proxy exited with status " + str(proc.returncode))
        for key, _ in selector.select(0.2):
            line = key.fileobj.readline()
            if key.fileobj is proc.stderr:
                # Do not print arbitrary diagnostic output or potentially private paths.
                if b"Operation not permitted" in line:
                    raise PermissionError("local socket or runtime access denied by sandbox")
                if b"No such file" in line or b"Connection refused" in line:
                    raise RuntimeError("no reachable shared app-server control socket")
                continue
            if not line:
                continue
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                continue
            if value.get("id") == ident:
                if "error" in value:
                    message = value["error"].get("message", "").lower()
                    categories = [term for term in ["unknown variant", "unknown method", "not found", "rollout", "not loaded", "not materialized", "paginated", "invalid", "deserialize", "permission", "no such file", "unsupported"] if term in message]
                    raise RuntimeError("RPC error code " + str(value["error"].get("code")) + " for " + method + "; categories=" + ",".join(categories))
                return value.get("result", {})
    raise TimeoutError("no protocol response within 12 seconds")

try:
    init_params = {"clientInfo": {"name": "session_canvas_probe", "title": "Session Canvas probe", "version": "0.1.0"}}
    if args.experimental:
        init_params["capabilities"] = {"experimentalApi": True}
    initialized = request(1, "initialize", init_params)
    proc.stdin.write(b'{"method":"initialized"}\n')
    proc.stdin.flush()
    listed = request(2, "thread/list", {"limit": 5, "archived": False, "sourceKinds": ["cli", "vscode", "appServer", "unknown"], "useStateDbOnly": True})
    rows = listed.get("data", [])
    cursor = listed.get("nextCursor")
    ident = 2
    pages = 1
    cursors = set()
    while args.all_pages and cursor:
        if cursor in cursors:
            raise RuntimeError("inventory repeated a pagination cursor")
        cursors.add(cursor)
        ident += 1
        page = request(ident, "thread/list", {"limit": 100, "cursor": cursor, "archived": False, "sourceKinds": ["cli", "vscode", "appServer", "unknown"], "useStateDbOnly": True})
        rows.extend(page.get("data", []))
        cursor = page.get("nextCursor")
        pages += 1
    evidence = {"connected": True, "mode": "history" if args.history else "shared", "sample_count": len(rows), "pages": pages,
                "has_more": cursor is not None, "unique_id_count": len({r["id"] for r in rows}),
                "runtime_state_types": sorted({str(r.get("status", {}).get("type")) for r in rows}), "initialize_fields": sorted(initialized.keys())}
    if args.native_reader and rows:
        selected = rows[args.read_index]
        parsed = subprocess.run([args.native_reader, selected["path"], initialized["codexHome"], selected["id"]], capture_output=True, text=True)
        if parsed.returncode:
            raise RuntimeError("native saved-history reader could not verify the selected source record")
        evidence["native_reader"] = json.loads(parsed.stdout)
    if args.inspect_rollout_structure and rows:
        selected = rows[args.read_index]
        raw_path = selected.get("path")
        evidence["rollout_path_available"] = bool(raw_path)
        if raw_path:
            home = pathlib.Path(initialized["codexHome"]).resolve()
            path = pathlib.Path(raw_path).resolve()
            if not (path.is_relative_to(home / "sessions") or path.is_relative_to(home / "archived_sessions")):
                raise RuntimeError("rollout path is outside the source sessions directories")
            structures = {}
            with path.open() as handle:
                for index, line in enumerate(handle):
                    if index >= 10000:
                        break
                    row = json.loads(line)
                    payload = row.get("payload", {})
                    key = str(row.get("type")) + "/" + str(payload.get("type", payload.get("role", "")))
                    structures[key] = sorted(payload.keys())
            evidence["rollout_structure"] = structures
    if args.read_first and rows:
        ident += 1
        selected = rows[args.read_index]
        if args.paged:
            page = request(ident, "thread/turns/list", {"threadId": selected["id"], "limit": 5, "sortDirection": "desc", "itemsView": "full"})
            turns = page.get("data", [])
            evidence["paged_history_count"] = len(turns)
        else:
            history = request(ident, "thread/read", {"threadId": selected["id"], "includeTurns": True}).get("thread", {})
            evidence["history_identity_matches"] = history.get("id") == selected["id"]
            turns = history.get("turns", [])
        evidence["history_turn_count"] = len(turns)
        evidence["history_terminal_count"] = sum(t.get("status") in ["completed", "failed", "interrupted"] for t in turns)
    print(json.dumps(evidence, indent=2))
except (RuntimeError, PermissionError, TimeoutError, BrokenPipeError, OSError) as error:
    if isinstance(error, OSError):
        error = RuntimeError("local source file or process is unavailable")
    print(json.dumps({"connected": False, "mode": "history" if args.history else "shared", "reason": str(error)}, indent=2))
    raise SystemExit(1)
finally:
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
