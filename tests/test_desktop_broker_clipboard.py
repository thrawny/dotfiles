"""Image-only clipboard protocol, bounded reads, and wl-paste compatibility."""

import base64
import json
import shutil
import socket
import subprocess
import sys
import threading
from dataclasses import dataclass
from pathlib import Path
from types import ModuleType
from unittest.mock import patch

import pytest

ROOT = Path(__file__).resolve().parents[1]
PI_CLIPBOARD = (
    ROOT
    / "config/pi/node_modules/@earendil-works/pi-coding-agent/dist/utils/clipboard-image.js"
)
LINUX = pytest.mark.skipif(sys.platform != "linux", reason="Linux clipboard reader")
PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aO1sAAAAASUVORK5CYII="
)


def test_binary_can_share_header_packet_and_contain_newlines(
    broker: ModuleType, socket_pair: tuple[socket.socket, socket.socket]
):
    image = PNG + b"\n\x00\xff"
    server, client = socket_pair
    broker.send(server, {"version": 1, "ok": True}, image)
    header, data = broker.receive_frame(client, 1, body_limit=broker.MAX_IMAGE_BYTES)
    assert header["length"] == len(image)
    assert data == image


def test_fragmented_binary(
    broker: ModuleType, socket_pair: tuple[socket.socket, socket.socket]
):
    server, client = socket_pair

    def write():
        server.sendall(b'{"length":3}\n')
        for part in (b"a", b"\n", b"b"):
            server.sendall(part)

    thread = threading.Thread(target=write)
    thread.start()
    try:
        _, data = broker.receive_frame(client, 1, body_limit=3)
        assert data == b"a\nb"
    finally:
        thread.join(timeout=1)


@pytest.mark.parametrize("length", [-1, True, "3", 1.5, 20 * 1024 * 1024 + 1])
def test_invalid_or_oversized_binary_lengths(
    broker: ModuleType, socket_pair: tuple[socket.socket, socket.socket], length: object
):
    server, client = socket_pair
    server.sendall(json.dumps({"length": length}).encode() + b"\n")
    with pytest.raises(ValueError):
        broker.receive_frame(client, 1, body_limit=broker.MAX_IMAGE_BYTES)


def test_truncated_binary_is_not_returned(
    broker: ModuleType, socket_pair: tuple[socket.socket, socket.socket]
):
    server, client = socket_pair
    server.sendall(b'{"length":10}\nabc')
    server.shutdown(socket.SHUT_WR)
    with pytest.raises(ValueError, match="completion"):
        broker.receive_frame(client, 1, body_limit=10)


def test_requests_cannot_have_a_body(
    broker: ModuleType, socket_pair: tuple[socket.socket, socket.socket]
):
    server, client = socket_pair
    server.sendall(b'{"length":1}\nx')
    with pytest.raises(ValueError):
        broker.receive(client, 1)


@pytest.mark.parametrize(
    ("offered", "expected"),
    [
        (
            b"text/plain\nimage/png\nimage/svg+xml\nimage/jpeg\nimage/png\nSECRET\n",
            ["image/png", "image/jpeg"],
        ),
        (b"text/plain\n", []),
    ],
)
def test_types_hide_text_svg_and_arbitrary_metadata(
    broker: ModuleType, offered: bytes, expected: list[str]
):
    with patch.object(broker, "clipboard_output", return_value=offered):
        assert broker.clipboard_types("/fixed/wl-paste") == expected


def test_read_is_explicitly_typed_and_binary(broker: ModuleType):
    with patch.object(broker, "clipboard_output", return_value=PNG) as capture:
        assert broker.clipboard_image("/fixed/wl-paste", "image/png") == PNG
        capture.assert_called_once_with(
            "/fixed/wl-paste",
            ["--type", "image/png", "--no-newline"],
            broker.MAX_IMAGE_BYTES,
        )


@pytest.mark.parametrize(
    "mime",
    [
        None,
        [],
        "text/plain",
        "image/svg+xml",
        "image",
        "--watch",
        "image/png\ntext/plain",
    ],
)
def test_unsafe_mimes_never_invoke_host_reader(broker: ModuleType, mime: object):
    with patch.object(broker, "clipboard_output") as capture:
        with pytest.raises(ValueError):
            broker.clipboard_image("/fixed/wl-paste", mime)
        capture.assert_not_called()


def test_empty_images_are_errors(broker: ModuleType):
    with patch.object(broker, "clipboard_output", return_value=b""):
        with pytest.raises(ValueError, match="empty"):
            broker.clipboard_image("/fixed/wl-paste", "image/png")


@pytest.mark.parametrize(
    "message",
    [
        {"operation": "clipboard-image-types", "command": "sh"},
        {"operation": "clipboard-image-read", "mime": "image/png", "primary": True},
        {"operation": "clipboard-image-read"},
    ],
)
def test_clipboard_schema_rejects_extra_fields(
    broker: ModuleType, message: dict[str, object]
):
    with (
        patch.object(broker, "clipboard_types") as types,
        patch.object(broker, "clipboard_image") as image,
    ):
        with pytest.raises(ValueError):
            broker.dispatch({"version": 1, **message}, "/unused", [], "/fixed/wl-paste")
        types.assert_not_called()
        image.assert_not_called()


