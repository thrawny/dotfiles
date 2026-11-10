"""The Herdr TUI backend: workers in Herdr panes, driven by the herdr CLI."""

from __future__ import annotations

import json
import os
import shutil
import socket
import subprocess
from contextlib import suppress
from pathlib import Path
from typing import Any

from moto.common import BACKGROUND_WORKSPACE, MotoError, run


def herdr_binary() -> str:
    return os.environ.get("HERDR_BIN_PATH") or shutil.which("herdr") or "herdr"


def herdr(*args: str, timeout: int = 30) -> dict[str, Any]:
    output = run([herdr_binary(), *args], timeout=timeout)
    try:
        return json.loads(output)["result"]
    except (ValueError, KeyError, TypeError) as error:
        raise MotoError(f"herdr {' '.join(args[:2])} returned no result") from error


def socket_path() -> str:
    return os.environ.get("HERDR_SOCKET_PATH") or os.path.expanduser(
        "~/.config/herdr/herdr.sock"
    )


def herdr_up() -> bool:
    """Whether a Herdr server may be up: its socket exists."""
    return os.path.exists(socket_path())


def herdr_request(method: str, params: dict[str, Any]) -> dict[str, Any]:
    """One socket API call, for methods the herdr CLI has no command for."""
    path = socket_path()
    request = {"id": method, "method": method, "params": params}
    try:
        with socket.socket(socket.AF_UNIX) as sock:
            sock.settimeout(10)
            sock.connect(path)
            sock.sendall((json.dumps(request) + "\n").encode())
            reply = json.loads(sock.makefile().readline() or "{}")
    except (OSError, ValueError) as error:
        raise MotoError(f"herdr {method}: {error}") from error
    if "result" not in reply:
        raise MotoError(f"herdr {method}: {reply.get('error') or 'no result'}")
    return reply["result"]


def agents() -> dict[str, dict[str, Any]]:
    """Herdr's agents by pane id."""
    return {a["pane_id"]: a for a in herdr("agent", "list")["agents"]}


def prompt(name: str, _terminal: str, text: str) -> None:
    # moto tell and the watch reach a worker by its Herdr name.
    herdr("agent", "prompt", name, text)


def screen(terminal: str) -> str:
    return run([herdr_binary(), "pane", "read", terminal, "--source", "visible"])


def rename(terminal: str, name: str | None) -> None:
    herdr("agent", "rename", terminal, *([name] if name else ["--clear"]))


def name_tab(tab: str) -> None:
    herdr("tab", "rename", tab, "claude")


def close_tab(tab: str) -> None:
    try:
        herdr("tab", "close", tab)
    except MotoError:
        pass  # the tab is already gone


def checkout_workspace(path: str) -> str | None:
    """The Herdr workspace opened on this checkout, if any.

    The background workspace never counts: its long-running tabs often sit in a
    repo's main checkout, and Herdr may record that checkout as its own.
    """
    workspaces = [
        w
        for w in herdr("workspace", "list")["workspaces"]
        if w.get("label") != BACKGROUND_WORKSPACE
    ]
    for workspace in workspaces:
        worktree: dict[str, Any] = workspace.get("worktree") or {}
        if worktree.get("checkout_path") == path:
            return workspace["workspace_id"]
    # `workspace create --cwd` records no checkout, so fall back to a pane
    # there, in the workspace named after the folder first.
    folder = Path(path).name
    labels = {w["workspace_id"]: w.get("label") for w in workspaces}
    found = [
        pane["workspace_id"]
        for pane in herdr("pane", "list")["panes"]
        if pane.get("cwd") == path and pane.get("workspace_id") in labels
    ]
    found.sort(key=lambda workspace_id: labels[workspace_id] != folder)
    return found[0] if found else None


def others_in(tab: str, top: str) -> bool | None:
    try:
        panes = herdr("pane", "list")["panes"]
    except MotoError:
        return None
    for pane in panes:
        if pane.get("tab_id") == tab:
            continue
        for key in ("cwd", "foreground_cwd"):
            if (folder := pane.get(key)) and Path(folder).is_relative_to(top):
                return True
    return False


def remove_worktree(_tab: str, path: str, repo: str, force: bool) -> None:
    """Remove the worktree with its Herdr workspace, or with git when no
    workspace is open on it."""
    flags = ["--force"] if force else []
    if workspace := checkout_workspace(path):
        herdr("worktree", "remove", "--workspace", workspace, *flags, timeout=120)
    elif os.path.isdir(path):
        run(["git", "worktree", "remove", *flags, path], cwd=repo, timeout=120)


def notify(text: str) -> None:
    with suppress(MotoError, OSError, subprocess.TimeoutExpired):
        herdr("notification", "show", text, "--sound", "none")


def put_first(workspace: str) -> None:
    """Make this workspace the top of the sidebar, so its agent is number 1."""
    herdr_request("workspace.move", {"workspace_id": workspace, "insert_index": 0})


def focus_driver(
    home: Path, role_env: dict[str, str], plugin_dir: Path, driver_pane: str | None
) -> None:
    """Focus the driver, starting it in home when no workspace is open there."""
    workspace = checkout_workspace(str(home))
    if workspace is None:
        env = [arg for k, v in role_env.items() for arg in ("--env", f"{k}={v}")]
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
                str(plugin_dir),
                timeout=90,
            )
        except MotoError:
            pass  # a first start stops at Claude's trust prompt, which is now in view
        name_tab(pane["tab_id"])
    put_first(workspace)
    herdr("workspace", "focus", workspace)
    found = [
        a
        for a in herdr("agent", "list")["agents"]
        if a.get("workspace_id") == workspace
    ]
    # Workers with a role may share the driver's workspace, so it comes first.
    found.sort(key=lambda a: (a["pane_id"] != driver_pane, a.get("name") != "driver"))
    if found:
        # Focusing the agent alone leaves the client on its current tab.
        herdr("tab", "focus", found[0]["tab_id"])
        herdr("agent", "focus", found[0]["pane_id"])


def pin(home: Path) -> None:
    if workspace := checkout_workspace(str(home)):
        put_first(workspace)
