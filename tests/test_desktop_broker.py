"""Exercise the broker and sandbox URL routing without touching the desktop."""

import importlib.util
import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from importlib.machinery import SourceFileLoader
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin/desktop-broker"
loader = SourceFileLoader("desktop_broker", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
assert spec is not None
broker = importlib.util.module_from_spec(spec)
loader.exec_module(broker)


@unittest.skipUnless(sys.platform == "linux", "Linux peer credentials")
class ProtocolTests(unittest.TestCase):
    def exchange(self, payload: bytes):
        server, client = socket.socketpair()
        with server, client:
            client.sendall(payload)
            client.shutdown(socket.SHUT_WR)
            with patch.object(broker, "open_url") as opener:
                broker.handle(server, "/fixed/router", [])
                return broker.receive(client, 1), opener.call_args_list

    def test_open_url_has_one_fixed_host_command(self):
        target = "https://example.com/?q=$(touch%20/tmp/nope)&x=1"
        response, calls = self.exchange(
            json.dumps(
                {"version": 1, "operation": "open-url", "target": target}
            ).encode()
            + b"\n"
        )
        self.assertEqual(response, {"version": 1, "ok": True, "result": None})
        self.assertEqual(calls[0].args, (target, "/fixed/router"))

    def test_rejects_invalid_messages_without_invoking_opener(self):
        valid = {"version": 1, "operation": "open-url", "target": "https://example.com"}
        payloads = [
            b"[]\n",
            b"null\n",
            b"garbage\n",
            b"\xff\n",
            b"{}",
            b"{}\n{}\n",
            b"x" * (broker.MAX_MESSAGE_BYTES + 1),
        ] + [
            json.dumps(request).encode() + b"\n"
            for request in (
                {},
                {**valid, "version": True},
                {**valid, "version": 2},
                {**valid, "operation": "workspace"},
                {**valid, "operation": "spawn"},
                {**valid, "command": "sh"},
                {**valid, "env": {"NIRI_SOCKET": "/elsewhere"}},
                {**valid, "target": ["https://example.com"]},
                {**valid, "target": "javascript:alert(1)"},
                {**valid, "target": "--remote-debugging-port=9222"},
            )
        ]
        for payload in payloads:
            with self.subTest(payload=payload[:100]):
                response, calls = self.exchange(payload)
                self.assertIs(response["ok"], False)
                self.assertEqual(calls, [])

    def test_fragmented_message(self):
        server, client = socket.socketpair()
        with server, client:

            def write():
                for part in (b'{"version":', b'1,"ok":true}', b"\n"):
                    server.sendall(part)

            worker = threading.Thread(target=write)
            worker.start()
            self.assertEqual(broker.receive(client, 1), {"version": 1, "ok": True})
            worker.join(timeout=1)

    def test_read_deadline(self):
        server, client = socket.socketpair()
        with server, client:
            client.sendall(b"{")
            with self.assertRaises((TimeoutError, ValueError)):
                broker.receive(server, 0.01)

    def test_disconnected_client_does_not_crash_handler(self):
        server, client = socket.socketpair()
        client.close()
        with server:
            broker.handle(server, "/unused", [])

    def test_wrong_uid_is_rejected(self):
        server, client = socket.socketpair()
        with server, client, patch.object(broker.os, "getuid", return_value=-1):
            broker.handle(server, "/unused", [])
            self.assertIn("UID", broker.receive(client, 1)["error"])

    def test_nonzero_opener_status_is_an_error(self):
        with patch.object(broker.subprocess, "Popen") as popen:
            popen.return_value.__enter__.return_value.wait.return_value = 1
            with self.assertRaisesRegex(ValueError, "opener failed"):
                broker.open_url("https://example.com", "/fixed/router")
            self.assertEqual(
                popen.call_args.args[0], ["/fixed/router", "https://example.com"]
            )

    def test_opener_timeout_terminates_process_group(self):
        with (
            patch.object(broker.subprocess, "Popen") as popen,
            patch.object(broker.os, "killpg") as kill,
        ):
            process = popen.return_value.__enter__.return_value
            process.pid = 123
            process.wait.side_effect = [subprocess.TimeoutExpired("router", 40), 0]
            with self.assertRaisesRegex(ValueError, "timed out"):
                broker.open_url("https://example.com", "/fixed/router")
            self.assertEqual(kill.call_count, 2)


class TargetTests(unittest.TestCase):
    def test_web_urls(self):
        for target in ("https://example.com", "http://localhost:3000/path?q=a#b"):
            self.assertEqual(broker.normalize_target(target, []), target)

    def test_bad_targets(self):
        for target in (
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
        ):
            with self.subTest(target=target), self.assertRaises(ValueError):
                broker.normalize_target(target, [])

    def test_only_existing_html_inside_roots(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            root = base / "project"
            root.mkdir()
            page = root / "hello world.html"
            page.write_text("<h1>Test</h1>")
            for target in (str(page), page.as_uri()):
                self.assertEqual(broker.normalize_target(target, [root]), page.as_uri())
            outside = base / "outside.html"
            outside.write_text("outside")
            escape = root / "escape.html"
            escape.symlink_to(outside)
            text = root / "private.txt"
            text.touch()
            folder = root / "directory.html"
            folder.mkdir()
            for target in (outside, escape, text, folder, root / "missing.html"):
                with self.subTest(target=target), self.assertRaises(ValueError):
                    broker.normalize_target(str(target), [root])


@unittest.skipUnless(sys.platform == "linux", "Linux socket activation")
class RoutingTests(unittest.TestCase):
    def test_router_uses_activated_broker_inside_sandbox(self):
        # Simulate systemd FD passing with an isolated socket and fake opener.
        # No real host socket or browser is used, including under SANDBOX=1.
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            endpoint = base / "desktop-broker/broker.sock"
            endpoint.parent.mkdir()
            log = base / "opened"
            opener = base / "opener"
            opener.write_text(
                f"#!/bin/sh\nprintf 'start %s\\n' \"$1\" >> '{log}'\n"
                + f"sleep 0.05\nprintf 'end %s\\n' \"$1\" >> '{log}'\n"
            )
            opener.chmod(0o755)
            environment = {**os.environ, "XDG_RUNTIME_DIR": str(base), "SANDBOX": "1"}
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
                        str(opener),
                    ],
                    pass_fds=(fd,),
                    env=environment,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.PIPE,
                )
                try:
                    targets = ["https://example.com/one", "http://localhost:3000/two"]

                    def click(target: str):
                        return subprocess.run(
                            ["bash", str(ROOT / "bin/niri-open-url"), target],
                            env=environment,
                            capture_output=True,
                            text=True,
                            timeout=5,
                        )

                    with ThreadPoolExecutor(max_workers=2) as pool:
                        for result in pool.map(click, targets):
                            self.assertEqual(result.returncode, 0, result.stderr)
                    calls = log.read_text().splitlines()
                    self.assertEqual(len(calls), 4)
                    self.assertCountEqual(
                        calls[::2], [f"start {target}" for target in targets]
                    )
                    # Both clients may connect at once, but their focus/paste
                    # operations must finish in pairs, never interleave.
                    for start, end in zip(calls[::2], calls[1::2]):
                        self.assertEqual(end, start.replace("start ", "end ", 1))
                finally:
                    process.terminate()
                    process.communicate(timeout=5)

    def test_unavailable_broker_does_not_fall_back_to_helium(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            helium = base / "helium"
            helium.write_text(
                "#!/bin/sh\necho 'unexpected browser launch' >&2\nexit 99\n"
            )
            helium.chmod(0o755)
            result = subprocess.run(
                ["bash", str(ROOT / "bin/niri-open-url"), "https://example.com"],
                env={
                    **os.environ,
                    "SANDBOX": "1",
                    "XDG_RUNTIME_DIR": str(base),
                    "PATH": f"{base}:{os.environ['PATH']}",
                },
                capture_output=True,
                text=True,
                timeout=5,
            )
            self.assertEqual(result.returncode, 1)
            self.assertIn("broker unavailable", result.stderr)
            self.assertNotIn("unexpected browser launch", result.stderr)

    def test_server_refuses_sandbox_and_missing_activation(self):
        for sandbox in ("1", ""):
            result = subprocess.run(
                [sys.executable, "-I", str(SCRIPT), "serve", "--opener", "/unused"],
                env={
                    **os.environ,
                    "SANDBOX": sandbox,
                    "LISTEN_PID": "",
                    "LISTEN_FDS": "",
                },
                capture_output=True,
                text=True,
                timeout=5,
            )
            self.assertEqual(result.returncode, 1)
            self.assertIn("host" if sandbox else "systemd", result.stderr)
