"""Reviewer selection runs only the requested tools, without model invocations."""

import os
import subprocess
from pathlib import Path

import pytest

LAUNCHER = (
    Path(__file__).resolve().parents[1] / "skills/gauntlet/scripts/gauntlet-review"
)


@pytest.mark.parametrize(
    ("configured", "arguments", "expected"),
    [
        (None, [], {"codex"}),
        ("", [], {"codex"}),
        ("claude", [], {"claude"}),
        ("claude,codex", [], {"claude", "codex"}),
        ("codex", ["--reviewers", "claude"], {"claude"}),
        ("claude,codex", ["--reviewers", "codex"], {"codex"}),
        ("invalid", [], set()),
    ],
)
def test_reviewer_selection(
    tmp_path: Path,
    configured: str | None,
    arguments: list[str],
    expected: set[str],
) -> None:
    repository = tmp_path / "repository"
    repository.mkdir()
    subprocess.run(["git", "init", "-q", str(repository)], check=True)
    tools = tmp_path / "tools"
    tools.mkdir()
    calls = tmp_path / "calls"
    calls.mkdir()
    for reviewer in ("claude", "codex"):
        stub = tools / reviewer
        stub.write_text(
            "#!/bin/sh\n"
            f'touch "$CALLS/{reviewer}"\n'
            'while [ "$#" -gt 0 ]; do\n'
            '  if [ "$1" = "-o" ]; then shift; printf "No findings\\n" > "$1"; fi\n'
            "  shift\n"
            "done\n"
            'printf "No findings\\n"\n'
        )
        stub.chmod(0o755)
    environment = {
        key: value
        for key, value in os.environ.items()
        if not key.startswith("GAUNTLET_")
    }
    environment.update(
        PATH=f"{tools}:{environment['PATH']}",
        CALLS=str(calls),
        GAUNTLET_STATE_DIR=str(tmp_path / "state"),
    )
    if configured is not None:
        environment["GAUNTLET_REVIEWERS"] = configured
    result = subprocess.run(
        ["bash", str(LAUNCHER), "--uncommitted", *arguments, "Fixture review"],
        cwd=repository,
        env=environment,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert (result.returncode == 0) is bool(expected), result.stderr
    assert {entry.name for entry in calls.iterdir()} == expected
