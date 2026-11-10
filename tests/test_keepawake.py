"""Exercise session lifetimes and power decisions without sleeping a real machine."""

import datetime as dt
import importlib.machinery
import importlib.util
import stat
import sys
from pathlib import Path
from typing import Any

import pytest

ROOT = Path(__file__).resolve().parents[1]
pytestmark = pytest.mark.skipif(
    sys.platform != "linux", reason="Linux power and session service"
)
loader = importlib.machinery.SourceFileLoader("keepawake", str(ROOT / "bin/keepawake"))
spec = importlib.util.spec_from_loader(loader.name, loader)
assert spec is not None
keepawake: Any = importlib.util.module_from_spec(spec)
loader.exec_module(keepawake)


class Facts:
    def __init__(self):
        self.data: dict[str, Any] = {
            "on_ac": False,
            "battery_percent": 80,
            "wifi_ssids": ["Test Wi-Fi"],
            "processes": {"obs"},
            "external_displays": [],
        }
        self.errors: list[str] = []

    def sample(self, **_kwargs: Any):
        return self.data.copy(), self.errors.copy()


@pytest.fixture
def engine(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    clock = [100.0]
    monkeypatch.setattr(keepawake.time, "monotonic", lambda: clock[0])
    filename = tmp_path / "config.toml"
    filename.write_text(
        'version = 1\nbattery_floor = 20\nnotifications = false\nwifi_grace_seconds = 0\n[[rules]]\nname = "Wi-Fi"\n[rules.when]\nwifi_ssid = "Test Wi-Fi"\n'
    )
    directory = tmp_path / "runtime"
    directory.mkdir(mode=0o700)
    daemon = keepawake.Engine(filename, directory)
    facts = Facts()
    daemon.poll(facts)
    return daemon, facts, clock


@pytest.mark.parametrize("device_type", ["laptop", "desktop"])
def test_wifi_power_transitions(engine: Any, device_type: str):
    daemon, facts, _ = engine
    desktop = device_type == "desktop"
    if desktop:
        daemon.filename.write_text(
            'device_type = "desktop"\n'
            + daemon.filename.read_text().replace(
                'wifi_ssid = "Test Wi-Fi"', "wifi_connected = true"
            )
        )
        daemon.poll(facts)
    assert daemon.snapshot["active"]
    facts.data["battery_percent"] = 20
    daemon.poll(facts)
    assert daemon.snapshot["active"] is desktop
    facts.data["on_ac"] = True
    daemon.poll(facts)
    assert daemon.snapshot["active"]
    facts.data["wifi_ssids"] = ["Other Wi-Fi"]
    daemon.poll(facts)
    assert daemon.snapshot["active"] is desktop
    facts.data["wifi_ssids"] = []
    daemon.poll(facts)
    assert not daemon.snapshot["active"]
    facts.data["wifi_ssids"] = ["Test Wi-Fi"]
    facts.data["on_ac"] = False
    facts.data["battery_percent"] = 20.01
    daemon.poll(facts)
    assert daemon.snapshot["active"]


@pytest.mark.parametrize(
    "wifi_condition", ['wifi_ssid = "Test Wi-Fi"', "wifi_connected = true"]
)
@pytest.mark.parametrize("read_failure", [False, True])
def test_wifi_grace_expires_after_continuous_loss_and_rearms_on_reconnect(
    engine: Any, wifi_condition: str, read_failure: bool
):
    daemon, facts, clock = engine
    daemon.filename.write_text(
        daemon.filename.read_text()
        .replace("wifi_grace_seconds = 0\n", "")
        .replace('wifi_ssid = "Test Wi-Fi"', wifi_condition)
    )
    daemon.poll(facts)
    clock[0] += 60
    facts.data["wifi_ssids"] = []
    facts.errors = ["Wi-Fi information unavailable."] if read_failure else []
    daemon.poll(facts)
    assert daemon.snapshot["active"]
    assert daemon.snapshot["wifi_grace_remaining_seconds"] == 1200
    clock[0] += 1199
    daemon.poll(facts)
    assert not keepawake.can_idle("can-suspend", daemon.directory)
    clock[0] += 1
    daemon.poll(facts)
    assert keepawake.can_idle("can-suspend", daemon.directory)

    facts.data["wifi_ssids"] = ["Test Wi-Fi"]
    facts.errors = []
    daemon.poll(facts)
    assert daemon.snapshot["active"]
    facts.data["wifi_ssids"] = []
    daemon.poll(facts)
    clock[0] += 600
    daemon.poll(facts)
    facts.data["wifi_ssids"] = ["Test Wi-Fi"]
    daemon.poll(facts)
    facts.data["wifi_ssids"] = []
    daemon.poll(facts)
    clock[0] += 1199
    daemon.poll(facts)
    assert daemon.snapshot["active"], "Reconnection must reset the loss timer"
    clock[0] += 1
    daemon.poll(facts)
    assert not daemon.snapshot["active"]


@pytest.mark.parametrize(
    "override",
    [
        "battery",
        "unknown-power",
        "ac-rule",
        "pause",
        "disabled",
        "other-wifi",
        "stale",
        "sleep",
    ],
)
def test_wifi_grace_preserves_other_sleep_safety_conditions(
    engine: Any, monkeypatch: pytest.MonkeyPatch, override: str
):
    daemon, facts, clock = engine
    daemon.filename.write_text(
        daemon.filename.read_text().replace("wifi_grace_seconds = 0\n", "")
        + ("ac_power = true\n" if override == "ac-rule" else "")
    )
    facts.data["on_ac"] = True
    daemon.poll(facts)
    facts.data["wifi_ssids"] = []
    daemon.poll(facts)
    assert not keepawake.can_idle("can-suspend", daemon.directory)
    if override == "battery":
        facts.data.update(on_ac=False, battery_percent=20)
    elif override == "unknown-power":
        facts.data["on_ac"] = None
    elif override == "ac-rule":
        facts.data["on_ac"] = False
    elif override == "pause":
        daemon.command({"action": "pause"})
    elif override == "disabled":
        daemon.filename.write_text(
            daemon.filename.read_text().replace(
                'name = "Wi-Fi"', 'name = "Wi-Fi"\nenabled = false'
            )
        )
    elif override == "other-wifi":
        facts.data["wifi_ssids"] = ["Other Wi-Fi"]
    elif override == "stale":
        clock[0] += keepawake.MAX_AGE + 1
        assert keepawake.can_idle("can-suspend", daemon.directory)
        return
    elif override == "sleep":
        monkeypatch.setattr(
            keepawake, "suspend_offset", lambda: daemon.suspend_offset + 60
        )
    daemon.poll(facts)
    assert keepawake.can_idle("can-suspend", daemon.directory)


def test_wifi_grace_requires_an_observed_connection(engine: Any):
    previous, facts, _ = engine
    previous.filename.write_text(
        previous.filename.read_text().replace("wifi_grace_seconds = 0\n", "")
    )
    daemon = keepawake.Engine(previous.filename, previous.directory)
    facts.data["wifi_ssids"] = []
    daemon.poll(facts)
    assert not daemon.snapshot["active"]
    assert daemon.snapshot["wifi_grace_remaining_seconds"] == 0


@pytest.mark.parametrize("value", ["-1", "86401", '"1200"', "true", "nan", "inf"])
def test_wifi_grace_rejects_invalid_durations(engine: Any, value: str):
    daemon, _, _ = engine
    daemon.filename.write_text(
        daemon.filename.read_text().replace(
            "wifi_grace_seconds = 0", f"wifi_grace_seconds = {value}"
        )
    )
    with pytest.raises(keepawake.KeepawakeError):
        keepawake.load_config(daemon.filename)


def test_independent_manual_and_automatic_sessions(engine: Any):
    daemon, facts, clock = engine
    daemon.command({"action": "start", "duration": "10s", "keep_display_awake": True})
    first = daemon.snapshot["sessions"][0]["id"]
    daemon.command({"action": "start", "duration": "1h"})
    daemon.command({"action": "stop", "id": first})
    assert daemon.snapshot["active"]
    assert not daemon.snapshot["keep_display_awake"]
    assert len(daemon.snapshot["sessions"]) == 1
    daemon.command({"action": "stop"})
    assert daemon.snapshot["active"], (
        "Ending manual sessions must leave matching rules active"
    )
    facts.data["wifi_ssids"] = []
    daemon.poll(facts)
    daemon.command({"action": "start", "duration": "10s"})
    clock[0] += 11
    assert not daemon.command({"action": "status"})["active"]


def test_low_battery_ends_manual_sessions_and_ac_rearms_rules(engine: Any):
    daemon, facts, _ = engine
    daemon.command({"action": "toggle"})
    facts.data["battery_percent"] = 19
    daemon.poll(facts)
    assert not daemon.snapshot["active"]
    assert not daemon.snapshot["sessions"]
    with pytest.raises(keepawake.KeepawakeError):
        daemon.command({"action": "start"})
    facts.data["on_ac"] = True
    daemon.poll(facts)
    assert daemon.snapshot["active"]
    assert not daemon.snapshot["sessions"], "Ended manual sessions must not restart"


def test_pause_expires_timers_and_retains_automatic_rules(engine: Any):
    daemon, _, clock = engine
    daemon.command({"action": "start", "duration": "5s"})
    daemon.command({"action": "pause"})
    assert not daemon.snapshot["active"]
    clock[0] += 6
    daemon.command({"action": "resume"})
    assert daemon.snapshot["active"]
    assert not daemon.snapshot["sessions"]


def test_process_sessions_do_not_depend_on_window_focus(engine: Any):
    daemon, facts, _ = engine
    facts.data["wifi_ssids"] = []
    daemon.poll(facts)
    daemon.command({"action": "start", "process": "obs"})
    daemon.poll(facts)
    assert daemon.snapshot["active"]
    facts.data["processes"] = set()
    daemon.poll(facts)
    assert not daemon.snapshot["active"]
    with pytest.raises(keepawake.KeepawakeError):
        daemon.command({"action": "start", "process": "obs"})


def test_download_changes_extend_the_quiet_period(engine: Any, tmp_path: Path):
    daemon, facts, clock = engine
    facts.data["wifi_ssids"] = []
    daemon.poll(facts)
    download = tmp_path / "file.part"
    download.write_bytes(b"a")
    daemon.command({"action": "start", "file": str(download), "quiet_seconds": 10})
    clock[0] += 9
    download.write_bytes(b"ab")
    daemon.command({"action": "status"})
    clock[0] += 9
    assert daemon.command({"action": "status"})["active"]
    clock[0] += 2
    assert not daemon.command({"action": "status"})["active"]
    daemon.command({"action": "start", "file": str(download)})
    download.unlink()
    assert not daemon.command({"action": "status"})["active"]


def original_pid(_pid: int) -> str:
    return "original"


def replacement_pid(_pid: int) -> str:
    return "replacement"


def dead_pid(_pid: int) -> None:
    return None


def test_pid_reuse_ends_the_original_session(
    engine: Any, monkeypatch: pytest.MonkeyPatch
):
    daemon, facts, _ = engine
    facts.data["wifi_ssids"] = []
    daemon.poll(facts)
    monkeypatch.setattr(keepawake, "pid_identity", original_pid)
    daemon.command({"action": "start", "pid": 42})
    monkeypatch.setattr(keepawake, "pid_identity", replacement_pid)
    assert not daemon.command({"action": "status"})["active"]


@pytest.mark.parametrize("device_type", ["laptop", "desktop"])
def test_unknown_power_and_stale_facts_release_holds(engine: Any, device_type: str):
    daemon, facts, clock = engine
    if device_type == "desktop":
        daemon.filename.write_text(
            'device_type = "desktop"\n' + daemon.filename.read_text()
        )
    facts.data["on_ac"] = None
    facts.errors = ["Power unavailable"]
    daemon.poll(facts)
    assert daemon.snapshot["active"] is (device_type == "desktop")
    facts.data["on_ac"] = True
    daemon.poll(facts)
    clock[0] += keepawake.MAX_AGE + 1
    assert not daemon.command({"action": "status"})["active"]


def test_overnight_schedule_belongs_to_start_day():
    schedule = {"days": ["Fri"], "start": "22:00", "end": "02:00"}
    for instant, expected in (
        (dt.datetime(2026, 10, 16, 21, 59), False),
        (dt.datetime(2026, 10, 16, 22), True),
        (dt.datetime(2026, 10, 17, 1, 59), True),
        (dt.datetime(2026, 10, 17, 2), False),
        (dt.datetime(2026, 10, 18, 1), False),
    ):
        assert keepawake.in_schedule(schedule, instant) is expected


def test_initial_config_is_private_and_never_overwritten(tmp_path: Path):
    filename = tmp_path / "config.toml"
    keepawake.init_config(filename)
    assert stat.S_IMODE(filename.stat().st_mode) == 0o600
    filename.write_text("User content")
    keepawake.init_config(filename)
    assert filename.read_text() == "User content"


def test_desktop_without_upower_requires_batteryless_sysfs(tmp_path: Path):
    assert not keepawake.batteryless_desktop(tmp_path / "missing")
    assert keepawake.batteryless_desktop(tmp_path)
    battery = tmp_path / "BAT0"
    battery.mkdir()
    (battery / "type").write_text("Battery\n")
    assert not keepawake.batteryless_desktop(tmp_path)


def test_sleep_ends_manual_sessions_and_reevaluates_rules(
    engine: Any, monkeypatch: pytest.MonkeyPatch
):
    daemon, facts, clock = engine
    daemon.command({"action": "start", "duration": "1h"})
    daemon.suspend_offset = 0

    def after_sleep(_clock_id: int) -> float:
        return clock[0] + 30

    monkeypatch.setattr(keepawake.time, "clock_gettime", after_sleep)
    daemon.poll(facts)
    assert not daemon.snapshot["sessions"]
    assert daemon.snapshot["active"], "Automatic rules should reevaluate on wake"


def test_idle_guards_release_dead_stale_and_invalid_snapshots(
    engine: Any, monkeypatch: pytest.MonkeyPatch
):
    daemon, _, clock = engine
    assert not keepawake.can_idle("can-suspend", daemon.directory)
    assert keepawake.can_idle("can-screen-sleep", daemon.directory)
    assert keepawake.can_idle("can-lid-suspend", daemon.directory)
    daemon.command(
        {"action": "start", "keep_display_awake": True, "allow_lid_closed": True}
    )
    assert not keepawake.can_idle("can-screen-sleep", daemon.directory)
    assert not keepawake.can_idle("can-lid-suspend", daemon.directory)
    clock[0] += keepawake.MAX_AGE + 1
    assert keepawake.can_idle("can-suspend", daemon.directory)
    clock[0] -= keepawake.MAX_AGE + 1
    monkeypatch.setattr(keepawake, "pid_identity", dead_pid)
    assert keepawake.can_idle("can-suspend", daemon.directory)
    (daemon.directory / "status.json").write_text("not json")
    assert keepawake.can_idle("can-suspend", daemon.directory)
