"""Image-only clipboard protocol, bounded reads, and wl-paste compatibility."""

import base64
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from unittest.mock import patch

from tests.test_desktop_broker import ROOT, SCRIPT, broker

PI_CLIPBOARD = (
    ROOT
    / "config/pi/node_modules/@earendil-works/pi-coding-agent/dist/utils/clipboard-image.js"
)

PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aO1sAAAAASUVORK5CYII="
)


class ClipboardProtocolTests(unittest.TestCase):
    def test_binary_can_share_header_packet_and_contain_newlines(self):
        image = PNG + b"\n\x00\xff"
        server, client = socket.socketpair()
        with server, client:
            broker.send(server, {"version": 1, "ok": True}, image)
            header, data = broker.receive_frame(
                client, 1, body_limit=broker.MAX_IMAGE_BYTES
            )
            self.assertEqual(header["length"], len(image))
            self.assertEqual(data, image)

    def test_fragmented_binary(self):
        server, client = socket.socketpair()
        with server, client:

            def write():
                server.sendall(b'{"length":3}\n')
                for part in (b"a", b"\n", b"b"):
                    server.sendall(part)

            thread = threading.Thread(target=write)
            thread.start()
            _, data = broker.receive_frame(client, 1, body_limit=3)
            thread.join(timeout=1)
            self.assertEqual(data, b"a\nb")

    def test_invalid_or_oversized_binary_lengths(self):
        for length in (-1, True, "3", 1.5, broker.MAX_IMAGE_BYTES + 1):
            server, client = socket.socketpair()
            with self.subTest(length=length), server, client:
                server.sendall(json.dumps({"length": length}).encode() + b"\n")
                with self.assertRaises(ValueError):
                    broker.receive_frame(client, 1, body_limit=broker.MAX_IMAGE_BYTES)

    def test_truncated_binary_is_not_returned(self):
        server, client = socket.socketpair()
        with server, client:
            server.sendall(b'{"length":10}\nabc')
            server.shutdown(socket.SHUT_WR)
            with self.assertRaisesRegex(ValueError, "completion"):
                broker.receive_frame(client, 1, body_limit=10)

    def test_requests_cannot_have_a_body(self):
        server, client = socket.socketpair()
        with server, client:
            server.sendall(b'{"length":1}\nx')
            with self.assertRaises(ValueError):
                broker.receive(client, 1)

    def test_types_hide_text_svg_and_arbitrary_metadata(self):
        offered = (
            b"text/plain\nimage/png\nimage/svg+xml\nimage/jpeg\nimage/png\nSECRET\n"
        )
        with patch.object(broker, "clipboard_output", return_value=offered):
            self.assertEqual(
                broker.clipboard_types("/fixed/wl-paste"), ["image/png", "image/jpeg"]
            )
        with patch.object(broker, "clipboard_output", return_value=b"text/plain\n"):
            self.assertEqual(broker.clipboard_types("/fixed/wl-paste"), [])

    def test_read_is_explicitly_typed_and_binary(self):
        with patch.object(broker, "clipboard_output", return_value=PNG) as capture:
            self.assertEqual(
                broker.clipboard_image("/fixed/wl-paste", "image/png"), PNG
            )
            capture.assert_called_once_with(
                "/fixed/wl-paste",
                ["--type", "image/png", "--no-newline"],
                broker.MAX_IMAGE_BYTES,
            )

    def test_unsafe_mimes_never_invoke_host_reader(self):
        with patch.object(broker, "clipboard_output") as capture:
            for mime in (
                None,
                list[object](),
                "text/plain",
                "image/svg+xml",
                "image",
                "--watch",
                "image/png\ntext/plain",
            ):
                with self.subTest(mime=mime), self.assertRaises(ValueError):
                    broker.clipboard_image("/fixed/wl-paste", mime)
            capture.assert_not_called()

    def test_empty_images_are_errors(self):
        with patch.object(broker, "clipboard_output", return_value=b""):
            with self.assertRaisesRegex(ValueError, "empty"):
                broker.clipboard_image("/fixed/wl-paste", "image/png")

    def test_clipboard_schema_rejects_extra_fields(self):
        with (
            patch.object(broker, "clipboard_types") as types,
            patch.object(broker, "clipboard_image") as image,
        ):
            for request in (
                {"operation": "clipboard-image-types", "command": "sh"},
                {
                    "operation": "clipboard-image-read",
                    "mime": "image/png",
                    "primary": True,
                },
                {"operation": "clipboard-image-read"},
            ):
                with self.subTest(request=request), self.assertRaises(ValueError):
                    broker.dispatch(
                        {"version": 1, **request}, "/unused", [], "/fixed/wl-paste"
                    )
            types.assert_not_called()
            image.assert_not_called()


