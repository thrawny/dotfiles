#!/usr/bin/env python3
"""PROTOTYPE: press Ctrl+V in Pi or Claude and capture terminal output."""

import os
import sys
import time

import pexpect

program = sys.argv[1]
output_path = sys.argv[2]
arguments = {
    "pi": [
        "--no-session",
        "--no-extensions",
        "--no-skills",
        "--no-context-files",
        "--offline",
    ],
    "claude": ["--disable-slash-commands"],
}[program]
environment = os.environ.copy()
environment["PATH"] = (
    f"{os.getcwd()}/prototypes/clipboard-broker/bin:{environment['PATH']}"
)
environment["CLIPBOARD_BROKER_SOCKET"] = (
    f"{os.environ['XDG_RUNTIME_DIR']}/clipboard-broker-prototype.sock"
)
environment["XDG_RUNTIME_DIR"] = "/tmp/clipboard-broker-prototype-no-wayland"
environment["WAYLAND_DISPLAY"] = "missing-wayland-socket"
environment["XDG_SESSION_TYPE"] = "wayland"
environment["PI_OFFLINE"] = "1"
environment.pop("DISPLAY", None)
os.makedirs(environment["XDG_RUNTIME_DIR"], exist_ok=True)

with open(output_path, "wb") as output:
    child = pexpect.spawn(program, arguments, env=environment, dimensions=(40, 140))
    child.logfile = output
    time.sleep(4)
    child.sendcontrol("v")
    time.sleep(3)
    child.sendcontrol("c")
    time.sleep(1)
    child.sendcontrol("c")
    try:
        child.expect(pexpect.EOF, timeout=4)
    except pexpect.ExceptionPexpect:
        child.terminate(force=True)
