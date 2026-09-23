"""Project picker dispatch and Herdr workspace reuse."""

import json
import os
import subprocess
from collections.abc import Callable
from pathlib import Path

import pytest

Picker = tuple[
    Callable[..., subprocess.CompletedProcess[str]],
    dict[str, str],
    Path,
    Path,
    Callable[[str, str], None],
]

SCRIPT = Path(__file__).resolve().parents[1] / "bin/project-picker"


@pytest.fixture
def picker(tmp_path: Path) -> Picker:
    tools = tmp_path / "tools"
    tools.mkdir()
    repo = tmp_path / "repo with spaces"
    repo.mkdir()
    log = tmp_path / "calls"

    def stub(name: str, body: str):
        executable = tools / name
        executable.write_text("#!/usr/bin/env bash\n" + body)
        executable.chmod(0o755)

    stub("zoxide", "exit 0\n")
    stub("fzf", 'printf "\\n%s\\n" "$PICK"\n')
    for name in ("niri-project", "hyprland-project"):
        stub(name, 'printf "%s\\n" "$0" "$@" > "$LOG"\n')
    stub(
        "herdr",
        'case "$1 $2" in\n'
        + '"workspace list") echo \'{"result":{"workspaces":[{"workspace_id":"w9"}]}}\' ;;\n'
        + '"pane list") printf "%s" "$PANES" ;;\n'
        + '*) printf "%s\\n" "$@" > "$LOG" ;;\n'
        + "esac\n",
    )
    env = {
        **os.environ,
        "HOME": str(tmp_path),
        "PATH": f"{tools}:{os.environ['PATH']}",
        "PICK": str(repo),
        "LOG": str(log),
        "HERDR_BIN_PATH": str(tools / "herdr"),
        "PANES": '{"result":{"panes":[]}}',
    }

    def run(*args: str, stdin: str = ""):
        return subprocess.run(
            [str(SCRIPT), *args],
            env=env,
            input=stdin,
            capture_output=True,
            text=True,
            check=False,
        )

    return run, env, log, repo, stub


@pytest.mark.parametrize(
    "flag,command", [("--niri", "niri-project"), ("--hypr", "hyprland-project")]
)
def test_desktop_dispatch(picker: Picker, flag: str, command: str):
    run, _, log, repo, _ = picker
    assert run(flag).returncode == 0
    lines = log.read_text().splitlines()
    assert lines[0].endswith(command)
    assert lines[1:] == ["--terminals", "1", str(repo)]


def test_herdr_create(picker: Picker):
    run, _, log, repo, _ = picker
    assert run("--herdr").returncode == 0
    assert log.read_text().splitlines() == [
        "workspace",
        "create",
        "--cwd",
        str(repo),
        "--label",
        repo.name,
        "--focus",
    ]


def test_herdr_worktree_from_remote_default(picker: Picker, tmp_path: Path):
    run, env, log, repo, stub = picker
    fetches = tmp_path / "fetches"
    stub(
        "git",
        'case "$3 $4" in\n'
        + '"symbolic-ref --quiet") echo origin/trunk ;;\n'
        + '"fetch --quiet") printf "%s\\n" "$@" > "$FETCHES" ;;\n'
        + "*) exit 1 ;;\n"
        + "esac\n",
    )
    stub("fzf", 'printf "ctrl-g\\n%s\\n" "$PICK"\n')
    env["FETCHES"] = str(fetches)
    assert run("--herdr", stdin="feature\n").returncode == 0
    assert log.read_text().splitlines() == [
        "worktree",
        "create",
        "--cwd",
        str(repo),
        "--branch",
        "feature",
        "--base",
        "origin/trunk",
        "--focus",
    ]
    assert fetches.read_text().splitlines() == [
        "-C",
        str(repo),
        "fetch",
        "--quiet",
        "origin",
        "trunk",
    ]


def test_herdr_worktree_without_remote(picker: Picker):
    run, _, log, _, stub = picker
    stub("git", "exit 1\n")
    stub("fzf", 'printf "ctrl-g\\n%s\\n" "$PICK"\n')
    assert run("--herdr", stdin="feature\n").returncode == 0
    assert log.read_text().splitlines()[-2:] == ["HEAD", "--focus"]


def test_herdr_worktree_needs_a_branch(picker: Picker):
    run, _, log, _, stub = picker
    stub("fzf", 'printf "ctrl-g\\n%s\\n" "$PICK"\n')
    assert run("--herdr", stdin="\n").returncode == 0
    assert not log.exists()


def test_herdr_reuse(picker: Picker):
    run, env, log, repo, _ = picker
    env["PANES"] = json.dumps({"result": {"panes": [{"cwd": str(repo)}]}})
    assert run("--herdr").returncode == 0
    assert log.read_text().splitlines() == ["workspace", "focus", "w9"]


@pytest.mark.parametrize("args", [[], ["--invalid"], ["--niri", "--herdr"]])
def test_requires_one_backend(picker: Picker, args: list[str]):
    run, _, log, _, _ = picker
    assert run(*args).returncode == 2
    assert not log.exists()


def test_cancel(picker: Picker):
    run, _, log, _, stub = picker
    stub("fzf", "exit 130\n")
    assert run("--herdr").returncode == 0
    assert not log.exists()


@pytest.mark.parametrize("backend", ["niri", "hypr"])
def test_desktop_failure_notifies(picker: Picker, backend: str):
    run, _, log, _, stub = picker
    stub(
        f"{backend}land-project" if backend == "hypr" else "niri-project",
        'echo "compositor rejected request" >&2; exit 7\n',
    )
    stub("busctl", 'printf "%s\\n" "$@" > "$LOG"\n')
    result = run(f"--{backend}")
    assert result.returncode == 7
    assert "compositor rejected request" in result.stderr
    notification = log.read_text()
    assert "Could not open project" in notification
    assert "compositor rejected request" in notification
