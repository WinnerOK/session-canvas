#!/bin/bash
# Local workaround for mismatched public/private PackageDescription interfaces.
# Enabled only by scripts/swift-local.py; never changes the installed toolchain.
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
exec /Library/Developer/CommandLineTools/usr/bin/swiftc -Xfrontend "-swift-module-file=PackageDescription=$task_root/.build/manifest-api/PackageDescription.swiftmodule" "$@"
