"""Private skill activation uses local Git repos, never real credentials or networks."""

from __future__ import annotations

import fcntl
import json
import os
import runpy
import subprocess
import sys
from pathlib import Path
from typing import final

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "bin/private-skills-sync"


@final
class Skills:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.remote = root / "remote"
        self.checkout = root / "private skills"
        self.targets = [root / agent / "skills" for agent in ("claude", "codex", "pi")]
        self.config = root / "config.json"
        self.env = os.environ.copy()
        self.env.update(
            HOME=str(root),
            GIT_CONFIG_GLOBAL=os.devnull,
            GIT_CONFIG_NOSYSTEM="1",
            GIT_AUTHOR_NAME="Test",
            GIT_AUTHOR_EMAIL="test@example.com",
            GIT_COMMITTER_NAME="Test",
            GIT_COMMITTER_EMAIL="test@example.com",
        )
        for name in ("SANDBOX", "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
            self.env.pop(name, None)
        self.remote.mkdir()
        self.git(self.remote, "init", "-b", "main")
        self.skill("fleet")
        self.commit(self.remote)
        self.configure()

    def git(self, directory: Path, *args: str) -> str:
        return subprocess.run(
            ["git", "-C", str(directory), *args],
            env=self.env,
            text=True,
            capture_output=True,
            check=True,
        ).stdout.strip()

    def skill(self, name: str) -> None:
        directory = self.remote / name
        directory.mkdir(parents=True)
        (directory / "SKILL.md").write_text(
            f"---\nname: {name}\ndescription: Test\n---\n"
        )

    def commit(self, directory: Path) -> None:
        self.git(directory, "add", ".")
        self.git(directory, "commit", "-m", "Test changes")

    def configure(self, reserved: tuple[str, ...] = ()) -> None:
        self.config.write_text(
            json.dumps(
                {
                    "repository": str(self.remote),
                    "checkout": str(self.checkout),
                    "targets": {str(target): list(reserved) for target in self.targets},
                }
            )
        )

    def run(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--config", str(self.config), *args],
            env=self.env,
            text=True,
            capture_output=True,
            check=False,
        )


@pytest.fixture
def skills(tmp_path: Path) -> Skills:
    return Skills(tmp_path)


def test_clone_links_all_agents_and_is_repeatable(skills: Skills) -> None:
    for _ in range(2):
        result = skills.run()
        assert result.returncode == 0, result.stderr
        for target in skills.targets:
            assert (target / "fleet").readlink() == skills.checkout / "fleet"
    assert skills.checkout.stat().st_mode & 0o077 == 0


def test_updates_additions_removals_and_ignores_non_skills(skills: Skills) -> None:
    assert skills.run().returncode == 0
    skills.git(skills.remote, "rm", "fleet/SKILL.md")
    skills.skill("servers")
    (skills.remote / "notes").mkdir()
    (skills.remote / "notes/inventory.md").write_text("Not a skill")
    (skills.remote / "alias").symlink_to("servers", target_is_directory=True)
    skills.commit(skills.remote)
    assert skills.run().returncode == 0
    for target in skills.targets:
        assert not (target / "fleet").is_symlink()
        assert (target / "servers").is_symlink()
        assert not (target / "notes").exists()
        assert not (target / "alias").exists()


def test_offline_preserves_checkout_and_refreshes_links(skills: Skills) -> None:
    assert skills.run().returncode == 0
    skills.remote.rename(skills.root / "offline")
    (skills.targets[0] / "fleet").unlink()
    result = skills.run()
    assert result.returncode == 1
    assert (skills.targets[0] / "fleet").is_symlink()
    assert (skills.checkout / "fleet/SKILL.md").exists()
    assert skills.run("--link-only").returncode == 0


def test_failed_clone_leaves_no_checkout(skills: Skills) -> None:
    skills.remote.rename(skills.root / "offline")
    assert skills.run().returncode == 1
    assert not skills.checkout.exists()
    assert not list(skills.root.glob(".private-skills-*"))
    assert all(not target.exists() for target in skills.targets)


def test_dirty_checkout_is_not_modified(skills: Skills) -> None:
    assert skills.run().returncode == 0
    inventory = skills.checkout / "fleet/inventory.md"
    inventory.write_text("Local draft")
    skills.skill("new")
    skills.commit(skills.remote)
    result = skills.run()
    assert result.returncode == 1
    assert "local changes" in result.stderr
    assert inventory.read_text() == "Local draft"
    assert not (skills.checkout / "new").exists()


def test_diverged_history_is_not_reset_or_rebased(skills: Skills) -> None:
    assert skills.run().returncode == 0
    (skills.checkout / "local").write_text("Local commit")
    skills.commit(skills.checkout)
    before = skills.git(skills.checkout, "rev-parse", "HEAD")
    skills.skill("new")
    skills.commit(skills.remote)
    assert skills.run().returncode == 1
    assert skills.git(skills.checkout, "rev-parse", "HEAD") == before
    assert not (skills.checkout / "new").exists()


def test_non_main_branch_is_not_updated(skills: Skills) -> None:
    assert skills.run().returncode == 0
    skills.git(skills.checkout, "checkout", "-b", "draft")
    result = skills.run()
    assert result.returncode == 1
    assert "not on main" in result.stderr


def test_existing_files_and_foreign_links_are_preserved(skills: Skills) -> None:
    for target in skills.targets:
        target.mkdir(parents=True)
    (skills.targets[0] / "fleet").write_text("Keep me")
    (skills.targets[1] / "fleet").symlink_to(skills.root / "missing")
    (skills.targets[2] / "fleet").mkdir()
    result = skills.run()
    assert result.returncode == 1
    assert (skills.targets[0] / "fleet").read_text() == "Keep me"
    assert (skills.targets[1] / "fleet").readlink() == skills.root / "missing"
    assert not (skills.targets[2] / "fleet").is_symlink()


def test_reserved_public_names_are_not_linked_even_when_absent(skills: Skills) -> None:
    skills.configure(reserved=("fleet",))
    assert skills.run().returncode == 1
    assert all(not (target / "fleet").exists() for target in skills.targets)


def test_only_our_stale_links_are_removed(skills: Skills) -> None:
    assert skills.run().returncode == 0
    for target in skills.targets:
        (target / "unrelated").symlink_to(skills.checkout / "elsewhere")
        (target / "external").symlink_to(skills.root / "missing")
    skills.git(skills.remote, "rm", "fleet/SKILL.md")
    skills.commit(skills.remote)
    assert skills.run().returncode == 0
    for target in skills.targets:
        assert not (target / "fleet").is_symlink()
        assert (target / "unrelated").is_symlink()
        assert (target / "external").is_symlink()


def test_wrong_origin_is_not_used(skills: Skills) -> None:
    assert skills.run().returncode == 0
    skills.git(skills.checkout, "remote", "set-url", "origin", "/wrong/repo")
    (skills.targets[0] / "fleet").unlink()
    result = skills.run()
    assert result.returncode == 1
    assert "does not match" in result.stderr
    assert not (skills.targets[0] / "fleet").is_symlink()


def test_unmanaged_directory_and_symlink_are_not_used(skills: Skills) -> None:
    skills.checkout.mkdir()
    assert skills.run().returncode == 1
    skills.checkout.rmdir()
    skills.checkout.symlink_to(skills.remote, target_is_directory=True)
    assert skills.run().returncode == 1
    assert all(not target.exists() for target in skills.targets)


def test_dry_run_and_sandbox_do_not_write_or_clone(skills: Skills) -> None:
    assert skills.run("--dry-run").returncode == 0
    assert not skills.checkout.exists()
    assert not (skills.root / ".private skills.lock").exists()
    skills.env["SANDBOX"] = "1"
    result = skills.run()
    assert result.returncode == 1
    assert "sandboxes" in result.stderr
    assert not skills.checkout.exists()


def test_missing_checkout_does_not_prune_links(skills: Skills) -> None:
    assert skills.run().returncode == 0
    skills.checkout.rename(skills.root / "temporarily-missing")
    assert skills.run("--link-only").returncode == 1
    assert all((target / "fleet").is_symlink() for target in skills.targets)


def test_concurrent_sync_does_not_touch_checkout(skills: Skills) -> None:
    with (skills.root / ".private skills.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        result = skills.run()
    assert result.returncode == 1
    assert "another sync" in result.stderr
    assert not skills.checkout.exists()


def test_git_timeout_is_bounded(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    fake_git = tmp_path / "git"
    fake_git.write_text("#!/bin/sh\nsleep 60\n")
    fake_git.chmod(0o755)
    monkeypatch.setenv("PATH", f"{tmp_path}:{os.environ['PATH']}")
    module = runpy.run_path(str(SCRIPT))
    with pytest.raises(RuntimeError, match="timed out"):
        module["git"]("fetch", timeout=1)


def test_disabled_host_does_nothing(skills: Skills) -> None:
    skills.config.unlink()
    result = skills.run()
    assert result.returncode == 1
    assert "not enabled" in result.stderr
    assert not skills.checkout.exists()
