"""The --git-tracked cache key, driven through the real script and real git."""

import subprocess
import sys
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "bin/run-if-changed"


def test_git_tracked_key_follows_files_outside_the_working_directory(tmp_path):
    repo = tmp_path / "repo"
    (repo / "nix").mkdir(parents=True)
    (repo / "skills/demo").mkdir(parents=True)
    (repo / "nix/flake.nix").write_text("{ }\n")
    (repo / "skills/demo/SKILL.md").write_text("one\n")
    (repo / "skills/demo/link").symlink_to("missing-target")
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    subprocess.run(["git", "-C", str(repo), "add", "."], check=True)
    log = tmp_path / "runs.log"

    def runs() -> int:
        subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--name",
                "eval",
                "--stamp-dir",
                str(tmp_path / "stamps"),
                "--git-tracked",
                "--",
                "sh",
                "-c",
                f"echo run >> '{log}'",
            ],
            cwd=repo / "nix",
            check=True,
            capture_output=True,
        )
        return len(log.read_text().splitlines())

    assert runs() == 1
    assert runs() == 1

    (repo / "skills/demo/SKILL.md").write_text("two\n")
    assert runs() == 2

    # A flake does not see untracked files, so neither does the key.
    (repo / "skills/demo/notes.md").write_text("untracked\n")
    assert runs() == 2

    (repo / "skills/demo/SKILL.md").unlink()
    assert runs() == 3
    assert runs() == 3
