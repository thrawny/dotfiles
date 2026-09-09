"""Exercise snapshot boundaries and VM lifecycle without a hypervisor."""

import argparse
import importlib.machinery
import importlib.util
import json
import os
import socket
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path
from typing import Any
from unittest.mock import patch

import pytest

RUNNER = Path(__file__).resolve().parents[1] / "bin/test-macos-tart"
loader = importlib.machinery.SourceFileLoader("macos_tart", str(RUNNER))
spec = importlib.util.spec_from_loader(loader.name, loader)
assert spec is not None
tart = importlib.util.module_from_spec(spec)
loader.exec_module(tart)


class Repository:
    root: Path
    repo: Path

    def __init__(self, root: Path):
        self.root = root.resolve()
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.git("init", "-q")

    def git(self, *args: str):
        return subprocess.check_output(["git", *args], cwd=self.repo)

    def write(self, name: str, content: str = "source"):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def snapshot(self):
        archive = self.root / "source.tar"
        manifest = self.root / "manifest.nul"
        tart.snapshot(self.repo, archive, manifest)
        return archive, manifest


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


class Lifecycle(Repository):
    logs: Path
    args: argparse.Namespace

    def __init__(self, root: Path, monkeypatch: pytest.MonkeyPatch):
        super().__init__(root)
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
        monkeypatch.setenv("PATH", str(fake_bin) + os.pathsep + os.environ["PATH"])
        monkeypatch.setenv("FAKE_TART_ROOT", str(self.root))
        monkeypatch.setattr(tart.platform, "system", lambda: "Darwin")
        monkeypatch.setattr(tart.platform, "machine", lambda: "arm64")
        monkeypatch.setattr(tart.platform, "mac_ver", lambda: ("15.7.4", (), ""))

    def run_harness(self, mode: str = "success"):
        with patch.dict(os.environ, {"FAKE_TART_MODE": mode}):
            runner = tart.Harness(self.repo, self.args, self.logs)
            try:
                runner.execute()
            finally:
                assert runner.cleanup()
                if runner.boot:
                    assert runner.boot.poll() is not None
        return runner

    def calls(self):
        return [
            json.loads(line) for line in (self.root / "calls").read_text().splitlines()
        ]


@pytest.fixture
def repository(tmp_path: Path) -> Repository:
    return Repository(tmp_path)


