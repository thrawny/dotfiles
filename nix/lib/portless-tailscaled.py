#!/usr/bin/env python3
"""Publish UID-owned loopback previews through the host's Tailscale daemon."""

import argparse
import fcntl
import json
import os
import re
import socket
import socketserver
import struct
import subprocess
import threading
import time
from pathlib import Path
from typing import Any, TypedDict, cast, final


class Reply(TypedDict):
    code: int
    stdout: str
    stderr: str


class Preview(TypedDict):
    uid: int
    target: str


class State(TypedDict):
    previews: dict[str, Preview]
    proxyPorts: dict[str, int]


Config = dict[str, Any]

MAX_REQUEST = 4096
HTTPS_PORTS = {443, *range(8443, 8500)}
READ_COMMANDS = (["version"], ["status", "--json"], ["serve", "status", "--json"])


@final
class PreviewBroker:
    def __init__(self, tailscale: str, state_file: Path, lock_file: Path) -> None:
        self.tailscale = tailscale
        self.state_file = state_file
        self.lock_file = lock_file
        self.mutex = threading.Lock()

    def run(self, args: list[str]) -> Reply:
        result = subprocess.run(
            [self.tailscale, *args],
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
            env={"PATH": "/run/current-system/sw/bin", "HOME": "/var/lib/portless"},
        )
        return {
            "code": result.returncode,
            "stdout": result.stdout,
            "stderr": result.stderr,
        }

    def load(self) -> State:
        if not self.state_file.exists():
            return {"previews": {}, "proxyPorts": {}}
        return cast(State, json.loads(self.state_file.read_text()))

    def save(self, state: State) -> None:
        temporary = self.state_file.with_suffix(".tmp")
        with temporary.open("w") as stream:
            json.dump(state, stream)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.replace(self.state_file)

    def config(self) -> Config:
        result = self.run(["serve", "status", "--json"])
        if result["code"]:
            raise ValueError(result["stderr"] or "Cannot read Tailscale Serve state")
        config = json.loads(result["stdout"])
        if not isinstance(config, dict):
            raise ValueError("Invalid Tailscale Serve state")
        return cast(Config, config)

    @staticmethod
    def matches_preview(config: Config, port: int, target: str) -> bool:
        handlers = [
            web.get("Handlers", {})
            for authority, web in config.get("Web", {}).items()
            if authority.endswith(f":{port}")
        ]
        return handlers == [{"/": {"Proxy": target}}]

    @staticmethod
    def used_ports(config: Config) -> set[int]:
        # Named Services have separate addresses and do not occupy node ports.
        return {int(port) for port in config.get("TCP", {})} | {
            int(authority.rsplit(":", 1)[1]) for authority in config.get("Web", {})
        }

    def execute(self, uid: int, request: object) -> Reply:
        if not isinstance(request, list) or not all(
            isinstance(arg, str) for arg in cast(list[object], request)
        ):
            raise ValueError("Expected an argument list")
        args = cast(list[str], request)
        if args in READ_COMMANDS[:2]:
            return self.run(args)
        if args == ["proxy-port"]:
            with self.mutex:
                state = self.load()
                if str(uid) not in state["proxyPorts"]:
                    reserved = set(state["proxyPorts"].values())
                    for port in range(20000, 30000):
                        if port in reserved:
                            continue
                        with socket.socket() as probe:
                            try:
                                probe.bind(("127.0.0.1", port))
                            except OSError:
                                continue
                        state["proxyPorts"][str(uid)] = port
                        self.save(state)
                        break
                    else:
                        raise ValueError("No local proxy ports available")
                return {
                    "code": 0,
                    "stdout": str(state["proxyPorts"][str(uid)]) + "\n",
                    "stderr": "",
                }

        read_config = args == READ_COMMANDS[2]
        registration = len(args) == 5 and args[:3] == ["serve", "--bg", "--yes"]
        removal = (
            len(args) == 4 and args[:2] == ["serve", "--yes"] and args[-1] == "off"
        )
        if not (read_config or registration or removal):
            raise ValueError(
                "Only private preview registration and cleanup are allowed"
            )
        port = 0
        if not read_config:
            match = re.fullmatch(r"--https=([0-9]+)", args[-2])
            if not match or int(match[1]) not in HTTPS_PORTS:
                raise ValueError("Preview HTTPS ports must be 443 or 8443-8499")
            port = int(match[1])
        if registration:
            match = re.fullmatch(r"http://127\.0\.0\.1:([0-9]+)", args[-1])
            if not match or not 1024 <= int(match[1]) <= 65535:
                raise ValueError(
                    "Preview target must be an unprivileged loopback HTTP port"
                )

        # Share the declarative Serve units' lock. Hold it across read + update,
        # since Serve itself overwrites a route rather than reporting a conflict.
        with self.mutex, self.lock_file.open("a") as lock:
            deadline = time.monotonic() + 5
            while True:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    if time.monotonic() >= deadline:
                        raise ValueError("Tailscale configuration is busy; try again")
                    time.sleep(0.05)
            state = self.load()
            config = self.config()
            if read_config:
                # Failed/interrupted registrations stay reserved until their
                # owner cleans them up. Never reuse them on a failed status read.
                config.setdefault("TCP", {}).update(
                    {
                        key: config.get("TCP", {}).get(key, {})
                        for key in state["previews"]
                    }
                )
                return {"code": 0, "stdout": json.dumps(config), "stderr": ""}
            key = str(port)
            if registration:
                if any(config.get("AllowFunnel", {}).values()):
                    raise ValueError(
                        "Funnel is active on this node; refusing to publish a private preview"
                    )
                if port in self.used_ports(config) or key in state["previews"]:
                    raise ValueError(f"HTTPS port {port} is already in use")
                state["previews"][key] = {"uid": uid, "target": args[-1]}
                # Reserve before mutation: a timeout may still have changed Serve.
                self.save(state)
                result = self.run(args)
                if result["code"] and port not in self.used_ports(self.config()):
                    state["previews"].pop(key)
                    self.save(state)
                return result
            preview = state["previews"].get(key)
            if preview is None:
                if port in self.used_ports(config):
                    raise ValueError("This endpoint is not managed by Portless")
                return {"code": 0, "stdout": "", "stderr": ""}
            if preview["uid"] != uid and uid != 0:
                raise ValueError("This preview belongs to another user")
            if port in self.used_ports(config):
                if not self.matches_preview(config, port, preview["target"]):
                    raise ValueError(
                        "This endpoint was changed outside Portless; refusing cleanup"
                    )
                result = self.run(args)
                if result["code"]:
                    return result
            state["previews"].pop(key)
            self.save(state)
            return {"code": 0, "stdout": "", "stderr": ""}


