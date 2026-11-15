"""Re-entering a worktree must keep its own local files."""

import os
import subprocess
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "bin/git-worktree-new"


def test_rerun_seeds_missing_files_and_keeps_existing_ones(tmp_path: Path) -> None:
    environment = {
        **os.environ,
        "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_AUTHOR_NAME": "Test",
        "GIT_AUTHOR_EMAIL": "test@example.com",
        "GIT_COMMITTER_NAME": "Test",
        "GIT_COMMITTER_EMAIL": "test@example.com",
        "NIRI_SOCKET": "",
    }
    for name in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
        environment.pop(name, None)
    repo = tmp_path / "repo"
    repo.mkdir()

    def run(*args: str) -> None:
        subprocess.run(args, cwd=repo, env=environment, capture_output=True, check=True)

    run("git", "init", "--initial-branch=main")
    run("git", "commit", "--allow-empty", "-m", "Initial commit")
    (repo / ".claude").mkdir()
    (repo / "sub").mkdir()
    (repo / ".env").write_text("root\n")
    (repo / "sub/.envrc").write_text("root\n")
    (repo / ".claude/settings.local.json").write_text('{"source": "root"}\n')

    run(str(SCRIPT), "topic")
    worktree = tmp_path / "repo-worktrees/topic"
    assert (worktree / "sub/.envrc").read_text() == "root\n"

    (worktree / ".env").write_text("edited in worktree\n")
    (worktree / ".claude/settings.local.json").write_text('{"source": "worktree"}\n')
    (repo / ".env.local").write_text("added later\n")
    run(str(SCRIPT), "topic")

    assert (worktree / ".env").read_text() == "edited in worktree\n"
    assert (worktree / ".claude/settings.local.json").read_text() == (
        '{"source": "worktree"}\n'
    )
    assert (worktree / ".env.local").read_text() == "added later\n"
