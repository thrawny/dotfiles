"""Finding the nearest Neovim and opening files in it, against real headless Neovims."""

import json
import os
import shutil
import subprocess
import tempfile
import time
from collections.abc import Iterator
from pathlib import Path
from typing import final

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "bin/nvim-here"

pytestmark = pytest.mark.skipif(shutil.which("nvim") is None, reason="needs nvim")


def pane(pane_id: str, tab: str) -> dict[str, str]:
    return {"pane_id": pane_id, "tab_id": tab, "workspace_id": tab.partition(":")[0]}


@final
class World:
    def __init__(self, root: Path, tools: Path) -> None:
        self.root = root
        self.project = root / "project"
        self.project.mkdir()
        self.log = root / "herdr-calls"
        self.nvims: list[subprocess.Popen[bytes]] = []
        self.env = {
            **os.environ,
            "PATH": f"{tools}:{os.environ['PATH']}",
            "HERDR_BIN_PATH": str(tools / "herdr"),
            "HERDR_PANE_ID": "w1:p1",
            # Unix socket paths are short, too short for pytest's tmp_path on
            # macOS, so Neovim's run directory goes under a short root.
            "TMPDIR": str(root),
            "LOG": str(self.log),
            "PANES": "[]",
        }
        for key in ("XDG_RUNTIME_DIR", "NVIM", "HERDR_TAB_ID", "HERDR_WORKSPACE_ID"):
            self.env.pop(key, None)

    def panes(self, *panes: dict[str, str]) -> None:
        self.env["PANES"] = json.dumps({"result": {"panes": list(panes)}})

    def file(self, name: str, lines: int = 50) -> Path:
        path = self.project / name
        path.write_text("".join(f"line {n}\n" for n in range(1, lines + 1)))
        return path

    def start_nvim(self, pane_id: str) -> str:
        """Start a Neovim as if it ran in a Herdr pane and return its socket."""
        before = set(self.sockets())
        process = subprocess.Popen(
            ["nvim", "--clean", "--headless", "-n"],
            cwd=self.project,
            env={**self.env, "HERDR_PANE_ID": pane_id},
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        self.nvims.append(process)
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if new := set(self.sockets()) - before:
                return new.pop()
            time.sleep(0.05)
        raise AssertionError("Neovim did not open its socket")

    def sockets(self) -> list[str]:
        return [str(path) for path in self.root.glob("nvim.*/*/nvim.*.0")]

    def where(self, socket: str) -> tuple[str, int, int]:
        out = subprocess.run(
            [
                "nvim",
                "--clean",
                "--headless",
                "--server",
                socket,
                "--remote-expr",
                'json_encode([expand("%:p"), line("."), col(".")])',
            ],
            capture_output=True,
            text=True,
            stdin=subprocess.DEVNULL,
            check=True,
        ).stdout
        path, line, col = json.loads(out)
        return (str(Path(path).resolve()) if path else ""), line, col

    def run(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(SCRIPT), *args],
            cwd=self.project,
            env=self.env,
            capture_output=True,
            text=True,
            stdin=subprocess.DEVNULL,
            check=False,
        )

    def calls(self) -> list[str]:
        return self.log.read_text().splitlines() if self.log.exists() else []


@pytest.fixture
def world(tmp_path: Path) -> Iterator[World]:
    tools = tmp_path / "tools"
    tools.mkdir()
    herdr = tools / "herdr"
    herdr.write_text(
        "#!/usr/bin/env bash\n"
        + 'printf "%s\\n" "$*" >> "$LOG"\n'
        + 'case "$1 $2" in\n'
        + '"pane list") printf "%s" "$PANES" ;;\n'
        + '"pane split") printf \'{"result":{"pane":{"pane_id":"w1:p9"}}}\' ;;\n'
        + "*) printf '{}' ;;\n"
        + "esac\n"
    )
    herdr.chmod(0o755)
    root = Path(tempfile.mkdtemp(prefix="nvh", dir="/tmp"))
    world = World(root, tools)
    try:
        yield world
    finally:
        for process in world.nvims:
            process.terminate()
            process.wait(timeout=5)
        shutil.rmtree(root, ignore_errors=True)


