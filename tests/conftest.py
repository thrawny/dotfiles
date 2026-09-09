"""Shared desktop fixtures. No test connects to the live compositor."""

import importlib.util
import os
import socket
import subprocess
import sys
from collections.abc import Iterator
from importlib.machinery import SourceFileLoader
from pathlib import Path
from types import ModuleType

import pytest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin/desktop-broker"


@pytest.fixture(scope="session")
def broker() -> ModuleType:
    loader = SourceFileLoader("desktop_broker", str(SCRIPT))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


@pytest.fixture
def socket_pair() -> Iterator[tuple[socket.socket, socket.socket]]:
    server, client = socket.socketpair()
    with server, client:
        yield server, client


@pytest.fixture
def desktop_host(tmp_path: Path) -> Iterator[dict[str, str]]:
    if sys.platform != "linux":
        pytest.skip("Linux socket activation")
    endpoint = tmp_path / "desktop-broker/broker.sock"
    endpoint.parent.mkdir()
    environment = {
        **os.environ,
        "SANDBOX": "1",
        "XDG_RUNTIME_DIR": str(tmp_path),
        "WAYLAND_DISPLAY": "missing-wayland",
        "DISPLAY": "",
        "PATH": f"{tmp_path}:{ROOT / 'bin'}:{os.environ['PATH']}",
    }
    # Simulate systemd FD passing. Tests supply fake tools at these fixed paths
    # before making requests. Neither Wayland nor X11 is usable in this fixture.
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
        listener.bind(str(endpoint))
        listener.listen(8)
        fd = listener.fileno()
        process = subprocess.Popen(
            [
                "bash",
                "-c",
                f'exec 3<&{fd}; unset SANDBOX; export LISTEN_PID=$$ LISTEN_FDS=1; exec "$@"',
                "broker-test",
                sys.executable,
                "-I",
                str(SCRIPT),
                "serve",
                "--opener",
                str(tmp_path / "opener"),
                "--wl-paste",
                str(tmp_path / "host-wl-paste"),
            ],
            pass_fds=(fd,),
            env=environment,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        try:
            yield environment
        finally:
            process.terminate()
            process.communicate(timeout=5)
