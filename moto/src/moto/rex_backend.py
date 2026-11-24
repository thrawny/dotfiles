"""The Rex backend: workers in Rex terminal blocks, driven by the rex CLI.

A terminal is a Rex block id such as block:01a2..., and its tab is the Rex
window that holds it. spawn-session starts each worker in a session of its
own, so the Rex sidebar lists one row per worker. Every rex command takes a
block id where it wants a session, so no call here looks up a block's session.

Claude Code reports its state to Rex through the Program Status Protocol, so
the agent status comes from Rex itself. moto keeps a task's name in the
block's label.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
from pathlib import Path
from typing import Any

from moto.common import MotoError, run

AGENTS_SCRIPT = Path(__file__).with_name("rex_agents.lua")
# rex exits with this status when no server answers.
UNREACHABLE = 4
# Labels Rex gives a block that nobody named.
DEFAULT_LABELS = ("shell",)
# Rex's status words, in the words Herdr uses. A turn that ends in an error
# is over all the same.
STATUS = {"error": "done"}
PASTE_START, PASTE_END = "\x1b[200~", "\x1b[201~"


def installed_binary() -> str | None:
    """The rex to run: inside Rex, the one beside the server that runs the
    terminal, which Rex names in REX_BIN_DIR, so client and server match."""
    if path := os.environ.get("REX_BIN_PATH"):
        return path
    folder = os.environ.get("REX_BIN_DIR")
    if folder and os.access(Path(folder) / "rex", os.X_OK):
        return str(Path(folder) / "rex")
    return shutil.which("rex")


def rex_binary() -> str:
    return installed_binary() or "rex"


def rex_installed() -> bool:
    return installed_binary() is not None


def rex(*args: str, timeout: int = 30, stdin: str | None = None) -> str:
    # Never start a server: moto only drives the one its workers run in.
    return run([rex_binary(), "--autostart=false", *args], timeout=timeout, stdin=stdin)


def blocks() -> list[dict[str, Any]]:
    """Every terminal block on the server, or none when no server runs."""
    command = [rex_binary(), "--autostart=false", "do", str(AGENTS_SCRIPT)]
    try:
        result = subprocess.run(
            command, capture_output=True, text=True, timeout=30, check=False
        )
    except FileNotFoundError as error:
        raise MotoError(f"Required executable not found: {command[0]}") from error
    if result.returncode == UNREACHABLE:
        return []
    if result.returncode:
        raise MotoError(result.stderr.strip() or "rex do failed")
    try:
        found = json.loads(result.stdout)
    except ValueError as error:
        raise MotoError("rex do returned no block list") from error
    return found if isinstance(found, list) else []


def label_name(label: str | None) -> str | None:
    """The moto name in a block label, or None for a label Rex chose."""
    if not label or label in DEFAULT_LABELS or label.startswith("Block "):
        return None
    return label


def agent(block: dict[str, Any]) -> dict[str, Any] | None:
    """A terminal block in the shape of a Herdr agent, or None when no
    program in it reports a status as an app."""
    records = block.get("records")
    found = (
        [r for r in records if isinstance(r, dict)] if isinstance(records, list) else []
    )
    record = next((r for r in found if "id" not in r and r.get("app")), None)
    if record is None:
        return None
    child: dict[str, Any] = block.get("child") or {}
    foreground: dict[str, Any] = block.get("foreground") or {}
    word = record.get("state") or "unknown"
    app = record.get("effective_app") or record["app"]
    return {
        "pane_id": block["block_id"],
        "agent": "claude" if app == "claude-code" else app,
        "agent_status": STATUS.get(word, word),
        # updated_at moves on every report, as Herdr's sequence does.
        "state_change_seq": record.get("updated_at"),
        "cwd": child.get("cwd"),
        "foreground_cwd": foreground.get("cwd"),
        "name": label_name(block.get("label")),
        "terminal_title_stripped": block.get("title"),
        "tab_id": block.get("window_id"),
        "workspace_id": block.get("session_id"),
    }


def agents() -> dict[str, dict[str, Any]]:
    found = (agent(b) for b in blocks())
    return {a["pane_id"]: a for a in found if a}


def prompt(_name: str, terminal: str, text: str) -> None:
    """Type the text and press Enter. Several lines go in as one paste, so a
    newline inside them does not submit early."""
    target = ("-s", terminal, "-b", terminal)
    if "\n" in text:
        rex("send", *target, stdin=PASTE_START + text + PASTE_END)
        # Sent at once, a busy Claude can read the Enter as part of the paste.
        time.sleep(0.5)
    else:
        rex("send", *target, stdin=text)
    rex("send-key", *target, "enter")


def screen(terminal: str) -> str:
    return rex("capture", "-s", terminal, "-b", terminal, "--trim")


def rename(terminal: str, name: str | None) -> None:
    # An empty label makes Rex name the block itself again.
    rex("block", "rename", "-s", terminal, terminal, name or "")


def name_tab(terminal: str, tab: str) -> None:
    if tab:
        rex("window", "rename", "-s", terminal, tab, "claude")


def close_tab(terminal: str, tab: str) -> None:
    """Close the worker's window, and its session when nothing else is left
    in it, so the sidebar keeps no empty row."""
    try:
        view = json.loads(rex("window", "ls", "-s", terminal, "--json"))
    except (MotoError, ValueError):
        return  # the block, and with it the session, is already gone
    windows = [w.get("window_id") for w in view.get("windows") or []]
    if windows in ([], [tab]):
        rex("kill", terminal)
    elif tab in windows:
        rex("window", "close", "-s", terminal, tab)


def close_pane(terminal: str, _tab: str) -> None:
    try:
        rex("block", "close", "-s", terminal, terminal)
    except MotoError:
        pass  # the block is already gone


def clear_held_mark(_terminal: str) -> None:
    """Rex never had a held mark."""


def others_in(tab: str, top: str) -> bool | None:
    try:
        found = blocks()
    except MotoError:
        return None
    for block in found:
        if block.get("window_id") == tab:
            continue
        for process in (block.get("child"), block.get("foreground")):
            folder = (process or {}).get("cwd") if isinstance(process, dict) else None
            if folder and Path(folder).is_relative_to(top):
                return True
    return False


def remove_worktree(terminal: str, tab: str, path: str, repo: str, force: bool) -> None:
    """Close the worker's tab, then remove its worktree with git."""
    close_tab(terminal, tab)
    if os.path.isdir(path):
        flags = ["--force"] if force else []
        run(["git", "worktree", "remove", *flags, path], cwd=repo, timeout=120)
