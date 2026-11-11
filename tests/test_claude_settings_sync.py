"""The settings sync overwrites a live file, so drift handling must be exact."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path
from typing import Any

import pytest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/claude-settings-sync.py"

SWITCH = {"type": "command", "command": "agent-switch track stop --agent claude"}
MOTO = {"type": "command", "command": "moto attach --hook"}
EXAMPLE = {
    "model": "claude-fable-5-1",
    "enabledPlugins": {"handoff": True},
    "hooks": {
        "Stop": [{"hooks": [SWITCH]}],
        "SessionStart": [
            {"hooks": [SWITCH]},
            {"matcher": "startup", "hooks": [MOTO, SWITCH]},
        ],
    },
    "statusLine": {"type": "command", "command": "python3 ~/dotfiles/status_line.py"},
}
STRIPPED = {
    **EXAMPLE,
    "hooks": {"SessionStart": [{"matcher": "startup", "hooks": [MOTO]}]},
}


def run(tmp_path: Path, *flags: str) -> subprocess.CompletedProcess[str]:
    example = tmp_path / "settings.example.json"
    if not example.exists():
        example.write_text(json.dumps(EXAMPLE))
    return subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "--example",
            str(example),
            "--target",
            str(tmp_path / "live/settings.json"),
            "--backup-dir",
            str(tmp_path / "backups"),
            *flags,
        ],
        text=True,
        capture_output=True,
        check=True,
    )


def live(tmp_path: Path) -> Any:
    return json.loads((tmp_path / "live/settings.json").read_text())


def backups(tmp_path: Path) -> list[str]:
    directory = tmp_path / "backups"
    return (
        [p.read_text() for p in sorted(directory.iterdir())]
        if directory.exists()
        else []
    )


@pytest.mark.parametrize(
    ("flags", "expected"), [((), STRIPPED), (("--agent-switch",), EXAMPLE)]
)
def test_missing_file_is_written_with_host_filter(
    tmp_path: Path, flags: tuple[str, ...], expected: dict[str, Any]
) -> None:
    run(tmp_path, *flags)

    assert live(tmp_path) == expected
    assert backups(tmp_path) == []


def test_no_drift_leaves_file_untouched(tmp_path: Path) -> None:
    target = tmp_path / "live/settings.json"
    target.parent.mkdir()
    # Same settings in another key order and layout still count as in sync.
    original = json.dumps(dict(reversed(list(STRIPPED.items()))))
    target.write_text(original)

    run(tmp_path)

    assert target.read_text() == original
    assert backups(tmp_path) == []


@pytest.mark.parametrize(
    ("flags", "expected"), [((), STRIPPED), (("--agent-switch",), EXAMPLE)]
)
def test_drift_is_backed_up_then_replaced(
    tmp_path: Path, flags: tuple[str, ...], expected: dict[str, Any]
) -> None:
    target = tmp_path / "live/settings.json"
    target.parent.mkdir()
    stale = json.dumps({**expected, "permissions": {"ask": ["Bash(rm:*)"]}})
    target.write_text(stale)

    result = run(tmp_path, *flags)

    assert live(tmp_path) == expected
    assert backups(tmp_path) == [stale]
    assert "Bash(rm:*)" in result.stdout


def test_store_variant_drops_plugins_and_uses_home_status_line(tmp_path: Path) -> None:
    run(tmp_path, "--store")

    settings = live(tmp_path)
    assert "enabledPlugins" not in settings
    assert settings["statusLine"]["command"] == "python3 ~/.claude/status_line.py"
    assert settings["hooks"] == STRIPPED["hooks"]


def test_stale_symlink_is_replaced_by_a_regular_file(tmp_path: Path) -> None:
    target = tmp_path / "live/settings.json"
    target.parent.mkdir()
    old = tmp_path / "store-settings.json"
    old.write_text("{}")
    target.symlink_to(old)

    run(tmp_path)

    assert not target.is_symlink()
    assert live(tmp_path) == STRIPPED
    assert old.read_text() == "{}"


def test_dry_run_reports_drift_without_writing(tmp_path: Path) -> None:
    target = tmp_path / "live/settings.json"
    target.parent.mkdir()
    target.write_text("{}")

    run(tmp_path, "--dry-run")

    assert target.read_text() == "{}"
    assert backups(tmp_path) == []


def test_real_example_drops_every_agent_switch_hook(tmp_path: Path) -> None:
    (tmp_path / "settings.example.json").write_text(
        (ROOT / "config/claude/settings.example.json").read_text()
    )

    run(tmp_path)

    assert "agent-switch" not in (tmp_path / "live/settings.json").read_text()
