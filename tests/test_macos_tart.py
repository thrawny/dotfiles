"""Exercise snapshot boundaries and VM lifecycle without a hypervisor."""

import argparse
import importlib.machinery
import importlib.util
import io
import json
import os
import socket
import subprocess
import sys
import tarfile
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

RUNNER = Path(__file__).resolve().parents[1] / "bin/test-macos-tart"
loader = importlib.machinery.SourceFileLoader("macos_tart", str(RUNNER))
spec = importlib.util.spec_from_loader(loader.name, loader)
tart = importlib.util.module_from_spec(spec)
loader.exec_module(tart)


class RepositoryTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.git("init", "-q")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.repo)

    def write(self, name, content="source"):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def snapshot(self):
        archive = self.root / "source.tar"
        manifest = self.root / "manifest.nul"
        tart.snapshot(self.repo, archive, manifest)
        return archive, manifest


class SnapshotTest(RepositoryTest):
    def test_worktree_content_ignore_rules_and_file_metadata(self):
        self.write("tracked", "old")
        removed = self.write("deleted")
        self.write("ignored-but-tracked")
        self.git("add", ".")
        self.write(".gitignore", "ignored*\n")
        self.write("ignored-untracked")
        self.write("tracked", "uncommitted")
        removed.unlink()
        executable = self.write("untracked space\nand newline", "new")
        executable.chmod(0o755)
        (self.repo / "link").symlink_to("tracked")
        for name in (
            ".env.local",
            "config/codex/config.toml",
            "config/claude/settings.json",
            "config/pi/settings.json",
            "nested/node_modules/file",
            "build/output",
        ):
            self.write(name, "must not transfer")
        self.write("config/codex/config.example.toml", "example")
        archive, manifest = self.snapshot()
        with tarfile.open(archive) as source:
            names = set(source.getnames())
            self.assertEqual(
                names,
                {
                    ".gitignore",
                    "tracked",
                    "untracked space\nand newline",
                    "link",
                    "config/codex/config.example.toml",
                },
            )
            self.assertEqual(source.extractfile("tracked").read(), b"uncommitted")
            self.assertEqual(
                source.getmember("untracked space\nand newline").mode, 0o755
            )
            self.assertTrue(source.getmember("link").issym())
            self.assertEqual(source.getmember("link").linkname, "tracked")
        self.assertEqual(
            set(manifest.read_bytes().split(b"\0")) - {b""},
            {os.fsencode(name) for name in names},
        )

    def test_sensitive_names_are_excluded_without_opening_them(self):
        for name in (
            ".secrets",
            "nested/.secrets.json",
            ".git/config",
            ".envrc",
            "config/claude/CLAUDE.local.md",
            "nested/.aws/credentials",
            "result-output/file",
        ):
            with self.subTest(name=name):
                self.assertTrue(tart.excluded(name))

    def test_symlink_to_excluded_or_external_data_is_rejected(self):
        for destination in (".env.local", "../outside", "/etc/hosts"):
            with self.subTest(destination=destination):
                self.write(".env.local")
                (self.root / "outside").write_text("outside")
                link = self.repo / "innocent"
                link.symlink_to(destination)
                with self.assertRaises(RuntimeError):
                    self.snapshot()
                link.unlink()

    def test_replaced_parent_symlink_is_rejected(self):
        child = self.write("directory/file")
        self.git("add", ".")
        child.unlink()
        child.parent.rmdir()
        target = self.root / "outside"
        target.mkdir()
        (target / "file").write_text("outside")
        (self.repo / "directory").symlink_to(target, target_is_directory=True)
        with self.assertRaises(RuntimeError):
            self.snapshot()


