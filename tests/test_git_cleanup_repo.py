"""Worktree cleanup must preserve local files even when the branch is merged."""

import os
import subprocess
from collections.abc import Callable
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "bin/git-cleanup-repo"
Repository = tuple[Path, dict[str, str], Callable[..., str]]


@pytest.fixture
def repository(tmp_path: Path) -> Repository:
    environment = {
        **os.environ,
        "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_AUTHOR_NAME": "Test",
        "GIT_AUTHOR_EMAIL": "test@example.com",
        "GIT_COMMITTER_NAME": "Test",
        "GIT_COMMITTER_EMAIL": "test@example.com",
    }
    for name in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
        environment.pop(name, None)

    def git(*args: str) -> str:
        return subprocess.run(
            ["git", *args],
            cwd=tmp_path,
            env=environment,
            text=True,
            capture_output=True,
            check=True,
        ).stdout.strip()

    git("init", "--bare", "--initial-branch=main", "remote")
    git("clone", "remote", "repo")
    repo = tmp_path / "repo"
    (repo / "tracked").write_text("Committed content\n")
    (repo / ".gitignore").write_text("ignored\n")
    git("-C", str(repo), "add", "tracked", ".gitignore")
    git("-C", str(repo), "commit", "-m", "Initial commit")
    git("-C", str(repo), "push", "-u", "origin", "main")
    git("-C", str(repo), "remote", "set-head", "origin", "--auto")
    return repo, environment, git


@pytest.mark.parametrize(
    "local_change",
    [None, "tracked", "untracked", "ignored", "assume-unchanged", "skip-worktree"],
)
def test_merged_worktree_removal_preserves_local_changes(
    tmp_path: Path, repository: Repository, local_change: str | None
) -> None:
    repo, environment, git = repository
    worktree = tmp_path / "merged worktree"
    git("-C", str(repo), "worktree", "add", "-b", "topic", str(worktree))
    local_file = worktree / (local_change or "tracked")
    if local_change in ("assume-unchanged", "skip-worktree"):
        git("-C", str(worktree), "update-index", f"--{local_change}", "tracked")
        local_file = worktree / "tracked"
    if local_change:
        local_file.write_text("Local work\n")

    result = subprocess.run(
        ["bash", str(SCRIPT)],
        cwd=repo,
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )

    if local_change:
        assert local_file.read_text() == "Local work\n"
        assert git("-C", str(worktree), "branch", "--show-current") == "topic"
        assert result.returncode != 0
    else:
        assert result.returncode == 0, result.stderr
        assert not worktree.exists()
        assert git("-C", str(repo), "branch", "--list", "topic") == ""


@pytest.mark.parametrize("failure", ["stash", "checkout", "fetch", "missing-upstream"])
def test_failed_preparation_preserves_worktree_and_branch(
    tmp_path: Path, repository: Repository, failure: str
) -> None:
    repo, environment, git = repository
    worktree = tmp_path / "topic"
    git("-C", str(repo), "worktree", "add", "-b", "topic", str(worktree))
    if failure == "stash":
        (repo / "tracked").write_text("Unstashed work\n")
        (repo / ".git/index.lock").touch()
    elif failure == "checkout":
        git("-C", str(repo), "checkout", "-b", "caller")
        git("-C", str(repo), "worktree", "add", str(tmp_path / "main"), "main")
    elif failure == "fetch":
        (tmp_path / "remote").rename(tmp_path / "unavailable-remote")
    else:
        (worktree / "unique").write_text("Unmerged work\n")
        git("-C", str(worktree), "add", "unique")
        git("-C", str(worktree), "commit", "-m", "Unmerged work")
        git("-C", str(tmp_path / "remote"), "branch", "-m", "main", "trunk")
    topic_head = git("-C", str(repo), "rev-parse", "topic")

    result = subprocess.run(
        ["bash", str(SCRIPT)],
        cwd=repo,
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode != 0
    assert worktree.is_dir()
    assert git("-C", str(repo), "rev-parse", "refs/heads/topic") == topic_head
    if failure == "stash":
        assert (repo / "tracked").read_text() == "Unstashed work\n"
    if failure == "missing-upstream":
        assert (worktree / "unique").read_text() == "Unmerged work\n"
