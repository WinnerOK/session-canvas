#!/usr/bin/env python3
"""Build a local macOS .app bundle; optionally sign with a supplied identity."""
import argparse
import pathlib
import plistlib
import shutil
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--local-toolchain", action="store_true", help="Use the opt-in workaround for the development machine's mismatched SwiftPM interfaces")
parser.add_argument("--debug", action="store_true")
parser.add_argument("--binary", type=pathlib.Path, help="Package an already-built executable instead of invoking SwiftPM")
parser.add_argument("--sign", default="-", help="Codesigning identity; default is an ad-hoc local signature")
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parent.parent
runner = [sys.executable, str(root / "scripts/swift-local.py")] if args.local_toolchain else ["swift"]
configuration = "debug" if args.debug else "release"
if args.binary:
    binary = args.binary.resolve()
else:
    subprocess.run(runner + ["build", "-c", configuration], cwd=root, check=True)
    binary_dir = pathlib.Path(subprocess.check_output(runner + ["build", "-c", configuration, "--show-bin-path"], cwd=root, text=True).strip())
    binary = binary_dir / "SessionCanvas"
bundle = root / "dist/Session Canvas.app"
executable_dir = bundle / "Contents/MacOS"
executable_dir.mkdir(parents=True, exist_ok=True)
shutil.copy2(binary, executable_dir / "SessionCanvas")
info = {
    "CFBundleName": "Session Canvas", "CFBundleDisplayName": "Session Canvas",
    "CFBundleIdentifier": "local.sessioncanvas.app", "CFBundleExecutable": "SessionCanvas",
    "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1",
    "LSMinimumSystemVersion": "14.0", "LSApplicationCategoryType": "public.app-category.developer-tools",
    "NSHighResolutionCapable": True, "NSPrincipalClass": "NSApplication",
}
with (bundle / "Contents/Info.plist").open("wb") as output:
    plistlib.dump(info, output)
subprocess.run(["codesign", "--force", "--sign", args.sign, str(bundle)], check=True)
print(bundle)
