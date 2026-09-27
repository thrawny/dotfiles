"""Mock display commands so recovery tests never touch the live session."""

import fcntl
import json
import os
import shutil
import subprocess
from collections.abc import Callable
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
type RunRecovery = Callable[..., tuple[subprocess.CompletedProcess[str], list[str]]]


@pytest.fixture
def recovery(tmp_path: Path) -> RunRecovery:
    log = tmp_path / "calls"
    tools = tmp_path / "tools"
    tools.mkdir()
    grep = shutil.which("grep")
    assert grep
    stubs = {
        "hyprctl": r"""
if [[ "$*" == 'monitors -j' ]]; then
    if [[ -f "$TEST_ROOT/queried" ]]; then
        printf '%s\n' "$MONITORS_AFTER"
    else
        touch "$TEST_ROOT/queried"
        printf '%s\n' "$MONITORS"
    fi
    exit 0
fi
printf '%s\n' "$*" >> "$CALLS"
if [[ "$FAIL_OFF" == 1 && "$*" == *'action = "off"'* ]]; then exit 1; fi
""",
        "systemctl": r"""
echo systemctl >> "$CALLS"
if [[ "$GPU" == missing ]]; then
    printf 'LoadState=not-found\nActiveState=inactive\nJob=\nResult=success\n'
elif [[ "$GPU" == failed ]]; then
    printf 'LoadState=loaded\nActiveState=failed\nJob=\nResult=exit-code\n'
elif [[ "$GPU" == stuck || ! -f "$TEST_ROOT/gpu-ready" ]]; then
    touch "$TEST_ROOT/gpu-ready"
    printf 'LoadState=loaded\nActiveState=inactive\nJob=123\nResult=success\n'
else
    printf 'LoadState=loaded\nActiveState=inactive\nJob=\nResult=success\n'
fi
""",
        "sleep": r"""
echo sleep >> "$CALLS"
if [[ "$CLOSE_DURING_SLEEP" == 1 ]]; then touch "$TEST_ROOT/closed"; fi
if [[ "$FAIL_SLEEP" == 1 ]]; then exit 1; fi
""",
        "grep": f"""
if [[ "$*" == *'/proc/acpi/button/lid/'* ]]; then
    [[ "$LID_CLOSED" == 1 || -f "$TEST_ROOT/closed" ]]
else
    exec {grep} "$@"
fi
""",
        "niri": 'echo "niri $*" >> "$CALLS"',
    }
    for name, body in stubs.items():
        tool = tools / name
        tool.write_text("#!/usr/bin/env bash\n" + body)
        tool.chmod(0o755)

    def run(
        *args: str,
        monitors: list[dict[str, object]] | None = None,
        after: list[dict[str, object]] | None = None,
        script: str = "hypr-display-recover",
        locked: bool = False,
        **env: str,
    ):
        outputs = (
            monitors
            if monitors is not None
            else [{"name": "HDMI-A-1"}, {"name": "DP-1"}]
        )
        log.write_text("")
        with (tmp_path / "hypr-display-recover.lock").open("w") as lock:
            if locked:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result = subprocess.run(
                ["bash", str(ROOT / "bin" / script), *args],
                env={
                    **os.environ,
                    "PATH": f"{tools}{os.pathsep}{os.environ['PATH']}",
                    "HYPRLAND_INSTANCE_SIGNATURE": "test",
                    "XDG_RUNTIME_DIR": str(tmp_path),
                    "TEST_ROOT": str(tmp_path),
                    "CALLS": str(log),
                    "MONITORS": json.dumps(outputs),
                    "MONITORS_AFTER": json.dumps(
                        after if after is not None else outputs
                    ),
                    "GPU": "ready",
                    "LID_CLOSED": "0",
                    "CLOSE_DURING_SLEEP": "0",
                    "FAIL_OFF": "0",
                    "FAIL_SLEEP": "0",
                    **env,
                },
                capture_output=True,
                text=True,
                timeout=10,
            )
        return result, log.read_text().splitlines()

    return run


