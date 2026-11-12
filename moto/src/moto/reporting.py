from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from collections.abc import Callable
from typing import Any

from moto import backend
from moto.adopting import adopt
from moto.backend import live_agents
from moto.common import (
    ADOPT_KINDS,
    BUSY,
    CHILD_KINDS,
    ENDED_BY_USER,
    HANDOFF_POLL_SECONDS,
    HANDOFF_SESSION_WAIT,
    HANDOFF_STAY,
    HANDOFF_TAKEOFF_WAIT,
    PASS_ON_RULE,
    PR_URL,
    REPORTS_KEPT,
    TURN_OVER,
    UNTRACKED,
    MotoError,
    age,
)
from moto.driverstate import driver_path, read_driver, wake_driver, write_driver
from moto.sessions import last_turn
from moto.store import (
    find_task,
    message_sender,
    read_tasks,
    record,
    tag,
    tasks_for_update,
    user_window,
    with_user,
)


def cmd_report(args: argparse.Namespace) -> int:
    pane_id = backend.here()
    text = " ".join(args.text).strip()
    with tasks_for_update() as tasks:
        if args.agent:
            task = find_task(tasks, args.agent)
        else:
            task = next((t for t in tasks.values() if t["pane_id"] == pane_id), None)
            if task is None and args.kind in ADOPT_KINDS:
                if adopted := adopt(tasks, pane_id):
                    task = tasks[adopted]
                    print(f"moto now tracks this session as {adopted} for the driver.")
            if task is None:
                # Dropped tasks keep the brief that asks for reports.
                print(UNTRACKED)
                return 0
            # The SessionStart hook runs before spawn records the task, so a
            # new worker's session id arrives with its first report.
            if session := os.environ.get("CLAUDE_CODE_SESSION_ID"):
                task["session"] = session
        # A wrap or snooze hands the task to the driver, so the user's earlier
        # prompts no longer count. A child is its parent's whoever types to it.
        talking = (
            args.kind not in ENDED_BY_USER
            and not task.get("parent")
            and with_user(task, None, time.time()) is not None
        )
        # A done while the user talks to the worker is when the driver updates
        # tickets and notes, so it is passed on as if --to-driver were given.
        # question and blocked stay with the user. A child's done is for its
        # parent.
        passes_on = args.to_driver or (args.kind == "done" and talking)
        task["report"] = {"kind": args.kind, "text": text, "at": time.time()}
        if passes_on:
            task["report"]["to_driver"] = True
        # report keeps the last one for moto list. The watch reads reports, so
        # several reports between two watches all reach the driver.
        task["reports"] = [*task.get("reports", []), task["report"]][-REPORTS_KEPT:]
        record(
            "report",
            task["agent"],
            kind=args.kind,
            text=text,
            **({"to_driver": True} if passes_on else {}),
        )
        if (match := PR_URL.search(text)) and match.group(0) != task.get("pr"):
            task["pr"] = match.group(0)
            record("pr", task["agent"], pr=task["pr"])
        parent = task.get("parent")
        host = direct_host(tasks, parent, args.kind, passes_on)
        if host:
            task["report"]["direct"] = True
        name = task["agent"]
    if host:
        send_to_parent(name, host, task["report"])
    if parent and (args.kind in ADOPT_KINDS or args.to_driver):
        print(f"Reported {args.kind} to the driver, and {parent} can read it here.")
    elif parent and host:
        print(f"Sent to {parent}, which started you. {PASS_ON_RULE}")
    elif parent:
        print(
            f"Recorded. {parent} started you, not the driver, so moto delivers it to"
            + f" {parent}'s pane once its turn ends. {PASS_ON_RULE}"
        )
    elif talking and args.kind == "phase":
        print(
            "The user is talking to you in this pane, so moto does not hand you off."
            + " The driver hears of the phase. End your turn with one line that"
            + " names the next phase and asks the user to say go, such as: Phase"
            + " done. Say go to start the tono loop on PR #138."
        )
    elif talking and passes_on:
        print(
            f"The driver got your {args.kind}. The user is talking to you, so carry"
            + " on with the user in this pane."
        )
    elif talking:
        # The driver's watch skips the ordinary reports of a worker the user
        # is talking to, until the user window passes.
        minutes = round(user_window() / 60)
        print(
            "Recorded. The user is talking to you in this pane, so the driver"
            + f" leaves this report alone until {minutes} minutes pass with no new"
            + " prompt from the user. Ask the user directly in this pane."
            + f" {PASS_ON_RULE}"
        )
    elif args.kind == "phase":
        print(
            "Reported the phase. End your turn now. Once it ends, the watch hands"
            + " you off to a fresh session or tells you to carry on."
        )
    else:
        print(f"Reported {args.kind} to the driver.")
    return 0


