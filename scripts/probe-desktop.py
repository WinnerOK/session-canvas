#!/usr/bin/env python3
"""Observe an existing desktop thread. Print state/structure only, never dialogue."""
import argparse
import json
import pathlib
import socket
import struct
import time
import uuid

parser = argparse.ArgumentParser()
parser.add_argument("thread")
parser.add_argument("--socket", default=str(pathlib.Path.home() / ".codex/ipc/ipc.sock"))
parser.add_argument("--expect-running", action="store_true")
args = parser.parse_args()
client = "initializing-client"
connection = socket.socket(socket.AF_UNIX)
connection.settimeout(8)

def send(message):
    data = json.dumps(message).encode()
    connection.sendall(struct.pack("<I", len(data)) + data)

def receive():
    def read(count):
        data = b""
        while len(data) < count:
            chunk = connection.recv(count - len(data))
            if not chunk:
                raise RuntimeError("desktop disconnected")
            data += chunk
        return data
    length = struct.unpack("<I", read(4))[0]
    if not 0 < length <= 64 * 1024 * 1024:
        raise RuntimeError("unsupported desktop frame size")
    return json.loads(read(length))

def follow(value):
    send({"type": "broadcast", "method": "thread-stream-following-changed", "sourceClientId": client,
          "version": 1, "params": {"conversationId": args.thread, "hostId": "local", "following": value}})

try:
    connection.connect(args.socket)
    request_id = str(uuid.uuid4())
    send({"type": "request", "method": "initialize", "requestId": request_id,
          "sourceClientId": client, "version": 0, "params": {"clientType": "session-canvas"}})
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        message = receive()
        if message.get("type") == "client-discovery-request":
            send({"type": "client-discovery-response", "requestId": message["requestId"], "response": {"canHandle": False}})
        if message.get("requestId") == request_id and message.get("resultType") == "success":
            client = message["result"]["clientId"]
            follow(True)
        if message.get("method") != "thread-stream-state-changed":
            continue
        params = message.get("params", {})
        change = params.get("change", {})
        if params.get("conversationId") != args.thread or change.get("type") != "snapshot":
            continue
        state = change["conversationState"]
        turns = state.get("turns", [])
        canonical = state.get("turnHistory", {}).get("history", {}).get("entitiesByKey", {})
        if canonical:
            turns = list(canonical.values())
        statuses = [turn.get("status") for turn in turns]
        evidence = {"connected": True, "snapshot_version": message.get("version"), "state_fields": sorted(state),
                    "runtime_status": state.get("threadRuntimeStatus"), "resume_state": state.get("resumeState"),
                    "turn_statuses": statuses[-3:], "latest_turn_fields": sorted(turns[-1]) if turns else [],
                    "request_shapes": [sorted(r) for r in state.get("requests", [])]}
        print(json.dumps(evidence, indent=2))
        if args.expect_running and "inProgress" not in statuses:
            raise RuntimeError("running desktop session did not have an inProgress turn")
        break
    else:
        raise RuntimeError("desktop did not send a conversation snapshot")
finally:
    if client != "initializing-client":
        follow(False)
    connection.close()
