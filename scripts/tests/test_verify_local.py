"""Checks for the persistent verification launcher's output/argument boundary."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("verify_local", Path(__file__).resolve().parents[1] / "verify-local.py")
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)


class VerificationTests(unittest.TestCase):
    def test_swift_build_concurrency_is_bounded(self):
        args = verify.parser().parse_args(["test"])
        command = verify.swift_command(args, "test")
        self.assertEqual(command[command.index("--jobs") + 1], "2")
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            verify.parser().parse_args(["test", "--jobs", "0"])
    def test_outputs_reject_user_database_and_wrong_extension(self):
        for path, suffix in ((Path.home() / "Library/Application Support/Session Canvas/canvas.sqlite", ".sqlite"),
                             (verify.OUTPUT / "capture.sh", ".png")):
            with self.subTest(path=path), self.assertRaises(ValueError):
                verify.output_path(path, suffix)

    def test_outputs_resolve_symlinks_before_checking_boundary(self):
        with tempfile.TemporaryDirectory() as folder:
            link = Path(folder) / "outside"
            link.symlink_to(Path.home() / "Library")
            with self.assertRaises(ValueError):
                verify.output_path(link / "capture.png", ".png")
            self.assertEqual(verify.output_path(Path(folder) / "capture.png", ".png"), Path(folder).resolve() / "capture.png")

    def test_arbitrary_command_options_are_rejected(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            verify.parser().parse_args(["preview", "--executable", "/bin/sh"])

    def test_real_source_is_explicit_even_if_inherited(self):
        with patch.dict(os.environ, {"SESSION_CANVAS_TEST_REAL_SOURCE": "1", "SESSION_CANVAS_TEST_LIVE_DESKTOP": "1", "SESSION_CANVAS_TEST_CAPTURE_CREATION": "/outside.png"}):
            self.assertNotIn("SESSION_CANVAS_TEST_REAL_SOURCE", verify.environment())
            self.assertNotIn("SESSION_CANVAS_TEST_CAPTURE_CREATION", verify.environment(True))
            self.assertEqual(verify.environment(True)["SESSION_CANVAS_TEST_REAL_SOURCE"], "1")
            self.assertNotIn("SESSION_CANVAS_TEST_LIVE_DESKTOP", verify.environment())
            self.assertNotIn("SESSION_CANVAS_TEST_LIVE_DESKTOP", verify.environment(True))
            self.assertEqual(verify.environment(True, True)["SESSION_CANVAS_TEST_LIVE_DESKTOP"], "1")

    def test_live_desktop_cannot_be_enabled_for_a_broad_run(self):
        for arguments in (["test", "--live-desktop"], ["test", "--real-source", "--live-desktop"],
                          ["test", "--real-source", "--live-desktop", "--filter", "LiveStateTests"]):
            with self.subTest(arguments=arguments), patch.object(verify.subprocess, "run") as run, contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                verify.main(arguments)
            run.assert_not_called()

    def test_invalid_output_is_rejected_before_subprocesses(self):
        with patch.object(verify.subprocess, "run") as run, self.assertRaises(ValueError):
            verify.main(["preview", "--capture", str(Path.home() / "outside.png")])
        run.assert_not_called()

    def test_successful_exit_without_fresh_capture_is_failure(self):
        with tempfile.TemporaryDirectory() as folder:
            executable = Path(folder) / "Contents/MacOS/SessionCanvas"
            executable.parent.mkdir(parents=True)
            executable.touch()
            storage, capture = Path(folder) / "canvas.sqlite", Path(folder) / "canvas.png"
            args = verify.parser().parse_args(["preview", "--skip-build"])
            for existing in (False, True):
                if existing:
                    capture.write_bytes(b"\x89PNG\r\n\x1a\nold")
                with self.subTest(existing=existing), patch.object(verify, "BUNDLE", Path(folder)), patch.object(verify.subprocess, "run"), self.assertRaisesRegex(ValueError, "new capture"):
                    verify.capture_window(args, {}, storage, capture)

    def test_preview_defaults_to_demo_and_never_uses_shell(self):
        with tempfile.TemporaryDirectory() as folder:
            executable = Path(folder) / "Contents/MacOS/SessionCanvas"
            executable.parent.mkdir(parents=True)
            executable.touch()
            storage, capture = Path(folder) / "canvas.sqlite", Path(folder) / "canvas.png"
            args = verify.parser().parse_args(["preview", "--show-session", "a; touch /outside"])
            def write_capture(command, **kwargs):
                self.assertIn("--demo", command)
                self.assertIn("a; touch /outside", command)
                self.assertNotIn("shell", kwargs)
                capture.write_bytes(b"\x89PNG\r\n\x1a\nnew")
            with patch.object(verify, "BUNDLE", Path(folder)), patch.object(verify.subprocess, "run", side_effect=write_capture), contextlib.redirect_stdout(io.StringIO()):
                verify.capture_window(args, {}, storage, capture)


if __name__ == "__main__":
    unittest.main()
