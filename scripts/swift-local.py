#!/usr/bin/env python3
"""Opt-in workaround for this machine's stale private PackageDescription interface.

Normal installations should use `swift build` and `swift test` directly.
"""
import os
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
api = pathlib.Path("/Library/Developer/CommandLineTools/usr/lib/swift/pm/ManifestAPI")
out = root / ".build/manifest-api"
out.mkdir(parents=True, exist_ok=True)
target = subprocess.check_output(["uname", "-m"], text=True).strip() + "-apple-macos"
module = out / "PackageDescription.swiftmodule"
if not module.exists():
    sdk = subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip()
    subprocess.run(["swiftc", "-frontend", "-compile-module-from-interface", str(api / "PackageDescription.swiftmodule" / (target + ".swiftinterface")),
                    "-module-name", "PackageDescription", "-target", target + "x14.0", "-sdk", sdk, "-package-description-version", "6.0.0",
                    "-module-cache-path", str(root / ".build/compiler-cache"), "-o", str(module)], check=True)
wrapper = root / "scripts/swift-manifest-compiler.sh"
wrapper.chmod(0o755)
task_env = os.environ.copy()
task_env["SWIFT_EXEC_MANIFEST"] = str(wrapper)
subprocess.run(["swift", *sys.argv[1:]], cwd=root, env=task_env, check=True)
