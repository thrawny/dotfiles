from __future__ import annotations

import argparse
import subprocess
import sys
from contextlib import suppress

from moto.adopting import name_claude_tab
from moto.closing import checkout_workspace
from moto.common import (
    DRIVER_ROLE,
    MOTO_HOME,
    WATCH_MOD,
    MotoError,
    herdr,
    herdr_request,
)
from moto.driverstate import read_driver
from moto.roles import roles_dir


def put_first(workspace: str) -> None:
    """Make this workspace the top of the sidebar, so its agent is number 1."""
    herdr_request("workspace.move", {"workspace_id": workspace, "insert_index": 0})


def cmd_pin(_: argparse.Namespace) -> int:
    """Move the driver's workspace to the top of the sidebar, if it is open."""
    if workspace := checkout_workspace(str(MOTO_HOME.resolve())):
        put_first(workspace)
    return 0


def cmd_focus(_: argparse.Namespace) -> int:
    """Focus the driver session, starting it in its home folder if none is open."""
    home = MOTO_HOME.resolve()
    workspace = checkout_workspace(str(home))
    if workspace is None:
        if not home.is_dir():
            raise MotoError(f"moto home not found: {home}")
        env = driver_env()
        pane = herdr(
            "workspace", "create", "--cwd", str(home), "--label", "moto", *env
        )["root_pane"]
        workspace = pane["workspace_id"]
        try:
            herdr(
                "agent",
                "start",
                "driver",
                "--kind",
                "claude",
                "--pane",
                pane["pane_id"],
                "--",
                "--plugin-dir",
                str(WATCH_MOD),
                timeout=90,
            )
        except MotoError:
            pass  # a first start stops at Claude's trust prompt, which is now in view
        name_claude_tab(pane["tab_id"])
    put_first(workspace)
    herdr("workspace", "focus", workspace)
    agents = [
        a
        for a in herdr("agent", "list")["agents"]
        if a.get("workspace_id") == workspace
    ]
    # Workers with a role may share the driver's workspace, so it comes first.
    pane_id = read_driver().get("pane_id")
    agents.sort(key=lambda a: (a["pane_id"] != pane_id, a.get("name") != "driver"))
    if agents:
        # Focusing the agent alone leaves the client on its current tab.
        herdr("tab", "focus", agents[0]["tab_id"])
        herdr("agent", "focus", agents[0]["pane_id"])
    return 0


def driver_env() -> list[str]:
    """The Herdr arguments that start the driver in its role.

    Until MOTO_HOME has a roles folder, the driver runs on MOTO_HOME's
    CLAUDE.md, and focus says so on each start. Once it has one, a missing
    driver role is a mistake, and focus refuses rather than start a driver
    without instructions.
    """
    path = roles_dir() / f"{DRIVER_ROLE}.md"
    if path.is_file():
        return ["--env", f"MOTO_ROLE={DRIVER_ROLE}"]
    if roles_dir().is_dir():
        raise MotoError(f"role file missing: {path}, so the driver has no role")
    notice = f"moto: no {path}, so the driver starts without a role"
    print(notice, file=sys.stderr)
    with suppress(MotoError, OSError, subprocess.TimeoutExpired):
        herdr("notification", "show", notice, "--sound", "none")
    return []
