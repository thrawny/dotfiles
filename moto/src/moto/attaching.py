from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from typing import Any

from moto.adopting import attach
from moto.common import MotoError, live_agents
from moto.driverstate import driver_session, read_driver, write_driver
from moto.store import find_task, forked, pane_owner, read_tasks, tasks_for_update


def cmd_attach(args: argparse.Namespace) -> int:
    if args.hook:
        try:
            attach_hook(json.loads(sys.stdin.read() or "{}"))
        except Exception:  # a session start must never fail on moto
            pass
        return 0
    if not args.agent:
        raise MotoError("Name the task to attach, or pass --hook")
    pane_id = args.pane or os.environ.get("HERDR_PANE_ID")
    if not pane_id:
        raise MotoError("Pass --pane, or run it from inside the worker's Herdr pane")
    live = live_agents()
    if (live.get(pane_id) or {}).get("agent") != "claude":
        raise MotoError(f"No live Claude agent in pane {pane_id}")
    with tasks_for_update() as tasks:
        task = find_task(tasks, args.agent)
        if task.get("snoozed"):
            raise MotoError(f"{args.agent} is snoozed; bring it back with moto wake")
        owner = pane_owner(tasks, pane_id)
        if owner == args.agent:
            raise MotoError(f"{args.agent} is already in pane {pane_id}")
        if owner:
            raise MotoError(f"Pane {pane_id} belongs to {owner}")
        attach(tasks, args.agent, pane_id, live)
    print(f"Attached {args.agent} to pane {pane_id}")
    return 0


def driver_elsewhere(pane_id: str) -> bool:
    """Whether the recorded driver pane is another pane, still running Claude.

    A session in MOTO_HOME whose tab lacks MOTO_WORKER passes for the driver
    until spawn records its task, so it must not take a live driver's pane. If
    Herdr cannot answer, the new session takes the pane, as before.
    """
    recorded = read_driver().get("pane_id")
    if not recorded or recorded == pane_id:
        return False
    try:
        agent = live_agents().get(recorded)
    except (MotoError, subprocess.TimeoutExpired):
        return False
    return bool(agent) and agent.get("agent") == "claude"


def attach_hook(payload: dict[str, Any]) -> None:
    """Claude's SessionStart hook, for startup, resume and clear.

    A task's own pane records its Claude session id. A session resumed in a
    pane no task owns moves the task with that session id to the pane. Reads
    tasks.json without the lock first, so the usual case costs no Herdr call.
    A fork gets a session id of its own, and the hook skips it anyway. A clear
    gives the task's own pane a new session, which moto handoff waits for.
    """
    pane_id = os.environ.get("HERDR_PANE_ID")
    session = payload.get("session_id")
    if not pane_id or not session or forked():
        return
    tasks = read_tasks()
    owner = pane_owner(tasks, pane_id)
    if (
        not owner
        and driver_session(payload.get("cwd"))
        and not driver_elsewhere(pane_id)
    ):
        # A pane no task owns that driver_session accepts is the driver. A
        # scheduled job needs this to know where to send what it finds.
        write_driver(pane_id=pane_id, session=session)
    if owner:
        if tasks[owner].get("session") != session:
            with tasks_for_update() as tasks:
                if owner in tasks and tasks[owner]["pane_id"] == pane_id:
                    marker = tasks[owner].get("handoff")
                    if marker and marker.get("old") != session:
                        marker.setdefault("new", session)
                    tasks[owner]["session"] = session
        return
    if not any(
        t.get("session") == session and not t.get("snoozed") for t in tasks.values()
    ):
        return
    # Herdr lists the agent by the time Claude runs this hook.
    live = live_agents()
    if pane_id not in live:
        return
    with tasks_for_update() as tasks:
        name = next(
            (
                n
                for n, t in tasks.items()
                if t.get("session") == session and not t.get("snoozed")
            ),
            None,
        )
        if name and not pane_owner(tasks, pane_id):
            attach(tasks, name, pane_id, live)
