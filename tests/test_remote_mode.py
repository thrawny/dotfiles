"""Exercise persistent remote-mode state without sudo or real power operations."""

import os
import subprocess
from pathlib import Path
from typing import final

import pytest

ROOT = Path(__file__).resolve().parents[1]


@final
class RemoteMode:
    def __init__(self, tmp_path: Path):
        self.marker = tmp_path / "state/enabled"
        self.active = tmp_path / "active"
        self.calls = tmp_path / "calls"
        self.calls.touch()
        self.script = tmp_path / "remote-mode"
        source = (ROOT / "bin/remote-mode").read_text()
        # Redirect privileged paths and skip escalation only in this test copy.
        source = source.replace("/var/lib/remote-mode", str(tmp_path / "state"))
        source = source.replace("/run/lock/remote-mode.lock", str(tmp_path / "lock"))
        source = source.replace("/sys/class/power_supply", str(tmp_path / "supplies"))
        source = source.replace("/usr/bin/pmset", str(tmp_path / "pmset"))
        source = source.replace("/usr/bin/sudo", str(tmp_path / "sudo"))
        source = source.replace("(( EUID != 0 ))", "false")
        self.script.write_text(source)
        stub = tmp_path / "systemctl"
        stub.write_text(
            """#!/usr/bin/env bash
set -eu
echo "$*" >> "$CALLS"
case "$1" in
  cat) [[ "$FAIL" != missing ]] ;;
  is-active) test -f "$ACTIVE" ;;
  start) [[ "$FAIL" != start ]] || exit 1; touch "$ACTIVE" ;;
  stop) [[ "$FAIL" != stop ]] || exit 1; rm -f "$ACTIVE" ;;
  *) exit 99 ;;
esac
"""
        )
        stub.chmod(0o755)
        for name, body in {
            "uname": 'echo "$PLATFORM"',
            "sudo": 'exec "$@"',
            "pmset": (
                'echo "pmset $*" >> "$CALLS"\n'
                'case "$*" in\n'
                '  "-g batt") echo "$POWER_SOURCE" ;;\n'
                '  "-g") echo "$PM_SETTINGS" ;;\n'
                '  "-a disablesleep "*) [[ "$FAIL" != pmset ]] ;;\n'
                "  *) exit 99 ;;\n"
                "esac"
            ),
        }.items():
            tool = tmp_path / name
            tool.write_text(f"#!/usr/bin/env bash\nset -eu\n{body}\n")
            tool.chmod(0o755)
        self.env = {
            **os.environ,
            "PATH": f"{tmp_path}{os.pathsep}{os.environ['PATH']}",
            "ACTIVE": str(self.active),
            "CALLS": str(self.calls),
            "FAIL": "",
            "PLATFORM": "Linux",
            "POWER_SOURCE": "Now drawing from 'AC Power'",
            "PM_SETTINGS": "System-wide power settings:\n SleepDisabled 0\n",
        }

    def run(self, *args: str, fail: str = "") -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(self.script), *args],
            env={**self.env, "FAIL": fail},
            capture_output=True,
            text=True,
            check=False,
        )


@pytest.fixture
def mode(tmp_path: Path) -> RemoteMode:
    return RemoteMode(tmp_path)


def test_on_is_persistent_and_idempotent(mode: RemoteMode):
    for _ in range(2):
        result = mode.run("on")
        assert result.returncode == 0, result.stderr
        assert mode.marker.is_file()
        assert mode.active.is_file()
    assert "Remote mode is on" in mode.run("status").stdout
    assert "suspend" not in mode.calls.read_text()


def test_off_clears_running_and_persistent_state(mode: RemoteMode):
    assert mode.run("on").returncode == 0
    for _ in range(2):
        result = mode.run("off")
        assert result.returncode == 0, result.stderr
        assert not mode.marker.exists()
        assert not mode.active.exists()
    assert "Remote mode is off" in mode.run("status").stdout


def test_status_does_not_modify_state(mode: RemoteMode):
    assert mode.run("status").returncode == 0
    assert not mode.marker.parent.exists()
    assert mode.calls.read_text().splitlines() == [
        "cat remote-mode.service",
        "is-active --quiet remote-mode.service",
    ]


def test_status_reports_missing_inhibitor(mode: RemoteMode):
    assert mode.run("on").returncode == 0
    mode.active.unlink()
    result = mode.run("status")
    assert result.returncode == 1
    assert "not running" in result.stderr
    assert mode.marker.exists()


def test_status_reports_unpersisted_inhibitor(mode: RemoteMode):
    mode.active.touch()
    result = mode.run("status")
    assert result.returncode == 1
    assert "not enabled for boot" in result.stderr


def test_failed_first_start_rolls_back_marker(mode: RemoteMode):
    result = mode.run("on", fail="start")
    assert result.returncode == 1
    assert not mode.marker.exists()
    assert "Failed to start" in result.stderr


