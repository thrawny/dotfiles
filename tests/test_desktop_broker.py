"""Exercise the broker and sandbox URL routing without touching the desktop."""

import json
import os
import socket
import subprocess
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from types import ModuleType
from unittest.mock import patch

import pytest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin/desktop-broker"
LINUX = pytest.mark.skipif(sys.platform != "linux", reason="Linux peer credentials")
VALID_REQUEST = {"version": 1, "operation": "open-url", "target": "https://example.com"}


def exchange(broker: ModuleType, payload: bytes):
    server, client = socket.socketpair()
    with server, client:
        client.sendall(payload)
        client.shutdown(socket.SHUT_WR)
        with patch.object(broker, "open_url") as opener:
            broker.handle(server, "/fixed/router", [], "/fixed/wl-paste")
            return broker.receive(client, 1), opener.call_args_list


@LINUX
def test_open_url_has_one_fixed_host_command(broker: ModuleType):
    target = "https://example.com/?q=$(touch%20/tmp/nope)&x=1"
    response, calls = exchange(
        broker, json.dumps({**VALID_REQUEST, "target": target}).encode() + b"\n"
    )
    assert response == {"version": 1, "ok": True, "result": None}
    assert calls[0].args == (target, "/fixed/router")


@LINUX
@pytest.mark.parametrize(
    "payload", [b"[]\n", b"null\n", b"garbage\n", b"\xff\n", b"{}", b"{}\n{}\n"]
)
def test_rejects_malformed_messages(broker: ModuleType, payload: bytes):
    response, calls = exchange(broker, payload)
    assert response["ok"] is False
    assert calls == []


@LINUX
def test_rejects_oversized_messages(broker: ModuleType):
    response, calls = exchange(broker, b"x" * (broker.MAX_MESSAGE_BYTES + 1))
    assert response["ok"] is False
    assert calls == []


@LINUX
@pytest.mark.parametrize(
    "message",
    [
        {},
        {**VALID_REQUEST, "version": True},
        {**VALID_REQUEST, "version": 2},
        {**VALID_REQUEST, "operation": "workspace"},
        {**VALID_REQUEST, "operation": "spawn"},
        {**VALID_REQUEST, "command": "sh"},
        {**VALID_REQUEST, "env": {"NIRI_SOCKET": "/elsewhere"}},
        {**VALID_REQUEST, "target": ["https://example.com"]},
        {**VALID_REQUEST, "target": "javascript:alert(1)"},
        {**VALID_REQUEST, "target": "--remote-debugging-port=9222"},
    ],
)
def test_rejects_invalid_requests(broker: ModuleType, message: dict[str, object]):
    response, calls = exchange(broker, json.dumps(message).encode() + b"\n")
    assert response["ok"] is False
    assert calls == []


def test_fragmented_message(
    broker: ModuleType, socket_pair: tuple[socket.socket, socket.socket]
):
    server, client = socket_pair

    def write():
        for part in (b'{"version":', b'1,"ok":true}', b"\n"):
            server.sendall(part)

    worker = threading.Thread(target=write)
    worker.start()
    try:
        assert broker.receive(client, 1) == {"version": 1, "ok": True}
    finally:
        worker.join(timeout=1)


def test_read_deadline(
    broker: ModuleType, socket_pair: tuple[socket.socket, socket.socket]
):
    server, client = socket_pair
    client.sendall(b"{")
    with pytest.raises((TimeoutError, ValueError)):
        broker.receive(server, 0.01)


@LINUX
def test_disconnected_client_does_not_crash_handler(
    broker: ModuleType, socket_pair: tuple[socket.socket, socket.socket]
):
    server, client = socket_pair
    client.close()
    broker.handle(server, "/unused", [], "/unused")


@LINUX
def test_wrong_uid_is_rejected(
    broker: ModuleType,
    socket_pair: tuple[socket.socket, socket.socket],
    monkeypatch: pytest.MonkeyPatch,
):
    server, client = socket_pair
    monkeypatch.setattr(broker.os, "getuid", lambda: -1)
    broker.handle(server, "/unused", [], "/unused")
    assert "UID" in broker.receive(client, 1)["error"]


def test_nonzero_opener_status_is_an_error(broker: ModuleType):
    with patch.object(broker.subprocess, "Popen") as popen:
        popen.return_value.__enter__.return_value.wait.return_value = 1
        with pytest.raises(ValueError, match="opener failed"):
            broker.open_url("https://example.com", "/fixed/router")
        assert popen.call_args.args[0] == ["/fixed/router", "https://example.com"]