@LINUX
def test_capture_bounds_bytes_before_buffering_everything(
    broker: ModuleType, tmp_path: Path
):
    helper = tmp_path / "producer"
    helper.write_text(
        f"#!{sys.executable}\nimport os\nwhile True: os.write(1, b'x' * 65536)\n"
    )
    helper.chmod(0o755)
    with pytest.raises(ValueError, match="size limit"):
        broker.clipboard_output(str(helper), [], 1024)


@LINUX
def test_capture_kills_stalled_reader(
    broker: ModuleType, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
):
    helper = tmp_path / "producer"
    helper.write_text(f"#!{sys.executable}\nimport time\ntime.sleep(10)\n")
    helper.chmod(0o755)
    monkeypatch.setattr(broker, "CLIPBOARD_TIMEOUT", 0.05)
    with pytest.raises(ValueError, match="timed out"):
        broker.clipboard_output(str(helper), [], 1024)


@LINUX
def test_failed_reader_does_not_return_partial_data_or_stderr(
    broker: ModuleType, tmp_path: Path
):
    helper = tmp_path / "producer"
    helper.write_text("#!/bin/sh\nprintf 'partial'; echo SECRET >&2; exit 1\n")
    helper.chmod(0o755)
    with pytest.raises(ValueError, match="unavailable") as raised:
        broker.clipboard_output(str(helper), [], 1024)
    assert "SECRET" not in str(raised.value)


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


@pytest.fixture
def clipboard(desktop_host: dict[str, str], tmp_path: Path) -> ClipboardFixture:
    log = tmp_path / "clipboard-calls"
    image = tmp_path / "clipboard.png"
    image.write_bytes(PNG)
    reader = tmp_path / "host-wl-paste"
    reader.write_text(
        f"#!{sys.executable}\nimport json, sys\nfrom pathlib import Path\n"
        + f"with open({str(log)!r}, 'a') as log: log.write(json.dumps(sys.argv[1:]) + '\\n')\n"
        + "if sys.argv[1:] == ['--list-types']: print('text/plain\\nimage/png')\n"
        + f"elif sys.argv[1:] == ['--type', 'image/png', '--no-newline']: sys.stdout.buffer.write(Path({str(image)!r}).read_bytes())\n"
        + "else: sys.exit(1)\n"
    )
    reader.chmod(0o755)
    (tmp_path / "wl-paste").symlink_to(ROOT / "bin/sandbox-wl-paste")
    return ClipboardFixture(desktop_host, log, image)


@pytest.mark.parametrize("arguments", [("--list-types",), ("-l",)])
def test_pi_and_claude_list_flags(
    clipboard: ClipboardFixture, arguments: tuple[str, ...]
):
    result = clipboard.paste(*arguments)
    assert result.returncode == 0, result.stderr
    assert result.stdout == b"image/png\n"
    assert json.loads(clipboard.log.read_text()) == ["--list-types"]


@pytest.mark.parametrize(
    "arguments",
    [
        ("--type", "image/png", "--no-newline"),
        ("-t", "image/png", "-n"),
        ("--type=image/png",),
    ],
)
def test_pi_and_claude_read_flags_round_trip_binary(
    clipboard: ClipboardFixture, arguments: tuple[str, ...]
):
    result = clipboard.paste(*arguments)
    assert result.returncode == 0, result.stderr
    assert result.stdout == PNG
    assert json.loads(clipboard.log.read_text()) == [
        "--type",
        "image/png",
        "--no-newline",
    ]


@pytest.mark.skipif(
    not shutil.which("node") or not PI_CLIPBOARD.is_file(),
    reason="Pi dependencies unavailable",
)
def test_pi_image_reader_uses_the_shim(clipboard: ClipboardFixture):
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
        env={**clipboard.environment, "PI_TEST_CLIPBOARD": PI_CLIPBOARD.as_uri()},
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout == PNG
    calls = [json.loads(line) for line in clipboard.log.read_text().splitlines()]
    assert calls == [["--list-types"], ["--type", "image/png", "--no-newline"]]


@pytest.mark.parametrize(
    "arguments",
    [(), ("--type", "text/plain"), ("--watch", "sh"), ("--primary", "-t", "image/png")],
)
def test_text_default_watch_and_primary_are_rejected(
    clipboard: ClipboardFixture, arguments: tuple[str, ...]
):
    result = clipboard.paste(*arguments)
    assert result.returncode != 0
    assert result.stdout == b""
    assert not clipboard.log.exists()


def test_unavailable_broker_never_falls_back_to_wayland(clipboard: ClipboardFixture):
    clipboard.environment["XDG_RUNTIME_DIR"] += "/missing"
    result = clipboard.paste("-t", "image/png")
    assert result.returncode == 1
    assert result.stdout == b""
    assert b"broker unavailable" in result.stderr
    assert not clipboard.log.exists()


def test_oversized_image_does_not_escape_as_partial_output(
    broker: ModuleType, clipboard: ClipboardFixture
):
    clipboard.image.write_bytes(b"x" * (broker.MAX_IMAGE_BYTES + 1))
    result = clipboard.paste("-t", "image/png")
    assert result.returncode == 1
    assert result.stdout == b""
    assert b"size limit" in result.stderr
    assert clipboard.paste("-l").stdout == b"image/png\n"


def test_server_error_has_no_partial_image(clipboard: ClipboardFixture):
    clipboard.image.write_bytes(b"")
    result = clipboard.paste("-t", "image/png")
    assert result.returncode == 1
    assert result.stdout == b""
    assert b"empty" in result.stderr
    assert clipboard.paste("-l").stdout == b"image/png\n"
