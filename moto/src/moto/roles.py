from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any

from moto import backend
from moto.common import (
    CLAUDE_HOME,
    CORE_SKILLS,
    DRIVER_ROLE,
    MOTO_HOME,
    ROLE_NAME,
    WORKER_ENV,
    MotoError,
)
from moto.driverstate import driver_session, read_driver
from moto.store import forked, pane_owner, read_tasks


def roles_dir() -> Path:
    return MOTO_HOME / "roles"


def role_file(role: str) -> Path:
    """The role's file, refusing a role that has none."""
    if not ROLE_NAME.fullmatch(role):
        raise MotoError(f"Role names match {ROLE_NAME.pattern}: {role}")
    path = roles_dir() / f"{role}.md"
    if not path.is_file():
        raise MotoError(f"No role {role}: {path} does not exist")
    return path


def role_folder(repo: str | None) -> Path:
    """Where a session with a role works: MOTO_HOME, or a folder in it.

    A relative --repo names a folder under MOTO_HOME, not a repo under ~/code.
    """
    home = MOTO_HOME.resolve()
    folder = (home / Path(repo).expanduser()).resolve() if repo else home
    if not folder.is_dir() or not folder.is_relative_to(home):
        raise MotoError(f"--role sessions work in a folder of {home}, not {folder}")
    return folder


# Claude Code caps hook context at 10,000 characters; past it, the session gets
# a file path and a 2,000-character preview, and no prompt to read the rest.
ROLE_INLINE_LIMIT = 9_000


def session_role(cwd: Any) -> str | None:
    """This session's role: MOTO_ROLE, else the driver's for the driver.

    MOTO_ROLE is missing from a tab whose shell predates the role. So a pane no
    task owns takes the driver role if it is in MOTO_HOME, the rule that
    records the driver's pane, or is the recorded driver pane. That needs a
    driver role file in MOTO_HOME.
    """
    if role := os.environ.get("MOTO_ROLE"):
        return role
    pane_id = backend.here()
    if not pane_id or os.environ.get(WORKER_ENV) or pane_owner(read_tasks(), pane_id):
        return None
    # The session may have moved out of MOTO_HOME since the pane was recorded.
    if not driver_session(cwd) and read_driver().get("pane_id") != pane_id:
        return None
    return DRIVER_ROLE if (roles_dir() / f"{DRIVER_ROLE}.md").is_file() else None


def role_context(role: str) -> str:
    """What the SessionStart hook hands a session with this role.

    A role that cannot load says so loudly, so the session never carries on
    as if it had instructions it lacks.
    """
    alarm = "; you have no role. Tell the user before anything else."
    if not ROLE_NAME.fullmatch(role):
        return f"MOTO ROLE ERROR: MOTO_ROLE={role!r} is not a role name{alarm}"
    path = roles_dir() / f"{role}.md"
    try:
        text = path.read_text()
    except OSError as error:
        problem = "missing" if isinstance(error, FileNotFoundError) else "unreadable"
        return f"MOTO ROLE ERROR: role file {problem}: {path}{alarm}"
    if len(text) <= ROLE_INLINE_LIMIT:
        return f"Your moto role is {role}. Its instructions, from {path}:\n\n{text}"
    return (
        f"Your moto role is {role}. Its instructions are in {path}, which is"
        + f" {len(text)} characters: too long for a hook to hand over whole."
        + f" Before anything else, before you answer any message, Read {path}"
        + " in full, every line, and follow it as your role. If one Read returns"
        + " only part of the file, read on with offset until its last line."
    )


def cmd_role(args: argparse.Namespace) -> int:
    """Claude's SessionStart hook with --hook; otherwise, name this session's role."""
    if not args.hook:
        if role := session_role(os.getcwd()):
            print(f"{role}: {roles_dir() / f'{role}.md'}")
        else:
            print("No role: MOTO_ROLE is unset, and this is not the driver")
        return 0
    # A fork carries its parent's role in the conversation it copied.
    if forked():
        return 0
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        payload = {}
    if not (role := session_role(payload.get("cwd") or os.getcwd())):
        return 0
    context = role_context(role)
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "SessionStart",
                    "additionalContext": context,
                }
            }
        )
    )
    return 0


def skill_folders() -> list[Path]:
    """Where moto skills live, the folder whose skills win last."""
    return [CORE_SKILLS, MOTO_HOME / "skills"]


def cmd_link(_: argparse.Namespace) -> int:
    """Symlink every skill in the skill folders into Claude's skills folder.

    A link is moto's when it points into a skill folder. moto replaces or
    removes only its own links, so Home Manager's links and anything else
    stay as they are.
    """
    folders = [folder.resolve() for folder in skill_folders()]
    wanted: dict[str, Path] = {}
    for folder in folders:
        for skill in sorted(folder.glob("*/SKILL.md")):
            wanted[skill.parent.name] = skill.parent
    target = CLAUDE_HOME / "skills"
    target.mkdir(parents=True, exist_ok=True)
    changes: list[str] = []
    refused: list[str] = []
    for entry in sorted(target.iterdir()):
        if not entry.is_symlink():
            if entry.name in wanted:
                refused.append(f"{entry} is not a symlink")
            continue
        points_to = entry.readlink()
        if points_to.parent not in folders:
            if entry.name in wanted:
                refused.append(f"{entry} points to {points_to}, not a moto skill")
            continue
        if wanted.get(entry.name) == points_to:
            continue
        entry.unlink()
        if entry.name not in wanted:
            changes.append(f"Removed {entry.name}, which pointed to {points_to}")
    for name, source in wanted.items():
        link = target / name
        if link.is_symlink() or link.exists():
            continue  # already right, or refused above
        link.symlink_to(source, target_is_directory=True)
        changes.append(f"Linked {name} to {source}")
    print("\n".join(changes) or f"All {len(wanted)} moto skills were already linked.")
    for line in refused:
        print(f"moto link: skipped, {line}", file=sys.stderr)
    return 1 if refused else 0
