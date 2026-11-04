"""Worktree cleanup must preserve local files even when the branch is merged."""

import os
import subprocess
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "bin/git-cleanup-repo"


@pytest.mark.parametrize(
    "local_change",
    [None, "tracked", "untracked", "ignored", "assume-unchanged", "skip-worktree"],
)
def test_merged_worktree_removal_preserves_local_changes(
    tmp_path: Path, local_change: str | None
) -> None:
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
