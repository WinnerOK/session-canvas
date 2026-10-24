#!/usr/bin/env python3
"""Build, test, or capture Session Canvas through one stable Codex command."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / ".build/verification"
BUNDLE = ROOT / "dist/Session Canvas.app"


def output_path(value, suffix):
    path = Path(value).expanduser().resolve()
    roots = (OUTPUT, Path("/private/tmp"), Path(tempfile.gettempdir()),
             Path.home() / ".codex/visualizations")
    if path.suffix != suffix or not any(path.is_relative_to(root.resolve()) for root in roots):
        raise ValueError(f"Use a {suffix} file under .build/verification, a temporary directory, or ~/.codex/visualizations")
    return path


def parser():
    cli = argparse.ArgumentParser(description=__doc__)
    commands = cli.add_subparsers(dest="command", required=True)
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--standard-toolchain", action="store_true", help="Use Swift directly instead of this machine's manifest workaround")
    common.add_argument("--configuration", choices=("debug", "release"), default="debug")
    common.add_argument("--jobs", type=int, choices=range(1, 9), default=2, help="Maximum parallel Swift build jobs (default: 2)")
    commands.add_parser("build", parents=[common], help="Build and sign the local app bundle")
    tests = commands.add_parser("test", parents=[common], help="Run Swift Testing, with optional installed-source checks")
    tests.add_argument("--real-source", action="store_true")
    tests.add_argument("--live-desktop", action="store_true", help="Connect one live desktop observer; requires separate user authorization and the exact live test filter")
    tests.add_argument("--filter", help="Swift Testing name filter")
    preview = commands.add_parser("preview", parents=[common], help="Build, capture a native window, then exit")
    preview.add_argument("--source", choices=("demo", "desktop"), default="demo")
    preview.add_argument("--storage", help="Separate verification .sqlite file; a fresh one is used by default")
    preview.add_argument("--capture", help="Output .png; defaults to a fresh directory under .build/verification")
    preview.add_argument("--show-session")
    preview.add_argument("--created-session-preview", action="store_true")
    preview.add_argument("--hide-sidebar", action="store_true")
    preview.add_argument("--show-result", action="store_true")
    preview.add_argument("--skip-build", action="store_true", help="Inspect the existing bundle instead of rebuilding it")
    return cli


def environment(real_source=False, live_desktop=False):
    task_env = os.environ.copy()
    task_env.pop("SESSION_CANVAS_TEST_REAL_SOURCE", None)
    task_env.pop("SESSION_CANVAS_TEST_LIVE_DESKTOP", None)
    task_env.pop("SESSION_CANVAS_TEST_CAPTURE_CREATION", None)
    if real_source:
        task_env["SESSION_CANVAS_TEST_REAL_SOURCE"] = "1"
    if live_desktop:
        task_env["SESSION_CANVAS_TEST_LIVE_DESKTOP"] = "1"
    cache = str(ROOT / ".build/compiler-cache")
    task_env["CLANG_MODULE_CACHE_PATH"] = cache
    task_env["SWIFT_MODULECACHE_PATH"] = cache
    return task_env


def swift_command(args, action):
    runner = ["swift"] if args.standard_toolchain else [sys.executable, str(ROOT / "scripts/swift-local.py")]
    return runner + [action, "-c", args.configuration,
                     "--jobs", str(args.jobs),
                     "--cache-path", str(OUTPUT / "swiftpm-cache"), "--manifest-cache", "local",
                     "-Xswiftc", "-module-cache-path", "-Xswiftc", str(ROOT / ".build/compiler-cache")]


def build_bundle(args, task_env):
    command = swift_command(args, "build")
    subprocess.run(command, cwd=ROOT, env=task_env, check=True)
    binary_dir = subprocess.check_output(command + ["--show-bin-path"], cwd=ROOT, env=task_env, text=True).strip()
    subprocess.run([sys.executable, str(ROOT / "scripts/build-app.py"), "--binary", str(Path(binary_dir) / "SessionCanvas")],
                   cwd=ROOT, env=task_env, check=True)


def capture_window(args, task_env, storage, capture):
    executable = BUNDLE / "Contents/MacOS/SessionCanvas"
    if not executable.is_file():
        raise ValueError("Build the app first, or omit --skip-build")
    for path in (storage, capture):
        path.parent.mkdir(parents=True, exist_ok=True)
    before = capture.stat().st_mtime_ns if capture.exists() else None
    command = [str(executable), "--storage", str(storage), "--capture", str(capture)]
    if args.source == "demo":
        command.append("--demo")
    if args.show_session:
        command += ["--show-session", args.show_session]
    for flag in ("created_session_preview", "hide_sidebar", "show_result"):
        if getattr(args, flag):
            command.append("--" + flag.replace("_", "-"))
    subprocess.run(command, cwd=ROOT, env=task_env, check=True, timeout=45)
    if not capture.is_file() or capture.stat().st_mtime_ns == before:
        raise ValueError("The app exited without writing a new capture")
    with capture.open("rb") as image:
        if image.read(8) != b"\x89PNG\r\n\x1a\n":
            raise ValueError("The capture is not a PNG")
    print(f"Capture: {capture}", flush=True)
    print(f"Storage: {storage}", flush=True)


def main(argv=None):
    cli = parser()
    args = cli.parse_args(argv)
    if getattr(args, "live_desktop", False) and (not args.real_source or args.filter != "installedDesktopFeedsLiveStateIntoTheApplication"):
        cli.error("--live-desktop requires --real-source --filter installedDesktopFeedsLiveStateIntoTheApplication; authorize that single live run separately")
    # Validate outputs before building or launching anything.
    storage = output_path(args.storage, ".sqlite") if getattr(args, "storage", None) else None
    capture = output_path(args.capture, ".png") if getattr(args, "capture", None) else None
    if getattr(args, "created_session_preview", False) and not args.show_session:
        cli.error("--created-session-preview requires --show-session")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    (ROOT / ".build/compiler-cache").mkdir(parents=True, exist_ok=True)
    task_env = environment(getattr(args, "real_source", False), getattr(args, "live_desktop", False))
    if args.command == "test":
        command = swift_command(args, "test") + ["--disable-xctest"]
        if args.filter:
            command += ["--filter", args.filter]
        subprocess.run(command, cwd=ROOT, env=task_env, check=True)
    else:
        if not getattr(args, "skip_build", False):
            build_bundle(args, task_env)
        if args.command == "preview":
            run_dir = Path(tempfile.mkdtemp(prefix="preview-", dir=OUTPUT))
            capture_window(args, task_env, storage or run_dir / "canvas.sqlite", capture or run_dir / "canvas.png")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"Verification failed: {error}", file=sys.stderr)
        sys.exit(1)
