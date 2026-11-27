from __future__ import annotations

import argparse
import json
import os
import re
import time
from pathlib import Path
from typing import Any

from moto import backend
from moto.backend import live_agents
from moto.common import MODEL_FLAGS, MotoError, run
from moto.driverstate import driver_session, read_driver
from moto.sessions import last_title, last_turn, session_dir
from moto.store import (
    caller,
    forked,
    mark_seen,
    pane_owner,
    read_tasks,
    record,
    tasks_for_update,
)


def git_checkout(cwd: str) -> tuple[str, str | None, str | None]:
    """The repo a folder belongs to, the branch when the folder is in a linked
    worktree, and the checked-out branch.

    A main checkout gives no linked branch, nor does a detached worktree, so
    close never removes either. A folder outside git is its own repo.
    """
    try:
        top, common, git_dir = run(
            ["git", "rev-parse", "--path-format=absolute", "--show-toplevel"]
            + ["--git-common-dir", "--git-dir"],
            cwd=cwd,
        ).splitlines()
    except (MotoError, ValueError, OSError):
        return cwd, None, None
    try:
        current: str | None = run(
            ["git", "symbolic-ref", "--quiet", "--short", "HEAD"], cwd=cwd
        ).strip()
    except MotoError:
        current = None
    if Path(common) == Path(git_dir):
        return top, None, current
    return str(Path(common).parent), current, current


def adopted_name(
    tasks: dict[str, dict[str, Any]],
    live: dict[str, dict[str, Any]],
    sources: list[str | None],
) -> str:
    """A task name from the first of sources that gives one, unique in moto and Herdr.

    A Jira key wins, as in abc-242 for ABC-242-retry-timeouts, the way the
    driver names its workers. Otherwise the first three words, as in
    widgets-api-notes.
    """
    taken = set(tasks) | {a.get("name") for a in live.values()}
    return name_from(sources, taken)


def name_from(sources: list[str | None], taken: set[str | None]) -> str:
    """A name from the first of sources that gives one, not in taken."""
    base = ""
    for source in sources:
        if not source:
            continue
        if key := re.match(r"[A-Za-z]+-\d+", source):
            base = key.group(0).lower()
        else:
            base = "-".join(re.findall(r"[a-z0-9]+", source.lower())[:3])
        if base:
            break
    if not base[:1].isalpha():
        base = f"session-{base}".rstrip("-")
    base = base[:28]
    name, suffix = base, 2
    while name in taken:
        name, suffix = f"{base}-{suffix}", suffix + 1
    return name


def tracked(
    name: str,
    repo: str,
    branch: str | None,
    pane_id: str,
    agent: dict[str, Any],
    cwd: str,
    title: str | None,
    session: str,
) -> dict[str, Any]:
    """The task record of a session moto takes on in its pane, named in Herdr."""
    # moto tell and the watch reach a worker by its Herdr name.
    backend.rename(pane_id, name)
    backend.name_tab(pane_id, agent["tab_id"])
    now = time.time()
    return {
        "agent": name,
        "repo": repo,
        "branch": branch,
        "pane_id": pane_id,
        "workspace_id": agent["workspace_id"],
        "tab_id": agent["tab_id"],
        "cwd": cwd,
        "title": title,
        "started": now,
        "told": now,
        "report": None,
        "pr": None,
        # The report about to land is news; the pane's state so far is not.
        "seen": {
            "status": agent.get("agent_status"),
            "seq": agent.get("state_change_seq"),
        },
        "session": session,
        # It shares a checkout another session put there, so close removes the
        # checkout only when nobody else works in it.
        "adopted": True,
    }


def fork_name(tasks: dict[str, dict[str, Any]], parent: str) -> str:
    """A name for a fork of parent's session, as in abc-1-fork, unique in moto and Herdr."""
    try:
        names = {a.get("name") for a in live_agents().values()}
    except MotoError:
        names = set()
    taken = set(tasks) | names
    base = f"{parent[:27]}-fork"
    name, suffix = base, 2
    while name in taken:
        name, suffix = f"{base}-{suffix}", suffix + 1
    return name


def cmd_fork(args: argparse.Namespace) -> int:
    """For fork-window, run in the pane of the session it forks.

    Without --pane, print the task a fork of this pane's worker takes, as JSON
    with the worker's model and effort, or {} when no task owns the pane, as
    for the driver: that fork stays outside moto. With --pane, record the task
    once Herdr lists Claude in the fork's pane. Claude runs no SessionStart
    hook when a fork starts, so fork-window picks the session id and passes it.
    """
    tasks = read_tasks()
    parent = caller(tasks)
    if not args.pane:
        if parent is None:
            print("{}")
            return 0
        named = {"parent": parent, "name": fork_name(tasks, parent)}
        named |= {f: tasks[parent][f] for f in MODEL_FLAGS if tasks[parent].get(f)}
        print(json.dumps(named))
        return 0
    if parent is None or not args.name or not args.session:
        raise MotoError(
            "moto fork --pane takes --name and --session, from a worker's pane"
        )
    deadline = time.monotonic() + args.wait
    while (live_agents().get(args.pane) or {}).get("agent") != "claude":
        if time.monotonic() > deadline:
            raise MotoError(f"No Claude agent in {args.pane} after {args.wait}s")
        time.sleep(1)
    with tasks_for_update() as tasks:
        if owner := pane_owner(tasks, args.pane):
            raise MotoError(f"Pane {args.pane} belongs to {owner}")
        name = adopt_fork(tasks, args.pane, args.session, args.name, parent)
    if not name:
        raise MotoError(f"No Claude agent in {args.pane}")
    print(f"The fork is the moto task {name}; the user owns it.")
    return 0


