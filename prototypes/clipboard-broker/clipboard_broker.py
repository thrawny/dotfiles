#!/usr/bin/env python3
"""PROTOTYPE: image-only host clipboard broker and wl-paste client."""

from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import sys
from pathlib import Path

ALLOWED_IMAGE_TYPES = {
    "image/png",
    "image/jpeg",
    "image/jpg",
    "image/webp",
    "image/gif",
    "image/bmp",
}
MAX_IMAGE_BYTES = 20 * 1024 * 1024
MAX_REQUEST_BYTES = 8192


def send_response(
    connection: socket.socket, *, data: bytes = b"", error: str | None = None
) -> None:
    header = {"ok": error is None, "length": len(data)}
    if error is not None:
        header["error"] = error
    connection.sendall(json.dumps(header).encode() + b"\n" + data)


def read_request(connection: socket.socket) -> dict[str, object]:
    request = bytearray()
    while b"\n" not in request:
        chunk = connection.recv(1024)
        if not chunk:
            raise ValueError("request ended before newline")
        request.extend(chunk)
        if len(request) > MAX_REQUEST_BYTES:
            raise ValueError("request is too large")
    line, _, _ = request.partition(b"\n")
    value = json.loads(line)
    if not isinstance(value, dict):
        raise ValueError("request must be an object")
    return value


def host_clipboard_types(wl_paste: str) -> list[str]:
    result = subprocess.run(
        [wl_paste, "--list-types"],
        check=True,
        capture_output=True,
        timeout=2,
    )
    return [
        mime
        for line in result.stdout.decode(errors="replace").splitlines()
        if (mime := line.strip().split(";", 1)[0].lower()) in ALLOWED_IMAGE_TYPES
    ]


def host_clipboard_image(wl_paste: str, mime: str) -> bytes:
    normalized = mime.split(";", 1)[0].lower()
    if normalized not in ALLOWED_IMAGE_TYPES:
        raise ValueError(f"clipboard MIME type is not allowed: {mime}")
    result = subprocess.run(
        [wl_paste, "--type", mime, "--no-newline"],
        check=True,
        capture_output=True,
        timeout=3,
    )
    if not result.stdout:
        raise ValueError("clipboard image is empty")
    if len(result.stdout) > MAX_IMAGE_BYTES:
        raise ValueError(f"clipboard image exceeds {MAX_IMAGE_BYTES} bytes")
    return result.stdout


def handle_request(connection: socket.socket, wl_paste: str) -> None:
    try:
        request = read_request(connection)
        operation = request.get("operation")
        if operation == "list-types":
            types = host_clipboard_types(wl_paste)
            print(f"list-types -> {types}", flush=True)
            send_response(connection, data=("\n".join(types) + "\n").encode())
        elif operation == "read":
            mime = request.get("mime")
            if not isinstance(mime, str):
                raise ValueError("read requires a MIME type")
            data = host_clipboard_image(wl_paste, mime)
            print(f"read {mime} -> {len(data)} bytes", flush=True)
            send_response(connection, data=data)
        else:
            raise ValueError(f"unsupported operation: {operation}")
    except Exception as error:
        print(f"request failed: {error}", file=sys.stderr, flush=True)
        send_response(connection, error=str(error))


def run_broker(socket_path: Path, wl_paste: str) -> None:
    socket_path.parent.mkdir(parents=True, exist_ok=True)
    socket_path.unlink(missing_ok=True)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(socket_path))
    os.chmod(socket_path, 0o600)
    server.listen(8)
    print(f"clipboard broker listening on {socket_path}", flush=True)
    try:
        while True:
            connection, _ = server.accept()
            with connection:
                handle_request(connection, wl_paste)
    finally:
        server.close()
        socket_path.unlink(missing_ok=True)


def client_request(socket_path: Path, request: dict[str, object]) -> bytes:
    connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    connection.connect(str(socket_path))
    connection.sendall(json.dumps(request).encode() + b"\n")
    response = bytearray()
    while b"\n" not in response:
        chunk = connection.recv(1024)
        if not chunk:
            raise RuntimeError("broker response ended before header")
        response.extend(chunk)
    line, _, body = response.partition(b"\n")
    header = json.loads(line)
    length = int(header.get("length", 0))
    while len(body) < length:
        chunk = connection.recv(min(65536, length - len(body)))
        if not chunk:
            raise RuntimeError("broker response ended before body")
        body.extend(chunk)
    if not header.get("ok"):
        raise RuntimeError(str(header.get("error", "clipboard broker failed")))
    return bytes(body[:length])


def parse_wl_paste_args(arguments: list[str]) -> dict[str, object]:
    if "--list-types" in arguments or "-l" in arguments:
        return {"operation": "list-types"}
    for index, argument in enumerate(arguments):
        if argument in {"--type", "-t"} and index + 1 < len(arguments):
            return {"operation": "read", "mime": arguments[index + 1]}
        if argument.startswith("--type="):
            return {"operation": "read", "mime": argument.split("=", 1)[1]}
    raise ValueError("prototype wl-paste requires --list-types, -l, or --type MIME")


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    broker = subparsers.add_parser("broker")
    broker.add_argument("--socket", type=Path, required=True)
    broker.add_argument("--wl-paste", default="/run/current-system/sw/bin/wl-paste")
    client = subparsers.add_parser("client")
    client.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    if args.command == "broker":
        run_broker(args.socket, args.wl_paste)
        return

    socket_value = os.environ.get("CLIPBOARD_BROKER_SOCKET")
    if not socket_value:
        raise SystemExit("CLIPBOARD_BROKER_SOCKET is not set")
    try:
        arguments = (
            args.arguments[1:] if args.arguments[:1] == ["--"] else args.arguments
        )
        data = client_request(Path(socket_value), parse_wl_paste_args(arguments))
    except Exception as error:
        print(f"wl-paste broker: {error}", file=sys.stderr)
        raise SystemExit(1) from error
    sys.stdout.buffer.write(data)


if __name__ == "__main__":
    main()