@unittest.skipUnless(sys.platform == "linux", "Linux clipboard reader")
class ClipboardCaptureTests(unittest.TestCase):
    def test_capture_bounds_bytes_before_buffering_everything(self):
        with tempfile.TemporaryDirectory() as directory:
            helper = Path(directory) / "producer"
            helper.write_text(
                f"#!{sys.executable}\nimport os\nwhile True: os.write(1, b'x' * 65536)\n"
            )
            helper.chmod(0o755)
            with self.assertRaisesRegex(ValueError, "size limit"):
                broker.clipboard_output(str(helper), [], 1024)

    def test_capture_kills_stalled_reader(self):
        with tempfile.TemporaryDirectory() as directory:
            helper = Path(directory) / "producer"
            helper.write_text(f"#!{sys.executable}\nimport time\ntime.sleep(10)\n")
            helper.chmod(0o755)
            with patch.object(broker, "CLIPBOARD_TIMEOUT", 0.05):
                with self.assertRaisesRegex(ValueError, "timed out"):
                    broker.clipboard_output(str(helper), [], 1024)

    def test_failed_reader_does_not_return_partial_data_or_stderr(self):
        with tempfile.TemporaryDirectory() as directory:
            helper = Path(directory) / "producer"
            helper.write_text("#!/bin/sh\nprintf 'partial'; echo SECRET >&2; exit 1\n")
            helper.chmod(0o755)
            with self.assertRaisesRegex(ValueError, "unavailable") as raised:
                broker.clipboard_output(str(helper), [], 1024)
            self.assertNotIn("SECRET", str(raised.exception))


@dataclass(frozen=True)
class ClipboardFixture:
    environment: dict[str, str]
    log: Path
    image: Path

    def paste(self, *arguments: str):
        return subprocess.run(
            ["wl-paste", *arguments],
            env=self.environment,
            capture_output=True,
            timeout=5,
        )


@contextmanager
def running_clipboard():
    with (
        tempfile.TemporaryDirectory() as directory,
        socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener,
    ):
        base = Path(directory)
        endpoint = base / "desktop-broker/broker.sock"
        endpoint.parent.mkdir()
        log = base / "clipboard-calls"
        image = base / "clipboard.png"
        image.write_bytes(PNG)
        clipboard = base / "host-wl-paste"
        clipboard.write_text(
            f"#!{sys.executable}\nimport json, sys\nfrom pathlib import Path\n"
            + f"with open({str(log)!r}, 'a') as log: log.write(json.dumps(sys.argv[1:]) + '\\n')\n"
            + "if sys.argv[1:] == ['--list-types']: print('text/plain\\nimage/png')\n"
            + f"elif sys.argv[1:] == ['--type', 'image/png', '--no-newline']: sys.stdout.buffer.write(Path({str(image)!r}).read_bytes())\n"
            + "else: sys.exit(1)\n"
        )
        clipboard.chmod(0o755)
        # Simulate the sandbox-only wl-paste mount. Neither display is usable.
        (base / "wl-paste").symlink_to(ROOT / "bin/sandbox-wl-paste")
        environment = {
            **os.environ,
            "SANDBOX": "1",
            "XDG_RUNTIME_DIR": str(base),
            "WAYLAND_DISPLAY": "missing-wayland",
            "DISPLAY": "",
            "PATH": f"{base}:{ROOT / 'bin'}:{os.environ['PATH']}",
        }
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
                "/unused",
                "--wl-paste",
                str(clipboard),
            ],
            pass_fds=(fd,),
            env=environment,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        try:
            yield ClipboardFixture(environment, log, image)
        finally:
            process.terminate()
            process.communicate(timeout=5)


