"""Exercise reconnect timing without kubectl, network access or real sleeps."""

import runpy
from pathlib import Path
from types import SimpleNamespace

import pytest

KPF = runpy.run_path(str(Path(__file__).resolve().parents[1] / "bin/kpf"))


@pytest.mark.parametrize("stable_connection", [False, True])
def test_persistent_transient_failures_back_off_and_stable_connections_reset(
    monkeypatch: pytest.MonkeyPatch, stable_connection: bool
):
    manager = KPF["PortForwardManager"](
        KPF["PortForward"]("example", "example", "default", "example", 8080, 80)
    )
    now = 0.0
    attempts: list[float] = []

    def advance(seconds: float) -> None:
        nonlocal now
        now += seconds

    def fail() -> tuple[int, str, str]:
        attempts.append(now)
        if stable_connection and len(attempts) == 3:
            advance(40)
        if len(attempts) == 10:
            manager.stop()
        return 1, "", "lost connection to pod"

    monkeypatch.setitem(
        manager.start.__globals__,
        "time",
        SimpleNamespace(time=lambda: now, sleep=advance),
    )
    monkeypatch.setattr(manager, "run_kubectl", fail)
    manager.start()

    if stable_connection:
        assert attempts == [0, 0, 2, 42, 44, 48, 56, 72, 104, 164]
    else:
        assert attempts == [0, 0, 2, 6, 14, 30, 62, 122, 182, 242]
