#!/usr/bin/env python3
"""Build a versioned macOS ZIP and SHA-256 file for one release architecture."""
import argparse
import hashlib
import importlib.util
from pathlib import Path
import subprocess

spec = importlib.util.spec_from_file_location("build_app", Path(__file__).with_name("build-app.py"))
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


def release_tag(value):
    if not value.startswith("v"):
        raise argparse.ArgumentTypeError("Release tag must be vMAJOR.MINOR.PATCH")
    builder.version(value[1:])
    return value


def parser():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("--tag", required=True, type=release_tag)
    cli.add_argument("--build-number", required=True, type=builder.build_number)
    cli.add_argument("--arch", required=True, choices=("arm64", "x86_64"))
    cli.add_argument("--binary", type=Path, help="Package an existing executable (for local verification)")
    return cli


def package(args, root=builder.ROOT):
    options = builder.parser().parse_args(["--version", args.tag[1:], "--build-number", args.build_number])
    options.binary = args.binary
    bundle = builder.build_app(options, root=root)
    binary = bundle / "Contents/MacOS/SessionCanvas"
    subprocess.run(["lipo", "-verify_arch", args.arch, str(binary)], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(bundle)], check=True)
    archive = root / "dist" / f"SessionCanvas-{args.tag}-macos-{args.arch}.zip"
    subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(bundle), str(archive)], check=True)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    archive.with_suffix(".zip.sha256").write_text(f"{digest}  {archive.name}\n", encoding="utf-8")
    return archive


if __name__ == "__main__":
    print(package(parser().parse_args()))