@final
class Handler(socketserver.StreamRequestHandler):
    def handle(self) -> None:
        self.connection.settimeout(5)
        try:
            _, uid, _ = struct.unpack(
                "3i",
                self.connection.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12),
            )
            request = self.rfile.readline(MAX_REQUEST + 1)
            if len(request) > MAX_REQUEST or not request.endswith(b"\n"):
                raise ValueError("Invalid preview request")
            response = cast(Server, self.server).broker.execute(
                uid, json.loads(request)
            )
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
            response: Reply = {"code": 1, "stdout": "", "stderr": f"{error}\n"}
        try:
            self.wfile.write(json.dumps(response).encode() + b"\n")
        except OSError:
            pass  # An interrupted client must not stop the broker.


@final
class Server(socketserver.ThreadingUnixStreamServer):
    daemon_threads = True

    def __init__(
        self,
        address: str,
        handler: type[socketserver.BaseRequestHandler],
        broker: PreviewBroker,
        bind_and_activate: bool = True,
    ) -> None:
        self.broker = broker
        super().__init__(address, handler, bind_and_activate=bind_and_activate)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tailscale", required=True)
    parser.add_argument(
        "--state-file", default="/var/lib/portless/ownership.json", type=Path
    )
    parser.add_argument(
        "--lock-file", default="/run/lock/dotfiles-tailscale-serve.lock", type=Path
    )
    arguments = parser.parse_args()
    if (
        os.environ.get("LISTEN_PID") != str(os.getpid())
        or os.environ.get("LISTEN_FDS") != "1"
    ):
        parser.error("Requires systemd socket activation")
    broker = PreviewBroker(
        arguments.tailscale, arguments.state_file, arguments.lock_file
    )
    with Server(
        "/run/portless-tailscale.sock", Handler, broker, bind_and_activate=False
    ) as server:
        server.socket.close()
        server.socket = socket.socket(fileno=3)
        server.serve_forever()


if __name__ == "__main__":
    main()
