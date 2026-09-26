"""Shared direnv helpers behave the same without a user's Home Manager config."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path

STDLIB = Path(__file__).resolve().parents[1] / "nix/lib/direnv-stdlib.sh"


def run_layout(directory: Path) -> subprocess.CompletedProcess[str]:
    script = r"""
set -eu
dotenv_if_exists() { :; }
log_status() { :; }
PATH_add() { export PATH="$1:$PATH"; }
uv() {
    printf '%s\n' "$*" >> uv-calls
    case "$1" in
        init) touch pyproject.toml ;;
        venv) mkdir -p .venv/bin ;;
    esac
}
source "$1"
layout_uv
printf '%s\n' "$VIRTUAL_ENV" "$UV_ACTIVE"
command -v example || true
"""
    environment = os.environ.copy()
    # Avoid activating a developer's environment or running actual uv/network calls.
    environment["VIRTUAL_ENV"] = ""
    return subprocess.run(
        ["bash", "-c", script, "direnv-test", str(STDLIB)],
        cwd=directory,
        env=environment,
        check=True,
        capture_output=True,
        text=True,
    )


def test_existing_environment_is_activated(tmp_path: Path) -> None:
    binary = tmp_path / ".venv/bin/example"
    binary.parent.mkdir(parents=True)
    binary.write_text("#!/bin/sh\nexit 0\n")
    binary.chmod(0o755)
    result = run_layout(tmp_path)
    assert result.stdout.splitlines() == [str(tmp_path / ".venv"), "1", str(binary)]
    assert not (tmp_path / "uv-calls").exists()


def test_existing_project_creates_only_environment(tmp_path: Path) -> None:
    (tmp_path / "pyproject.toml").write_text("[project]\nname = 'example'\n")
    result = run_layout(tmp_path)
    assert result.stdout.splitlines()[:2] == [str(tmp_path / ".venv"), "1"]
    assert (tmp_path / "uv-calls").read_text() == "venv\n"


def test_empty_directory_initializes_project(tmp_path: Path) -> None:
    run_layout(tmp_path)
    assert (tmp_path / "uv-calls").read_text() == "init\nvenv\n"