def test_failed_restart_preserves_existing_preference(mode: RemoteMode):
    assert mode.run("on").returncode == 0
    mode.active.unlink()
    assert mode.run("on", fail="start").returncode == 1
    assert mode.marker.exists()


def test_failed_stop_preserves_preference(mode: RemoteMode):
    assert mode.run("on").returncode == 0
    assert mode.run("off", fail="stop").returncode == 1
    assert mode.marker.exists()
    assert mode.active.exists()


@pytest.mark.parametrize("args", [(), ("toggle",), ("on", "off")])
def test_invalid_arguments_have_no_effect(mode: RemoteMode, args: tuple[str, ...]):
    result = mode.run(*args)
    assert result.returncode == 2
    assert "Usage:" in result.stderr
    assert not mode.marker.parent.exists()
    assert mode.calls.read_text() == ""


def test_missing_service_fails_without_creating_state(mode: RemoteMode):
    result = mode.run("on", fail="missing")
    assert result.returncode == 1
    assert "not installed" in result.stderr
    assert not mode.marker.parent.exists()


@pytest.mark.parametrize("online", ["0", "1"])
def test_linux_laptop_requires_ac(mode: RemoteMode, tmp_path: Path, online: str):
    battery = tmp_path / "supplies/BAT0"
    battery.mkdir(parents=True)
    (battery / "type").write_text("Battery\n")
    mains = tmp_path / "supplies/AC"
    mains.mkdir()
    (mains / "type").write_text("Mains\n")
    (mains / "online").write_text(online)
    result = mode.run("on")
    assert result.returncode == (0 if online == "1" else 1)
    assert mode.marker.exists() == (online == "1")
    if online == "1":
        assert "Unplugging does not turn it off" in result.stdout
        (mains / "online").write_text("0")
        assert mode.run("off").returncode == 0
    else:
        assert "Connect AC power" in result.stderr


def test_device_battery_does_not_make_desktop_a_laptop(
    mode: RemoteMode, tmp_path: Path
):
    battery = tmp_path / "supplies/mouse"
    battery.mkdir(parents=True)
    (battery / "type").write_text("Battery\n")
    (battery / "scope").write_text("Device\n")
    assert mode.run("on").returncode == 0


def test_mac_on_and_off_use_pmset(mode: RemoteMode):
    mode.env["PLATFORM"] = "Darwin"
    result = mode.run("on")
    assert result.returncode == 0, result.stderr
    assert "Unplugging does not turn it off" in result.stdout
    assert mode.run("off").returncode == 0
    assert mode.calls.read_text().splitlines() == [
        "pmset -g batt",
        "pmset -a disablesleep 1",
        "pmset -a disablesleep 0",
    ]
    assert not mode.marker.parent.exists()


def test_mac_refuses_on_battery_but_allows_off(mode: RemoteMode):
    mode.env.update(PLATFORM="Darwin", POWER_SOURCE="Now drawing from 'Battery Power'")
    result = mode.run("on")
    assert result.returncode == 1
    assert "Connect AC power" in result.stderr
    assert "disablesleep 1" not in mode.calls.read_text()
    assert mode.run("off").returncode == 0


@pytest.mark.parametrize("disabled", ["0", "1"])
def test_mac_status_reads_persistent_setting(mode: RemoteMode, disabled: str):
    mode.env.update(PLATFORM="Darwin", PM_SETTINGS=f" SleepDisabled\t{disabled}\n")
    result = mode.run("status")
    assert result.returncode == 0
    assert f"Remote mode is {'on' if disabled == '1' else 'off'}" in result.stdout
    assert mode.calls.read_text() == "pmset -g\n"


def test_mac_unknown_status_is_not_reported_as_off(mode: RemoteMode):
    mode.env.update(PLATFORM="Darwin", PM_SETTINGS="unknown")
    assert mode.run("status").returncode == 1


def test_mac_pmset_failure_is_not_reported_as_success(mode: RemoteMode):
    mode.env["PLATFORM"] = "Darwin"
    result = mode.run("on", fail="pmset")
    assert result.returncode != 0
    assert "Remote mode is on" not in result.stdout


def test_service_blocks_sleep_but_not_idle_and_starts_at_boot():
    module = (ROOT / "nix/modules/remote-mode.nix").read_text()
    assert "--what=sleep --mode=block" in module
    assert "--what=idle" not in module
    assert 'wantedBy = [ "multi-user.target" ];' in module
    assert 'ConditionPathExists = "/var/lib/remote-mode/enabled";' in module
    assert 'Type = "notify";' in module
    assert "systemd-notify --ready" in module
    assert 'export NOTIFY_SOCKET="$1"' in module
    assert '${holdAwake} "$NOTIFY_SOCKET"' in module
