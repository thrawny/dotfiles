"""The herdr-core backend: workers in hc terminals, shown by the Herdr app.

hc knows terminals, not workspaces or tabs. The app places a terminal by its
herdr.space and herdr.tab labels, and drives the window through
`herdr-app do`. moto keeps a task's name in the moto.name label, because hc
names are fixed at start.
"""

from __future__ import annotations

import json
import os
import shutil
from pathlib import Path
from typing import Any

from moto.common import MotoError, run

NAME_LABEL = "moto.name"
SPACE_LABEL = "herdr.space"
TAB_LABEL = "herdr.tab"
# hc's status words, in the words Herdr uses. A turn that ends in an error
# is over all the same.
STATUS = {"error": "done"}


def hc_binary() -> str:
    return os.environ.get("HC_BIN_PATH") or shutil.which("hc") or "hc"


def hc_installed() -> bool:
    return bool(os.environ.get("HC_BIN_PATH") or shutil.which("hc"))


def hc(*args: str, timeout: int = 30) -> str:
    return run([hc_binary(), *args], timeout=timeout)


def rpc(method: str, params: dict[str, Any] | None = None) -> Any:
    """One JSON-RPC call over `hc connect`, for facts the CLI's JSON leaves out."""
    request = {"jsonrpc": "2.0", "id": 1, "method": method, "params": params or {}}
    output = run([hc_binary(), "connect"], stdin=json.dumps(request) + "\n")
    for line in output.splitlines():
        try:
            reply = json.loads(line)
        except ValueError:
            continue
        if reply.get("id") != 1:
            continue
        if "result" not in reply:
            raise MotoError(f"hc {method}: {reply.get('error') or 'no result'}")
        return reply["result"]
    raise MotoError(f"hc {method} returned no result")


def app(command: str, **params: Any) -> None:
    """Run a Herdr app command, such as tab.close."""
    run(["herdr-app", "do", command, json.dumps(params)])


def terminals() -> list[dict[str, Any]]:
    return rpc("terminal.list")["terminals"]


def agent(terminal: dict[str, Any]) -> dict[str, Any] | None:
    """A live hc terminal in the shape of a Herdr agent, or None when no agent
    reports status in it."""
    status: dict[str, Any] = terminal.get("status") or {}
    if terminal.get("state") != "live" or not status.get("app"):
        return None
    labels: dict[str, str] = terminal.get("labels") or {}
    foreground: dict[str, Any] = terminal.get("foreground") or {}
    word = status.get("state") or "unknown"
    return {
        "pane_id": terminal["address"],
        "agent": "claude" if status["app"] == "claude-code" else status["app"],
        "agent_status": STATUS.get(word, word),
        # status_ms moves on every status change, as Herdr's sequence does.
        "state_change_seq": terminal.get("status_ms"),
        "cwd": terminal.get("cwd"),
        "foreground_cwd": foreground.get("cwd"),
        "name": labels.get(NAME_LABEL) or terminal.get("name"),
        "terminal_title_stripped": terminal.get("title"),
        "tab_id": labels.get(TAB_LABEL),
        "workspace_id": labels.get(SPACE_LABEL),
    }


def agents() -> dict[str, dict[str, Any]]:
    found = (agent(t) for t in terminals())
    return {a["pane_id"]: a for a in found if a}


# What tells hc which terminal calls. A send that carries it arrives wrapped
# in an <hc from="t1"> tag, and Claude then runs no slash command in it.
IDENTITY = ("HC_TERMINAL_ID", "HC_TERMINAL_SOCKET", "HC_SCOPE")


def prompt(_name: str, terminal: str, text: str) -> None:
    """Type text into the terminal as plain input, so /handoff and /compact
    run as commands and moto's own tags lead the prompt."""
    env = {k: v for k, v in os.environ.items() if k not in IDENTITY}
    run([hc_binary(), "send", terminal, text], timeout=60, env=env)


def screen(terminal: str) -> str:
    return hc("read", terminal)


def rename(terminal: str, name: str | None) -> None:
    hc("label", terminal, f"{NAME_LABEL}={name or ''}")


def name_tab(tab: str) -> None:
    if tab:
        app("tab.rename", id=tab, name="claude")


def close_tab(tab: str) -> None:
    if not tab:
        return
    try:
        app("tab.close", id=tab, confirmed=True)
    except MotoError:
        pass  # the tab is already gone


def others_in(tab: str, top: str) -> bool | None:
    try:
        found = terminals()
    except MotoError:
        return None
    for terminal in found:
        labels: dict[str, str] = terminal.get("labels") or {}
        if terminal.get("state") != "live" or labels.get(TAB_LABEL) == tab:
            continue
        foreground: dict[str, Any] = terminal.get("foreground") or {}
        for folder in (terminal.get("cwd"), foreground.get("cwd")):
            if folder and Path(folder).is_relative_to(top):
                return True
    return False


def remove_worktree(tab: str, path: str, repo: str, force: bool) -> None:
    """Close the worker's tab, then remove its worktree with git."""
    close_tab(tab)
    if os.path.isdir(path):
        flags = ["--force"] if force else []
        run(["git", "worktree", "remove", *flags, path], cwd=repo, timeout=120)