def direct_host(
    tasks: dict[str, dict[str, Any]], parent: str | None, kind: str, passes_on: bool
) -> dict[str, Any] | None:
    """The parent task a child's report goes straight to, or None.

    Under hc, a child's done, question and blocked reports go to its parent's
    terminal at once, as hc's own reports do, even mid-turn. In Herdr the
    watch holds them until the parent's turn ends.
    """
    host = tasks.get(parent) if parent else None
    if (
        not host
        or kind not in CHILD_KINDS
        or passes_on
        or host.get("snoozed")
        or host.get("closed_at")
        or backend.kind(host["pane_id"]) != backend.HC
    ):
        return None
    return host


def send_to_parent(name: str, host: dict[str, Any], report: dict[str, Any]) -> None:
    """Type a child's report into its parent. If that fails, the report goes
    back to the watch, which delivers it as it does in Herdr."""
    text = f"[{name} {report['kind']}] {report['text']}"
    try:
        backend.prompt(host["agent"], host["pane_id"], text)
    except (MotoError, subprocess.TimeoutExpired):
        with tasks_for_update() as tasks:
            for kept in tasks.get(name, {}).get("reports", []):
                if kept["at"] == report["at"]:
                    kept.pop("direct", None)
        return
    with tasks_for_update() as tasks:
        if host["agent"] in tasks:
            tasks[host["agent"]]["told"] = time.time()
        record("deliver", name, to=host["agent"], kind=report["kind"], at=report["at"])


def cmd_settle(args: argparse.Namespace) -> int:
    """Replace a settled question with a done report the watch has already seen.

    A plain `report --agent` from the driver comes back to it as worker news.
    """
    text = " ".join(args.text).strip()
    with tasks_for_update() as tasks:
        task = find_task(tasks, args.agent)
        task["report"] = {"kind": "done", "text": text, "at": time.time()}
        task.setdefault("seen", {})["report_at"] = task["report"]["at"]
        record("settle", task["agent"], text=text)
    print(f"Settled {task['agent']}; the watch skips it.")
    return 0


def cmd_tell(args: argparse.Namespace) -> int:
    """Send a worker a prompt tagged with its sender: the driver or its parent."""
    text = " ".join(args.text).strip() or sys.stdin.read().strip()
    if not text:
        raise MotoError("Pass the message as arguments or on stdin")
    sender = message_sender(read_tasks(), args.agent, text)
    print(f"Sent to {tell_task(args.agent, text, sender)}.")
    return 0


def tell_task(name: str, text: str, sender: str | None) -> str:
    """Prompt a live task, tagged with its sender, and return its agent name."""
    task = find_task(read_tasks(), name)
    if task.get("snoozed"):
        raise MotoError(f"{name} is snoozed; pass the message to moto wake")
    agent = task["agent"]
    backend.prompt(agent, task["pane_id"], f"{tag(sender)} {text}")
    with tasks_for_update() as tasks:
        if agent in tasks:
            tasks[agent]["told"] = time.time()
        record("tell", agent, text=text, **{"from": sender or "driver"})
    return agent


def cmd_handoff(args: argparse.Namespace) -> int:
    """Hand a worker off, and from the watch, tell the driver when that fails.

    The watch starts a phase handoff in the background, so nobody else would
    see its error. It also set the handoff marker, which a failure must end.
    """
    if not args.from_watch:
        return hand_off(args)
    try:
        return hand_off(args)
    except MotoError as error:
        with tasks_for_update() as tasks:
            if args.agent in tasks:
                tasks[args.agent].pop("handoff", None)
                record("handoff_failed", args.agent, error=str(error))
        wake_driver(
            f"phase-{args.agent}",
            f"{args.agent}'s phase handoff failed: {error}",
            label="[watch]",
        )
        raise


