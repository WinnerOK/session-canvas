#!/usr/bin/env python3
"""Build a local macOS .app bundle; optionally sign with a supplied identity."""
import argparse
import pathlib
import plistlib
import re
import shutil
import subprocess
import sys

VERSION_PATTERN = r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
ROOT = pathlib.Path(__file__).resolve().parent.parent


def version(value):
    if not re.fullmatch(VERSION_PATTERN, value):
        raise argparse.ArgumentTypeError("Version must be MAJOR.MINOR.PATCH (for example, 0.2.0)")
    return value


def build_number(value):
    if not re.fullmatch(r"[1-9][0-9]*", value):
        raise argparse.ArgumentTypeError("Build number must be a positive integer")
    return value


def parser():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--local-toolchain", action="store_true", help="Use the opt-in workaround for the development machine's mismatched SwiftPM interfaces")
    cli.add_argument("--debug", action="store_true")
    cli.add_argument("--binary", type=pathlib.Path, help="Package an already-built executable instead of invoking SwiftPM")
    cli.add_argument("--sign", default="-", help="Codesigning identity; default is an ad-hoc local signature")
    cli.add_argument("--version", type=version, default="0.1.0")
    cli.add_argument("--build-number", type=build_number, default="1")
    return cli


def build_app(args, root=ROOT):
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
    resources_dir = bundle / "Contents/Resources"
    resources_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(root / "assets/branding/SessionCanvas.icns", resources_dir / "SessionCanvas.icns")
    info = {
        "CFBundleName": "Session Canvas", "CFBundleDisplayName": "Session Canvas",
        "CFBundleIdentifier": "local.sessioncanvas.app", "CFBundleExecutable": "SessionCanvas",
        "CFBundleIconFile": "SessionCanvas.icns",
        "CFBundlePackageType": "APPL", "CFBundleShortVersionString": args.version, "CFBundleVersion": args.build_number,
        "LSMinimumSystemVersion": "14.0", "LSApplicationCategoryType": "public.app-category.developer-tools",
        "NSHighResolutionCapable": True, "NSPrincipalClass": "NSApplication",
    }
    with (bundle / "Contents/Info.plist").open("wb") as output:
        plistlib.dump(info, output)
    subprocess.run(["codesign", "--force", "--sign", args.sign, str(bundle)], check=True)
    return bundle


if __name__ == "__main__":
    print(build_app(parser().parse_args()))
