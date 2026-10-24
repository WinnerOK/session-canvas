"""Release metadata, failure propagation, and distributable integrity checks."""
import argparse
import contextlib
import hashlib
import importlib.util
import io
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("package_release", Path(__file__).resolve().parents[1] / "package-release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
builder = release.builder


class ReleasePackagingTests(unittest.TestCase):
    def test_malformed_metadata_is_rejected_before_building(self):
        with patch.object(builder, "build_app") as build:
            for tag in ("1.2.3", "v1.2", "v01.2.3", "v1.2.3-rc.1", "v1.2.3\n", "v1.2.3; touch /tmp/unwanted"):
                with self.subTest(tag=tag), contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                    release.parser().parse_args(["--tag", tag, "--build-number", "7", "--arch", "arm64"])
            for number in ("0", "-1", "1.2", "01"):
                with self.subTest(number=number), self.assertRaises(argparse.ArgumentTypeError):
                    builder.build_number(number)
        build.assert_not_called()

    def test_versioned_bundle_preserves_executable_and_minimum_os(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            binary = root / "SessionCanvas"
            binary.write_bytes(b"executable")
            binary.chmod(0o755)
            args = builder.parser().parse_args(["--binary", str(binary), "--version", "2.4.1", "--build-number", "37"])
            with patch.object(builder.subprocess, "run") as run:
                bundle = builder.build_app(args, root=root)
            info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
            self.assertEqual(info["CFBundleShortVersionString"], "2.4.1")
            self.assertEqual(info["CFBundleVersion"], "37")
            self.assertEqual(info["LSMinimumSystemVersion"], "14.0")
            executable = bundle / "Contents/MacOS" / info["CFBundleExecutable"]
            self.assertEqual(executable.read_bytes(), binary.read_bytes())
            self.assertTrue(executable.stat().st_mode & 0o111)
            run.assert_called_once_with(["codesign", "--force", "--sign", "-", str(bundle)], check=True)

    def test_local_build_defaults_remain_available(self):
        args = builder.parser().parse_args([])
        self.assertEqual((args.version, args.build_number, args.sign), ("0.1.0", "1", "-"))

    def test_archive_has_architecture_identity_and_verifiable_checksum(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            bundle = root / "dist/Session Canvas.app"
            bundle.mkdir(parents=True)
            args = release.parser().parse_args(["--tag", "v2.4.1", "--build-number", "37", "--arch", "arm64"])
            def execute(command, **kwargs):
                if command[0] == "ditto":
                    Path(command[-1]).write_bytes(b"archive containing the app")
            with patch.object(builder, "build_app", return_value=bundle) as build, patch.object(release.subprocess, "run", side_effect=execute) as run:
                archive = release.package(args, root=root)
            options = build.call_args.args[0]
            self.assertEqual((options.version, options.build_number), ("2.4.1", "37"))
            self.assertEqual(archive.name, "SessionCanvas-v2.4.1-macos-arm64.zip")
            checksum, filename = archive.with_suffix(".zip.sha256").read_text().strip().split("  ")
            self.assertEqual(filename, archive.name)
            self.assertEqual(checksum, hashlib.sha256(archive.read_bytes()).hexdigest())
            self.assertEqual([call.args[0][0] for call in run.call_args_list], ["lipo", "codesign", "ditto"])

    def test_wrong_architecture_or_bad_signature_prevents_archive(self):
        for failing_command in ("lipo", "codesign"):
            with self.subTest(failing_command=failing_command), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                bundle = root / "dist/Session Canvas.app"
                bundle.mkdir(parents=True)
                args = release.parser().parse_args(["--tag", "v1.0.0", "--build-number", "1", "--arch", "x86_64"])
                def execute(command, **kwargs):
                    if command[0] == failing_command:
                        raise subprocess.CalledProcessError(1, command)
                with patch.object(builder, "build_app", return_value=bundle), patch.object(release.subprocess, "run", side_effect=execute) as run, self.assertRaises(subprocess.CalledProcessError):
                    release.package(args, root=root)
                self.assertNotIn("ditto", [call.args[0][0] for call in run.call_args_list])
                self.assertFalse(list(root.glob("dist/*.zip*")))


if __name__ == "__main__":
    unittest.main()