def resolved(path: Path) -> str:
    return str(path.resolve())


def test_opens_at_line_in_the_neovim_in_the_same_tab(world: World):
    world.panes(pane("w1:p1", "w1:t1"), pane("w1:p2", "w1:t2"), pane("w1:p3", "w1:t1"))
    elsewhere = world.start_nvim("w1:p2")
    beside = world.start_nvim("w1:p3")
    file = world.file("main.go")

    result = world.run("open", "main.go:12")

    assert result.returncode == 0, result.stderr
    assert "pane w1:p3 (same tab)" in result.stdout
    assert world.where(beside) == (resolved(file), 12, 1)
    assert world.where(elsewhere)[0] == ""


def test_falls_back_to_a_neovim_in_the_same_workspace(world: World):
    world.panes(pane("w1:p1", "w1:t1"), pane("w1:p2", "w1:t2"), pane("w2:p1", "w2:t1"))
    other_workspace = world.start_nvim("w2:p1")
    same_workspace = world.start_nvim("w1:p2")
    file = world.file("main.go")

    result = world.run("open", "main.go:3:4", "--focus")

    assert result.returncode == 0, result.stderr
    assert world.where(same_workspace) == (resolved(file), 3, 4)
    assert world.where(other_workspace)[0] == ""
    assert world.calls()[-2:] == ["workspace focus w1", "tab focus w1:t2"]


def test_starts_a_neovim_beside_the_caller_when_none_is_near(world: World):
    world.panes(pane("w1:p1", "w1:t1"), pane("w2:p1", "w2:t1"))
    world.start_nvim("w2:p1")
    file = world.file("main.go")

    result = world.run("open", "main.go", "--line", "7")

    assert result.returncode == 0, result.stderr
    assert "new pane w1:p9" in result.stdout
    split, run = world.calls()[-2:]
    assert (
        split
        == f"pane split w1:p1 --direction right --cwd {world.project.resolve()} --no-focus"
    )
    assert run == f"pane run w1:p9 nvim '+call cursor(7, 1)' -- {resolved(file)}"


def test_no_spawn_fails_instead_of_starting_a_neovim(world: World):
    world.panes(pane("w1:p1", "w1:t1"))
    world.file("main.go")

    result = world.run("open", "main.go", "--no-spawn")

    assert result.returncode == 1
    assert "no Neovim in this tab or workspace" in result.stderr
    assert not any(call.startswith("pane split") for call in world.calls())


def test_parent_neovim_wins_over_the_multiplexer(world: World):
    world.panes(pane("w1:p1", "w1:t1"), pane("w1:p3", "w1:t1"))
    beside = world.start_nvim("w1:p3")
    parent = world.start_nvim("w9:p9")
    world.env["NVIM"] = parent
    file = world.file("main.go")

    result = world.run("open", "main.go:5")

    assert result.returncode == 0, result.stderr
    assert world.where(parent) == (resolved(file), 5, 1)
    assert world.where(beside)[0] == ""


def test_a_file_whose_name_looks_like_a_location_opens_as_written(world: World):
    world.panes(pane("w1:p1", "w1:t1"), pane("w1:p3", "w1:t1"))
    beside = world.start_nvim("w1:p3")
    file = world.file("notes:2")

    result = world.run("open", "notes:2")

    assert result.returncode == 0, result.stderr
    assert world.where(beside)[0] == resolved(file)


def test_missing_file_is_an_error(world: World):
    world.panes(pane("w1:p1", "w1:t1"))

    result = world.run("open", "nope.go:3")

    assert result.returncode == 1
    assert "no such file: nope.go" in result.stderr


def test_line_past_the_end_lands_on_the_last_line(world: World):
    world.panes(pane("w1:p1", "w1:t1"), pane("w1:p3", "w1:t1"))
    beside = world.start_nvim("w1:p3")
    file = world.file("short.txt", lines=4)

    result = world.run("open", "short.txt:99")

    assert result.returncode == 0, result.stderr
    assert world.where(beside) == (resolved(file), 4, 1)
