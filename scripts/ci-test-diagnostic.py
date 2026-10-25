#!/usr/bin/env python3
"""Temporary bounded probe for hosted Swift test startup."""
import os
from pathlib import Path
import signal
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
output = root / ".build/ci-diagnostics"
output.mkdir(parents=True, exist_ok=True)
command = ["swift", "test", "--disable-xctest"]
print("[DEBUG-ci-startup] Running Swift tests with a 180-second diagnostic deadline", flush=True)
process = subprocess.Popen(command, cwd=root, start_new_session=True)
try:
    sys.exit(process.wait(timeout=180))
except subprocess.TimeoutExpired:
    snapshot = subprocess.check_output(["ps", "-A", "-o", "pid=,ppid=,comm="], text=True)
    processes = [line.strip().split(None, 2) for line in snapshot.splitlines()]
    descendants = {process.pid}
    while True:
        found = {int(pid) for pid, parent, _ in processes if int(parent) in descendants}
        if found.issubset(descendants):
            break
        descendants.update(found)
    selected = [row for row in processes if int(row[0]) in descendants]
    (output / "processes.txt").write_text("\n".join(" ".join(row) for row in selected) + "\n")
    print("[DEBUG-ci-startup] Test startup timed out; capturing owned-process stacks", flush=True)
    for source in (root / ".build").glob("*/debug/SessionCanvasPackageTests.derived/runner.swift"):
        shutil.copy2(source, output / "runner.swift")
    for pid, _, _ in selected[:6]:
        subprocess.run(["sample", pid, "3", "-file", str(output / f"sample-{pid}.txt")], timeout=20, check=False)
    os.killpg(process.pid, signal.SIGTERM)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    sys.exit(1)