@pytest.fixture
def lifecycle(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Lifecycle:
    return Lifecycle(tmp_path, monkeypatch)


def test_worktree_content_ignore_rules_and_file_metadata(repository: Repository):
    repository.write("tracked", "old")
    removed = repository.write("deleted")
    repository.write("ignored-but-tracked")
    repository.git("add", ".")
    repository.write(".gitignore", "ignored*\n")
    repository.write("ignored-untracked")
    repository.write("tracked", "uncommitted")
    removed.unlink()
    executable = repository.write("untracked space\nand newline", "new")
    executable.chmod(0o755)
    (repository.repo / "link").symlink_to("tracked")
    for name in (
        ".env.local",
        "config/codex/config.toml",
        "config/claude/settings.json",
        "config/pi/settings.json",
        "nested/node_modules/file",
        "build/output",
    ):
        repository.write(name, "must not transfer")
    repository.write("config/codex/config.example.toml", "example")
    archive, manifest = repository.snapshot()
    with tarfile.open(archive) as source:
        names = set(source.getnames())
        assert names == {
            ".gitignore",
            "tracked",
            "untracked space\nand newline",
            "link",
            "config/codex/config.example.toml",
        }
        tracked = source.extractfile("tracked")
        assert tracked is not None
        assert tracked.read() == b"uncommitted"
        assert source.getmember("untracked space\nand newline").mode == 0o755
        assert source.getmember("link").issym()
        assert source.getmember("link").linkname == "tracked"
    assert set(manifest.read_bytes().split(b"\x00")) - {b""} == {
        os.fsencode(name) for name in names
    }


@pytest.mark.parametrize(
    "name",
    [
        ".secrets",
        "nested/.secrets.json",
        ".git/config",
        ".envrc",
        "config/claude/CLAUDE.local.md",
        "nested/.aws/credentials",
        "result-output/file",
    ],
)
def test_sensitive_names_are_excluded_without_opening_them(name: str):
    assert tart.excluded(name)


@pytest.mark.parametrize("destination", [".env.local", "../outside", "/etc/hosts"])
def test_symlink_to_excluded_or_external_data_is_rejected(
    repository: Repository, destination: str
):
    repository.write(".env.local")
    (repository.root / "outside").write_text("outside")
    (repository.repo / "innocent").symlink_to(destination)
    with pytest.raises(RuntimeError):
        repository.snapshot()


def test_replaced_parent_symlink_is_rejected(repository: Repository):
    child = repository.write("directory/file")
    repository.git("add", ".")
    child.unlink()
    child.parent.rmdir()
    target = repository.root / "outside"
    target.mkdir()
    (target / "file").write_text("outside")
    (repository.repo / "directory").symlink_to(target, target_is_directory=True)
    with pytest.raises(RuntimeError):
        repository.snapshot()


def test_success_transfers_current_source_and_deletes_only_owned_vm(
    lifecycle: Lifecycle,
):
    runner = lifecycle.run_harness()
    # Cleanup can be called again without deleting anything a second time.
    assert runner.cleanup()
    assert not (lifecycle.root / "vm").exists()
    with tarfile.open(lifecycle.root / "received.tar") as source:
        transferred = source.extractfile("source")
        assert transferred is not None
        assert transferred.read() == b"current worktree"
    calls = lifecycle.calls()
    assert [["delete", runner.vm], "1"] in calls
    assert sum((args[0] == "delete" for args, _ in calls)) == 1
    assert all((env == "1" for args, env in calls if args[0] != "--version"))


def test_guest_failure_preserves_exit_code_and_cleans_up(lifecycle: Lifecycle):
    with pytest.raises(subprocess.CalledProcessError) as raised:
        lifecycle.run_harness("guest-failure")
    assert raised.value.returncode == 37
    assert not (lifecycle.root / "vm").exists()


def test_partial_clone_is_cleaned_up(lifecycle: Lifecycle):
    with pytest.raises(subprocess.CalledProcessError) as raised:
        lifecycle.run_harness("clone-failure")
    assert raised.value.returncode == 19
    assert not (lifecycle.root / "vm").exists()


def test_keep_stops_vm_and_passes_links_only(lifecycle: Lifecycle):
    lifecycle.args.keep = lifecycle.args.links_only = True
    lifecycle.run_harness()
    assert (lifecycle.root / "vm").exists()
    calls = [args for args, _ in lifecycle.calls()]
    assert not any((args[0] == "delete" for args in calls))
    assert any((args[0] == "exec" and args[-1] == "--links-only" for args in calls))


def test_keep_removes_only_its_stale_control_socket(lifecycle: Lifecycle):
    lifecycle.args.keep = True
    # Unix socket paths on macOS must be shorter than 104 bytes.
    with tempfile.TemporaryDirectory(dir="/tmp") as storage:
        with patch.dict(os.environ, {"TART_HOME": storage}):
            runner = tart.Harness(lifecycle.repo, lifecycle.args, lifecycle.logs)
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
                assert runner.cleanup()
            assert not control.exists()
            assert sibling.exists()


def test_boot_timeout_is_bounded_and_cleans_up(lifecycle: Lifecycle):
    with pytest.raises(RuntimeError, match="startup timed out"):
        lifecycle.run_harness("boot-timeout")
    assert not (lifecycle.root / "vm").exists()


def test_guest_timeout_cleans_up(lifecycle: Lifecycle):
    with pytest.raises(subprocess.TimeoutExpired):
        lifecycle.run_harness("guest-timeout")
    assert not (lifecycle.root / "vm").exists()


def test_existing_vm_is_never_owned_or_deleted(lifecycle: Lifecycle):
    (lifecycle.root / "vm").touch()
    with pytest.raises(RuntimeError, match="already exists"):
        lifecycle.run_harness()
    assert (lifecycle.root / "vm").exists()
    assert not any(
        (args[0] in ("stop", "delete", "clone") for args, _ in lifecycle.calls())
    )


def test_interrupt_after_clone_cleans_up(lifecycle: Lifecycle):
    runner = tart.Harness(lifecycle.repo, lifecycle.args, lifecycle.logs)
    real_run = runner.run

    def interrupt(command: list[str], **kwargs: Any):
        if command[1] == "set":
            raise KeyboardInterrupt
        return real_run(command, **kwargs)

    with patch.object(runner, "run", side_effect=interrupt):
        with pytest.raises(KeyboardInterrupt):
            try:
                runner.execute()
            finally:
                assert runner.cleanup()
    assert not (lifecycle.root / "vm").exists()


def test_main_returns_guest_exit_code(lifecycle: Lifecycle):
    real_mkdtemp = tempfile.mkdtemp

    def temporary_directory(
        suffix: str | None = None, prefix: str | None = None, dir: str | None = None
    ):
        if prefix == "dotfiles-macos-vm-":
            return str(lifecycle.logs)
        return real_mkdtemp(suffix=suffix, prefix=prefix, dir=dir)

    with patch.dict(os.environ, {"FAKE_TART_MODE": "guest-failure"}):
        with patch.object(
            tart, "__file__", str(lifecycle.repo / "bin/test-macos-tart")
        ):
            with patch.object(
                tart.tempfile, "mkdtemp", side_effect=temporary_directory
            ):
                assert tart.main(["--tart", "tart", "--min-free-gib", "1"]) == 37
    assert not (lifecycle.root / "vm").exists()


def test_guest_script_refuses_direct_host_invocation(tmp_path: Path):
    result = subprocess.run(
        ["bash", str(RUNNER.with_name("test-macos-tart-guest"))],
        cwd=tmp_path,
        env={"HOME": str(tmp_path), "PATH": os.environ["PATH"]},
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=5,
        check=False,
    )
    assert result.returncode == 1
    assert "guest stage failed: prerequisites" in result.stdout
    assert list(tmp_path.iterdir()) == []


def test_stopped_tart_does_not_signal_privileged_helpers():
    with subprocess.Popen(
        [sys.executable, "-c", "pass"], start_new_session=True
    ) as process:
        process.wait(timeout=5)
        with patch.object(tart.os, "killpg", side_effect=PermissionError):
            tart.stop_process(process)


def test_group_permission_error_still_stops_the_owned_process():
    with subprocess.Popen(
        [sys.executable, "-c", "import time; time.sleep(60)"],
        start_new_session=True,
    ) as process:
        try:
            with patch.object(tart.os, "killpg", side_effect=PermissionError):
                tart.stop_process(process)
            assert process.poll() is not None
        finally:
            if process.poll() is None:
                process.kill()
