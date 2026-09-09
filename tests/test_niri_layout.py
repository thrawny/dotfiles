"""Exercise monitor detection without changing the running desktop."""

import json
import os
import subprocess
from collections.abc import Callable
from pathlib import Path
from typing import Any

import pytest

ROOT = Path(__file__).resolve().parents[1]
PHILIPS = "Philips Consumer Electronics Company"
type RunWork = Callable[..., tuple[subprocess.CompletedProcess[str], list[str]]]


@pytest.fixture
def run_work(tmp_path: Path) -> RunWork:
    log = tmp_path / "calls"
    for name in ("niri", "niri-move-workspaces", "niri-set-column-width"):
        stub = tmp_path / name
        stub.write_text(
            "#!/usr/bin/env bash\n"
            + 'if [[ "${0##*/}" == niri && "$*" == "msg -j outputs" ]]; then\n'
            + '  printf "%s\\n" "$OUTPUTS"\n  exit "$QUERY_EXIT"\nfi\n'
            + 'printf "%s %s\\n" "${0##*/}" "$*" >> "$CALLS"\n'
        )
        stub.chmod(0o755)

    def run(outputs: dict[str, Any], query_exit: int = 0):
        log.write_text("")
        result = subprocess.run(
            ["bash", str(ROOT / "bin/niri-layout"), "work"],
            env={
                **os.environ,
                "PATH": f"{tmp_path}{os.pathsep}{os.environ['PATH']}",
                "OUTPUTS": json.dumps(outputs),
                "QUERY_EXIT": str(query_exit),
                "CALLS": str(log),
                "TRACE": "",
            },
            capture_output=True,
            text=True,
        )
        return result, log.read_text().splitlines()

    return run


@pytest.mark.parametrize("connector", ["DP-1", "DP-2", "DP-8", "HDMI-A-1"])
def test_work_follows_philips_across_connectors(run_work: RunWork, connector: str):
    result, calls = run_work(
        {
            "eDP-1": {
                "name": "eDP-1",
                "make": "Lenovo Group Limited",
                "logical": {"x": 898, "y": 1440, "width": 1645, "height": 1028},
            },
            "DP-3": {"name": "DP-3", "make": "LG Electronics"},
            connector: {
                "name": connector,
                "make": PHILIPS,
                "model": "PHL34E1C5600",
                "logical": {"x": 4206, "y": 0, "width": 3440, "height": 1440},
            },
        }
    )
    assert result.returncode == 0, result.stderr
    assert calls == [
        "niri msg output eDP-1 on",
        f"niri msg output {connector} on",
        f"niri msg output {connector} position set 0 0",
        "niri msg output eDP-1 position set 898 1440",
        f"niri-move-workspaces {connector} --except main",
        "niri msg action move-workspace-to-monitor --reference main eDP-1",
        "niri-set-column-width 0.33333",
    ]


def test_position_uses_scaled_dimensions(run_work: RunWork):
    result, calls = run_work(
        {
            "DP-2": {
                "name": "DP-2",
                "make": PHILIPS,
                "logical": {"width": 2752, "height": 1152, "scale": 1.25},
            },
            "eDP-1": {
                "name": "eDP-1",
                "logical": {"width": 1440, "height": 900, "scale": 2},
            },
        }
    )
    assert result.returncode == 0, result.stderr
    assert "niri msg output DP-2 position set 0 0" in calls
    assert "niri msg output eDP-1 position set 656 1152" in calls


def test_missing_dimensions_does_not_move_workspaces(run_work: RunWork):
    result, calls = run_work(
        {"DP-2": {"name": "DP-2", "make": PHILIPS, "logical": None}}
    )
    assert result.returncode != 0
    assert "requires active Philips and laptop outputs" in result.stderr
    assert calls == ["niri msg output eDP-1 on", "niri msg output DP-2 on"]


@pytest.mark.parametrize(
    "outputs",
    [
        {},
        {"DP-1": {"name": "DP-1", "make": "LG Electronics"}},
        {name: {"name": name, "make": PHILIPS} for name in ("DP-1", "DP-2")},
    ],
)
def test_missing_or_ambiguous_monitor_does_not_change_layout(
    run_work: RunWork, outputs: dict[str, Any]
):
    result, calls = run_work(outputs)
    assert result.returncode != 0
    assert "exactly one connected Philips monitor" in result.stderr
    assert calls == []


def test_query_failure_does_not_change_layout(run_work: RunWork):
    result, calls = run_work({"DP-2": {"name": "DP-2", "make": PHILIPS}}, query_exit=1)
    assert result.returncode != 0
    assert calls == []
