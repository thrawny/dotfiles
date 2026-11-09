"""Merge cleanup must honor Git's worktree removal safeguards."""

import os
import subprocess
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "bin/git-worktree-merge"


@pytest.mark.parametrize(
    "local_state",
    [
        "clean",
        "untracked",
        "tracked",
        "locked",
        "ignored",
        "assume-unchanged",
        "skip-worktree",
    ],
)
def test_merge_cleanup_preserves_refused_worktrees(
    tmp_path: Path, local_state: str
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
    git("-C", str(repo), "branch", "topic")
    worktree = tmp_path / "repo-worktrees/topic"
    # A detached worktree lets the command rebase topic in the main checkout.
    git("-C", str(repo), "worktree", "add", "--detach", str(worktree), "topic")
    local_file = worktree / local_state
    if local_state in ("assume-unchanged", "skip-worktree"):
        git("-C", str(worktree), "update-index", f"--{local_state}", "tracked")
        local_file = worktree / "tracked"
    if local_state not in ("clean", "locked"):
        local_file.write_text("Local work\n")
    elif local_state == "locked":
        git("-C", str(repo), "worktree", "lock", str(worktree))
    topic_head = git("-C", str(repo), "rev-parse", "topic")

    result = subprocess.run(
        ["bash", str(SCRIPT), "topic", "--remove"],
        cwd=repo,
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )

    if local_state == "clean":
        assert result.returncode == 0, result.stderr
        assert not worktree.exists()
        assert git("-C", str(repo), "branch", "--list", "topic") == ""
    else:
        assert result.returncode != 0
        assert worktree.is_dir()
        assert git("-C", str(repo), "rev-parse", "refs/heads/topic") == topic_head
        if local_state != "locked":
            assert local_file.read_text() == "Local work\n"