FAKE_TART = r"""
import json, os, pathlib, subprocess, sys, time
root = pathlib.Path(os.environ["FAKE_TART_ROOT"])
args = sys.argv[1:]
with (root / "calls").open("a") as output:
    output.write(json.dumps([args, os.environ.get("TART_NO_AUTO_PRUNE")]) + "\n")
command = args[0]
mode = os.environ.get("FAKE_TART_MODE", "success")
vm = root / "vm"
if command == "--version":
    print("fake-test-version")
elif command == "get":
    sys.exit(0 if vm.exists() else 1)
elif command == "clone":
    vm.touch()
    sys.exit(19 if mode == "clone-failure" else 0)
elif command == "run":
    while not (root / "stopped").exists():
        time.sleep(0.01)
elif command == "stop":
    (root / "stopped").touch()
elif command == "delete":
    vm.unlink()
elif command == "exec":
    if args[-1] == "/usr/bin/true" and mode == "boot-timeout":
        time.sleep(60)
    elif "-i" in args:
        (root / "received.tar").write_bytes(sys.stdin.buffer.read())
    elif "/bin/bash" in args:
        if mode == "guest-timeout":
            time.sleep(60)
        sys.exit(37 if mode == "guest-failure" else 0)
"""


class LifecycleTest(RepositoryTest):
    def setUp(self):
        super().setUp()
        self.write("source", "current worktree")
        fake_bin = self.root / "bin"
        fake_bin.mkdir()
        fake = fake_bin / "tart"
        fake.write_text(f"#!{sys.executable}\n" + FAKE_TART)
        fake.chmod(0o755)
        self.logs = self.root / "logs"
        self.logs.mkdir()
        self.args = argparse.Namespace(
            tart="tart",
            image="test-image@sha256:pin",
            keep=False,
            links_only=False,
            min_free_gib=1,
            cpu=4,
            memory=6144,
            boot_timeout=1,
            test_timeout=1,
        )
        self.patchers = [
            patch.dict(
                os.environ,
                {
                    "PATH": str(fake_bin) + os.pathsep + os.environ["PATH"],
                    "FAKE_TART_ROOT": str(self.root),
                },
            ),
            patch.object(tart.platform, "system", return_value="Darwin"),
            patch.object(tart.platform, "machine", return_value="arm64"),
            patch.object(tart.platform, "mac_ver", return_value=("15.7.4", (), "")),
            redirect_stdout(io.StringIO()),
        ]
        for patcher in self.patchers:
            patcher.__enter__()
            self.addCleanup(patcher.__exit__, None, None, None)

    def run_harness(self, mode="success"):
        with patch.dict(os.environ, {"FAKE_TART_MODE": mode}):
            runner = tart.Harness(self.repo, self.args, self.logs)
            try:
                runner.execute()
            finally:
                self.assertTrue(runner.cleanup())
                if runner.boot:
                    self.assertIsNotNone(runner.boot.poll())
        return runner

    def calls(self):
        return [
            json.loads(line) for line in (self.root / "calls").read_text().splitlines()
        ]

    def test_success_transfers_current_source_and_deletes_only_owned_vm(self):
        runner = self.run_harness()
        # Cleanup can be called again without deleting anything a second time.
        self.assertTrue(runner.cleanup())
        self.assertFalse((self.root / "vm").exists())
        with tarfile.open(self.root / "received.tar") as source:
            self.assertEqual(source.extractfile("source").read(), b"current worktree")
        calls = self.calls()
        self.assertIn([["delete", runner.vm], "1"], calls)
        self.assertEqual(sum(args[0] == "delete" for args, _ in calls), 1)
        self.assertTrue(
            all(env == "1" for args, env in calls if args[0] != "--version")
        )

    def test_guest_failure_preserves_exit_code_and_cleans_up(self):
        with self.assertRaises(subprocess.CalledProcessError) as raised:
            self.run_harness("guest-failure")
        self.assertEqual(raised.exception.returncode, 37)
        self.assertFalse((self.root / "vm").exists())

    def test_partial_clone_is_cleaned_up(self):
        with self.assertRaises(subprocess.CalledProcessError) as raised:
            self.run_harness("clone-failure")
        self.assertEqual(raised.exception.returncode, 19)
        self.assertFalse((self.root / "vm").exists())

    def test_keep_stops_vm_and_passes_links_only(self):
        self.args.keep = self.args.links_only = True
        self.run_harness()
        self.assertTrue((self.root / "vm").exists())
        calls = [args for args, _ in self.calls()]
        self.assertFalse(any(args[0] == "delete" for args in calls))
        self.assertTrue(
            any(args[0] == "exec" and args[-1] == "--links-only" for args in calls)
        )

    def test_keep_removes_only_its_stale_control_socket(self):
        self.args.keep = True
        # Unix socket paths on macOS must be shorter than 104 bytes.
        with tempfile.TemporaryDirectory(dir="/tmp") as storage:
            with patch.dict(os.environ, {"TART_HOME": storage}):
                runner = tart.Harness(self.repo, self.args, self.logs)
                control = Path(storage) / "vms" / runner.vm / "control.sock"
                control.parent.mkdir(parents=True)
                with socket.socket(socket.AF_UNIX) as connection:
                    connection.bind(str(control))
                sibling = Path(storage) / "vms/existing/control.sock"
                sibling.parent.mkdir()
                with socket.socket(socket.AF_UNIX) as connection:
                    connection.bind(str(sibling))
                try:
                    runner.execute()
                finally:
                    self.assertTrue(runner.cleanup())
                self.assertFalse(control.exists())
                self.assertTrue(sibling.exists())

    def test_boot_timeout_is_bounded_and_cleans_up(self):
        with self.assertRaisesRegex(RuntimeError, "startup timed out"):
            self.run_harness("boot-timeout")
        self.assertFalse((self.root / "vm").exists())

    def test_guest_timeout_cleans_up(self):
        with self.assertRaises(subprocess.TimeoutExpired):
            self.run_harness("guest-timeout")
        self.assertFalse((self.root / "vm").exists())

    def test_existing_vm_is_never_owned_or_deleted(self):
        (self.root / "vm").touch()
        with self.assertRaisesRegex(RuntimeError, "already exists"):
            self.run_harness()
        self.assertTrue((self.root / "vm").exists())
        self.assertFalse(
            any(args[0] in ("stop", "delete", "clone") for args, _ in self.calls())
        )

    def test_interrupt_after_clone_cleans_up(self):
        runner = tart.Harness(self.repo, self.args, self.logs)
        real_run = runner.run

        def interrupt(command, **kwargs):
            if command[1] == "set":
                raise KeyboardInterrupt
            return real_run(command, **kwargs)

        with patch.object(runner, "run", side_effect=interrupt):
            with self.assertRaises(KeyboardInterrupt):
                try:
                    runner.execute()
                finally:
                    self.assertTrue(runner.cleanup())
        self.assertFalse((self.root / "vm").exists())

    def test_main_returns_guest_exit_code(self):
        real_mkdtemp = tempfile.mkdtemp

        def temporary_directory(*args, **kwargs):
            if kwargs.get("prefix") == "dotfiles-macos-vm-":
                return str(self.logs)
            return real_mkdtemp(*args, **kwargs)

        with patch.dict(os.environ, {"FAKE_TART_MODE": "guest-failure"}):
            with patch.object(tart, "__file__", str(self.repo / "bin/test-macos-tart")):
                with patch.object(
                    tart.tempfile, "mkdtemp", side_effect=temporary_directory
                ):
                    self.assertEqual(
                        tart.main(["--tart", "tart", "--min-free-gib", "1"]), 37
                    )
        self.assertFalse((self.root / "vm").exists())