def dpms(action: str, monitor: str) -> str:
    return f'dispatch hl.dsp.dpms({{ action = "{action}", monitor = "{monitor}" }})'


def test_resume_waits_for_queued_inactive_gpu_job(recovery: RunRecovery):
    result, calls = recovery("--after-sleep")
    assert result.returncode == 0, result.stderr
    assert calls == [
        "systemctl",
        "sleep",
        "systemctl",
        dpms("off", "HDMI-A-1"),
        dpms("off", "DP-1"),
        "sleep",
        dpms("on", "HDMI-A-1"),
        dpms("on", "DP-1"),
    ]


@pytest.mark.parametrize("gpu", ["failed", "stuck"])
def test_gpu_failure_does_not_touch_displays(recovery: RunRecovery, gpu: str):
    result, calls = recovery("--after-sleep", GPU=gpu)
    assert result.returncode != 0
    assert not any("dispatch" in call for call in calls)


def test_laptop_without_nvidia(recovery: RunRecovery):
    result, calls = recovery(
        "--after-sleep", GPU="missing", monitors=[{"name": "eDP-1"}]
    )
    assert result.returncode == 0, result.stderr
    assert calls == ["systemctl", dpms("off", "eDP-1"), "sleep", dpms("on", "eDP-1")]


def test_closed_lid_keeps_panel_off(recovery: RunRecovery):
    result, calls = recovery(
        monitors=[{"name": "eDP-1"}, {"name": "DP-1"}], LID_CLOSED="1"
    )
    assert result.returncode == 0, result.stderr
    assert calls == [
        dpms("off", "eDP-1"),
        dpms("off", "DP-1"),
        "sleep",
        dpms("on", "DP-1"),
    ]


def test_lid_closes_during_recovery(recovery: RunRecovery):
    result, calls = recovery(monitors=[{"name": "eDP-1"}], CLOSE_DURING_SLEEP="1")
    assert result.returncode == 0, result.stderr
    assert calls == [dpms("off", "eDP-1"), "sleep"]


def test_unplug_during_cycle_does_not_fall_back_to_all_outputs(recovery: RunRecovery):
    result, calls = recovery("DP-1", after=[])
    assert result.returncode == 0, result.stderr
    assert calls == [dpms("off", "DP-1"), "sleep"]


def test_missing_panel_shortcut_does_nothing(recovery: RunRecovery):
    result, calls = recovery(script="hypr-panel-recover")
    assert result.returncode == 0, result.stderr
    assert calls == []


def test_disabled_output_stays_disabled(recovery: RunRecovery):
    result, calls = recovery(monitors=[{"name": "DP-1", "disabled": True}])
    assert result.returncode == 0, result.stderr
    assert calls == []


@pytest.mark.parametrize("failure", ["FAIL_OFF", "FAIL_SLEEP"])
def test_error_still_restores_output(recovery: RunRecovery, failure: str):
    result, calls = recovery("DP-1", **{failure: "1"})
    assert result.returncode != 0
    assert calls[-1] == dpms("on", "DP-1")


def test_idle_wake_does_not_cycle(recovery: RunRecovery):
    result, calls = recovery(script="dpms-on")
    assert result.returncode == 0, result.stderr
    assert calls == [dpms("on", "HDMI-A-1"), dpms("on", "DP-1")]


def test_overlapping_recovery_is_skipped(recovery: RunRecovery):
    result, calls = recovery(locked=True)
    assert result.returncode == 0, result.stderr
    assert calls == []


def test_niri_wake_unchanged(recovery: RunRecovery):
    result, calls = recovery(
        "--after-sleep", HYPRLAND_INSTANCE_SIGNATURE="", NIRI_SOCKET="test"
    )
    assert result.returncode == 0, result.stderr
    assert calls == ["niri msg action power-on-monitors"]