def test_opener_timeout_terminates_process_group(broker: ModuleType):
    with (
        patch.object(broker.subprocess, "Popen") as popen,
        patch.object(broker.os, "killpg") as kill,
    ):
        process = popen.return_value.__enter__.return_value
        process.pid = 123
        process.wait.side_effect = [subprocess.TimeoutExpired("router", 40), 0]
        with pytest.raises(ValueError, match="timed out"):
            broker.open_url("https://example.com", "/fixed/router")
        assert kill.call_count == 2


@pytest.mark.parametrize(
    "target", ["https://example.com", "http://localhost:3000/path?q=a#b"]
)
def test_web_urls(broker: ModuleType, target: str):
    assert broker.normalize_target(target, []) == target


@pytest.mark.parametrize(
    "target",
    [
        "",
        None,
        "https://",
        "http://example.com:bad",
        "https://[bad",
        "https://example.com\n",
        "data:text/html,test",
        "javascript:alert(1)",
        "chrome://settings",
        "--new-window",
        "relative.html",
        "file://remote/tmp/index.html",
        "file:///tmp/test.html?query",
    ],
)
def test_bad_targets(broker: ModuleType, target: object):
    with pytest.raises(ValueError):
        broker.normalize_target(target, [])


def test_only_existing_html_inside_roots(broker: ModuleType, tmp_path: Path):
    root = tmp_path / "project"
    root.mkdir()
    page = root / "hello world.html"
    page.write_text("<h1>Test</h1>")
    for target in (str(page), page.as_uri()):
        assert broker.normalize_target(target, [root]) == page.as_uri()
    outside = tmp_path / "outside.html"
    outside.write_text("outside")
    escape = root / "escape.html"
    escape.symlink_to(outside)
    text = root / "private.txt"
    text.touch()
    folder = root / "directory.html"
    folder.mkdir()
    for target in (outside, escape, text, folder, root / "missing.html"):
        with pytest.raises(ValueError):
            broker.normalize_target(str(target), [root])


@pytest.mark.parametrize("router", ["niri-open-url", "sandbox-xdg-open"])
def test_router_uses_activated_broker_inside_sandbox(
    desktop_host: dict[str, str], tmp_path: Path, router: str
):
    log = tmp_path / "opened"
    opener = tmp_path / "opener"
    opener.write_text(
        f"#!/bin/sh\nprintf 'start %s\\n' \"$1\" >> '{log}'\n"
        + f"sleep 0.05\nprintf 'end %s\\n' \"$1\" >> '{log}'\n"
    )
    opener.chmod(0o755)
    targets = ["https://example.com/one", "http://localhost:3000/two"]

    def click(target: str):
        return subprocess.run(
            ["bash", str(ROOT / "bin" / router), target],
            env={**desktop_host, "PATH": f"{ROOT / 'bin'}:{os.environ['PATH']}"},
            capture_output=True,
            text=True,
            timeout=5,
        )

    with ThreadPoolExecutor(max_workers=2) as pool:
        for result in pool.map(click, targets):
            assert result.returncode == 0, result.stderr
    calls = log.read_text().splitlines()
    assert len(calls) == 4
    assert sorted(calls[::2]) == sorted(f"start {target}" for target in targets)
    # Concurrent clients must finish their focus/paste operations in pairs.
    for start, end in zip(calls[::2], calls[1::2]):
        assert end == start.replace("start ", "end ", 1)


@pytest.mark.parametrize("router", ["niri-open-url", "sandbox-xdg-open"])
def test_unavailable_broker_does_not_fall_back_to_helium(tmp_path: Path, router: str):
    helium = tmp_path / "helium"
    helium.write_text("#!/bin/sh\necho 'unexpected browser launch' >&2\nexit 99\n")
    helium.chmod(0o755)
    result = subprocess.run(
        ["bash", str(ROOT / "bin" / router), "https://example.com"],
        env={
            **os.environ,
            "SANDBOX": "1",
            "XDG_RUNTIME_DIR": str(tmp_path),
            "PATH": f"{tmp_path}:{ROOT / 'bin'}:{os.environ['PATH']}",
        },
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 1
    assert "broker unavailable" in result.stderr
    assert "unexpected browser launch" not in result.stderr


@pytest.mark.parametrize("sandbox", ["1", ""])
def test_server_refuses_sandbox_and_missing_activation(sandbox: str):
    result = subprocess.run(
        [
            sys.executable,
            "-I",
            str(SCRIPT),
            "serve",
            "--opener",
            "/unused",
            "--wl-paste",
            "/unused",
        ],
        env={**os.environ, "SANDBOX": sandbox, "LISTEN_PID": "", "LISTEN_FDS": ""},
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 1
    assert ("host" if sandbox else "systemd") in result.stderr