class GuestGuardTest(unittest.TestCase):
    def test_guest_script_refuses_direct_host_invocation(self):
        with tempfile.TemporaryDirectory() as temporary:
            result = subprocess.run(
                ["/bin/bash", str(RUNNER.with_name("test-macos-tart-guest"))],
                cwd=temporary,
                env={"HOME": temporary, "PATH": "/usr/bin:/bin"},
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=5,
                check=False,
            )
            self.assertEqual(result.returncode, 1)
            self.assertIn("guest stage failed: prerequisites", result.stdout)
            self.assertEqual(list(Path(temporary).iterdir()), [])


class ProcessCleanupTest(unittest.TestCase):
    def test_stopped_tart_does_not_signal_privileged_helpers(self):
        with subprocess.Popen(
            [sys.executable, "-c", "pass"], start_new_session=True
        ) as process:
            process.wait(timeout=5)
            with patch.object(tart.os, "killpg", side_effect=PermissionError):
                tart.stop_process(process)

    def test_group_permission_error_still_stops_the_owned_process(self):
        with subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(60)"],
            start_new_session=True,
        ) as process:
            try:
                with patch.object(tart.os, "killpg", side_effect=PermissionError):
                    tart.stop_process(process)
                self.assertIsNotNone(process.poll())
            finally:
                if process.poll() is None:
                    process.kill()


if __name__ == "__main__":
    unittest.main()