@unittest.skipUnless(sys.platform == "linux", "Linux socket activation")
class ClipboardRoutingTests(unittest.TestCase):
    def test_pi_and_claude_flags_round_trip_binary(self):
        with running_clipboard() as fixture:
            for arguments in (("--list-types",), ("-l",)):
                result = fixture.paste(*arguments)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, b"image/png\n")
            for arguments in (
                ("--type", "image/png", "--no-newline"),
                ("-t", "image/png", "-n"),
                ("--type=image/png",),
            ):
                result = fixture.paste(*arguments)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, PNG)
            calls = [json.loads(line) for line in fixture.log.read_text().splitlines()]
            self.assertEqual(
                calls,
                [["--list-types"]] * 2 + [["--type", "image/png", "--no-newline"]] * 3,
            )

    @unittest.skipUnless(
        shutil.which("node") and PI_CLIPBOARD.is_file(), "Pi dependencies unavailable"
    )
    def test_pi_image_reader_uses_the_shim(self):
        with running_clipboard() as fixture:
            result = subprocess.run(
                [
                    "node",
                    "--input-type=module",
                    "-e",
                    """
                    const { readClipboardImage } = await import(process.env.PI_TEST_CLIPBOARD);
                    const image = await readClipboardImage();
                    if (!image || image.mimeType !== 'image/png') process.exit(1);
                    process.stdout.write(Buffer.from(image.bytes));
                """,
                ],
                env={**fixture.environment, "PI_TEST_CLIPBOARD": PI_CLIPBOARD.as_uri()},
                capture_output=True,
                timeout=10,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, PNG)
            calls = [json.loads(line) for line in fixture.log.read_text().splitlines()]
            self.assertEqual(
                calls, [["--list-types"], ["--type", "image/png", "--no-newline"]]
            )

    def test_text_default_watch_and_primary_are_rejected(self):
        with running_clipboard() as fixture:
            for arguments in (
                (),
                ("--type", "text/plain"),
                ("--watch", "sh"),
                ("--primary", "-t", "image/png"),
            ):
                result = fixture.paste(*arguments)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, b"")
            self.assertFalse(fixture.log.exists())

    def test_unavailable_broker_never_falls_back_to_wayland(self):
        with running_clipboard() as fixture:
            fixture.environment["XDG_RUNTIME_DIR"] += "/missing"
            result = fixture.paste("-t", "image/png")
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stdout, b"")
            self.assertIn(b"broker unavailable", result.stderr)
            self.assertFalse(fixture.log.exists())

    def test_oversized_image_does_not_escape_as_partial_output(self):
        with running_clipboard() as fixture:
            fixture.image.write_bytes(b"x" * (broker.MAX_IMAGE_BYTES + 1))
            result = fixture.paste("-t", "image/png")
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stdout, b"")
            self.assertIn(b"size limit", result.stderr)
            self.assertEqual(fixture.paste("-l").stdout, b"image/png\n")

    def test_server_error_has_no_partial_image(self):
        with running_clipboard() as fixture:
            fixture.image.write_bytes(b"")
            result = fixture.paste("-t", "image/png")
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stdout, b"")
            self.assertIn(b"empty", result.stderr)
            self.assertEqual(fixture.paste("-l").stdout, b"image/png\n")