def adopt_fork(
    tasks: dict[str, dict[str, Any]],
    pane_id: str,
    session: str,
    name: str,
    parent: str,
) -> str | None:
    """Make a fork of a worker a task of its own, as moto spawn --to-driver would.

    The user forked it and owns it from the start. Its reports reach the
    driver, and requested_by names the worker it forked from. It keeps that
    worker's flow, model, effort and role, and shares its checkout.
    """
    live = live_agents()
    agent = live.get(pane_id)
    if not agent or agent.get("agent") != "claude":
        return None
    taken = set(tasks) | {a.get("name") for p, a in live.items() if p != pane_id}
    if name in taken:
        name = fork_name(tasks, parent)
    source = tasks.get(parent) or {}
    cwd = agent.get("cwd") or os.getcwd()
    repo, branch, _ = git_checkout(cwd)
    task = tracked(
        name, repo, branch, pane_id, agent, cwd, source.get("title"), session
    )
    task |= {
        "owner": "user",
        "owned_since": task["started"],
        "requested_by": parent,
    }
    for field in ("flow", "role", *MODEL_FLAGS):
        if value := source.get(field):
            task[field] = value
    tasks[name] = task
    record(
        "fork",
        name,
        repo=repo,
        branch=branch,
        worktree=cwd if branch else None,
        pane_id=pane_id,
        session=session,
        requested_by=parent,
        flow=task.get("flow"),
        owner="user",
    )
    return name


def adopt(tasks: dict[str, dict[str, Any]], pane_id: str | None) -> str | None:
    """Make the Claude session in this pane a task, or None when it may not be one.

    The user started it by hand, so moto takes what it finds: the pane, tab and
    workspace from Herdr, the repo and branch from the checkout Claude runs in.
    The driver's own pane stays untracked, like a pane outside Herdr or without
    Claude; main refuses a fork before this runs. A session a task already
    owns, resumed in a pane the SessionStart hook missed, moves its task here
    rather than becoming a second one.
    """
    session = os.environ.get("CLAUDE_CODE_SESSION_ID")
    if not pane_id or not session or forked():
        return None
    try:
        live = live_agents()
    except MotoError:
        return None
    agent = live.get(pane_id) or {}
    # The pane's own cwd, where Claude started; foreground_cwd moves with programs.
    cwd = agent.get("cwd") or os.getcwd()
    if agent.get("agent") != "claude" or (
        read_driver().get("pane_id") == pane_id or driver_session(cwd)
    ):
        return None
    for name, task in tasks.items():
        if task.get("session") == session and not task.get("snoozed"):
            attach(tasks, name, pane_id, live)
            return name
    repo, branch, current = git_checkout(cwd)
    path = session_dir(cwd) / f"{session}.jsonl"
    title = last_title(path) if path.is_file() else None
    named = agent.get("name")
    name = (
        named
        if named and named not in tasks
        else adopted_name(
            tasks,
            live,
            [
                branch,
                title,
                agent.get("terminal_title_stripped"),
                current,
                Path(repo).name,
            ],
        )
    )
    tasks[name] = tracked(name, repo, branch, pane_id, agent, cwd, title, session)
    record(
        "adopt",
        name,
        repo=repo,
        branch=branch,
        worktree=cwd if branch else None,
        pane_id=pane_id,
        session=session,
        title=title,
    )
    return name


def attach(
    tasks: dict[str, dict[str, Any]],
    name: str,
    pane_id: str,
    live: dict[str, dict[str, Any]],
) -> None:
    """Move a task to another pane, treating what happened there so far as seen."""
    task = tasks[name]
    agent = live[pane_id]
    # The old pane may still carry the name, and Herdr names are unique.
    for other in live.values():
        if other.get("name") == name and other["pane_id"] != pane_id:
            backend.rename(other["pane_id"], None)
    backend.rename(pane_id, name)
    backend.name_tab(pane_id, agent["tab_id"])
    old = task["pane_id"]
    task["pane_id"] = pane_id
    task["workspace_id"] = agent["workspace_id"]
    task["tab_id"] = agent["tab_id"]
    task.pop("closed_at", None)
    mark_seen(task, live)
    turn, _ = last_turn(task, agent)
    task["seen"]["turn"] = turn
    record("attach", name, pane_id=pane_id, previous=old)