def hand_off(args: argparse.Namespace) -> int:
    """Hand a worker off to a fresh session in its pane, with an optional brief.

    The worker's /handoff command writes the handoff file, then clears the
    session and runs /takeoff on it. The brief on stdin goes to the new session
    once takeoff's turn has ended.
    """
    goal = " ".join(args.goal).strip()
    if HANDOFF_STAY in goal.split():
        raise MotoError(f"{HANDOFF_STAY} keeps the session, so there is no handoff")
    brief = "" if sys.stdin.isatty() else sys.stdin.read().strip()
    name = args.agent
    sender = message_sender(read_tasks(), name, brief)
    live = live_agents()
    with tasks_for_update() as tasks:
        task = find_task(tasks, name)
        if task.get("snoozed"):
            raise MotoError(f"{name} is snoozed; wake it first")
        agent = live.get(task["pane_id"])
        status = agent.get("agent_status") if agent else "gone"
        if status == "gone":
            raise MotoError(f"{name}'s pane is gone")
        if status in BUSY:
            raise MotoError(f"{name} is {status}; wait for it to finish its turn")
        old = task.get("session")
        task["handoff"] = {"at": time.time(), "old": old}
    try:
        backend.prompt(task["agent"], task["pane_id"], f"/handoff {goal}".strip())
        new = wait_for(
            lambda: (read_tasks().get(name, {}).get("handoff") or {}).get("new"),
            HANDOFF_SESSION_WAIT,
            f"{name} started no new session within {age(HANDOFF_SESSION_WAIT)}: the"
            + " handoff may have failed, and the session may be unchanged",
        )
        with tasks_for_update():
            record("handoff", name, old=old, new=new, goal=goal)
        wait_for(
            lambda: took_off(name),
            HANDOFF_TAKEOFF_WAIT,
            f"{name}'s takeoff turn did not end within {age(HANDOFF_TAKEOFF_WAIT)}",
        )
    except BaseException:
        with tasks_for_update() as tasks:
            if name in tasks:
                tasks[name].pop("handoff", None)
        raise
    with tasks_for_update() as tasks:
        if name in tasks:
            settled(tasks[name], live_agents().get(task["pane_id"]))
    print(f"Handed {name} off to session {new}.")
    if brief:
        print(f"Sent to {tell_task(name, brief, sender)}.")
    return 0


def wait_for(ready: Callable[[], Any], timeout: float, failure: str) -> Any:
    """Poll until ready returns something truthy, which wait_for returns."""
    deadline = time.time() + timeout
    while not (found := ready()):
        if time.time() >= deadline:
            raise MotoError(failure)
        time.sleep(HANDOFF_POLL_SECONDS)
    return found


def took_off(name: str) -> bool:
    """Whether the worker's new session has answered and its turn has ended.

    /clear leaves the pane idle before /takeoff starts, so an idle pane is not
    enough: the new session's transcript must hold a reply too.
    """
    task = read_tasks().get(name)
    if task is None:
        raise MotoError(f"{name} was closed during the handoff")
    agent = live_agents().get(task["pane_id"])
    if not agent or agent.get("agent_status") not in TURN_OVER:
        return False
    turn, _ = last_turn(task, agent)
    return turn is not None


def settled(task: dict[str, Any], agent: dict[str, Any] | None) -> None:
    """End the handoff marker, treating takeoff's turn as seen by the watch."""
    seen = task.setdefault("seen", {})
    seen.pop("pending", None)
    seen["turn"], _ = last_turn(task, agent)
    if agent:
        seen["status"] = agent.get("agent_status")
        seen["seq"] = agent.get("state_change_seq")
    task.pop("handoff", None)


def cmd_ask(args: argparse.Namespace) -> int:
    """Show the driver's question under its own sidebar row, or clear it.

    Clearing drops the question's own fields and keeps the rest, because
    driver.json also records where the driver is, which a scheduled job needs
    long after a question is answered.
    """
    if args.clear:
        driver = read_driver()
        for field in ("kind", "text", "at"):
            driver.pop(field, None)
        if driver:
            driver_path().write_text(json.dumps(driver) + "\n")
        else:
            driver_path().unlink(missing_ok=True)
        print("Cleared the driver's question.")
        return 0
    text = " ".join(args.text).strip()
    pane_id = backend.here()
    if not text or not pane_id:
        raise MotoError("Pass the question, from inside the driver's own terminal")
    write_driver(pane_id=pane_id, kind="question", text=text, at=time.time())
    print("The question shows under the driver's sidebar row until moto ask --clear.")
    return 0
