from __future__ import annotations

import argparse
import json
import subprocess
import time
from typing import Any

from moto import backend
from moto.backend import live_agents
from moto.common import (
    ADOPT_KINDS,
    BACKGROUND_WORK,
    BRIEF_FOOTER,
    BUSY,
    CHILD_KINDS,
    COMPACT_GROWTH,
    DRIVER_TAG,
    HANDOFF_MARKER_LIFE,
    PANE_GONE_GRACE,
    REPORT_SETTLE_SECONDS,
    SELF,
    TURN_OVER,
    TURN_SETTLE_SECONDS,
    Delivery,
    MotoError,
    Step,
    state_dir,
)
from moto.driverstate import take_notes
from moto.sessions import context_tokens, last_turn, settings
from moto.store import (
    drop_held,
    new_reports,
    record,
    settle_report,
    tasks_for_update,
    unseen_reports,
    user_owns,
)

USER_ANSWERS = "the user answers in the pane"


def check(
    tasks: dict[str, dict[str, Any]],
    live: dict[str, dict[str, Any]],
    now: float,
    outbox: list[Delivery] | None = None,
    steps: list[Step] | None = None,
) -> list[str]:
    """One line per task that needs the driver, updating each task's seen marker.

    The driver hears only what MODEL.md lists for a task it owns: a done,
    question, blocked, wrap or snooze report, a closed pane, and one stall
    signal, a turn that ended with no report and no background work, or a
    worker waiting at an approval prompt. turn_end decides the stall. Herdr's
    state_change_seq catches a turn that ended while nothing was watching.

    A task the user owns, which user_owns decides, is news only when its pane
    closes and when it passes a report on with --to-driver. A wrap or snooze
    gives it back, and the normal path delivers that report. A task another
    worker started is news only when its pane closes, when the user ends it,
    and when it passes a report on. Its done, question and blocked reports go to
    that worker through outbox, which the caller sends after the update;
    to_parent decides when. Without an outbox they wait.

    A phase report stays between the worker and moto. cmd_report told the
    worker to carry on in its turn, or to end it for a handoff. Only a handoff
    waits for the turn to end, and then phase_step adds it to steps. A turn end
    without a report may earn /compact, which compact_step decides. Both add to
    steps, which the caller runs after the update. Without steps, handoffs wait.
    """
    lines: list[str] = []
    for name, task in sorted(tasks.items()):
        if not pane_watched(task):
            continue
        seen: dict[str, Any] = task.setdefault("seen", {})
        agent = live.get(task["pane_id"])
        status = agent.get("agent_status") if agent else "gone"
        seq = agent.get("state_change_seq") if agent else None
        if status == "unknown":
            continue
        if closed := pane_closed(name, task, status == "gone", now):
            lines.append(closed)
        was_owned = task.get("owner") == "user" or "with_user" in task
        if user_owns(task, agent):
            if not was_owned:
                lines += taken(name, task)
            lines += passed_on(name, task)
            settle_answered(name, task, now)
            continue
        if parent := task.get("parent"):
            lines += child_report(name, task, parent)
            lines += to_parent(name, task, parent, tasks, live, now, outbox)
            continue
        unseen = unseen_reports(task)
        if unseen and unseen[-1].get("action") == "handoff":
            if steps is None or status in BUSY:
                unseen = unseen[:-1]  # the handoff needs the turn to end
        fresh = bool(unseen)
        if status == "working":
            changed = False
            seen.pop("pending", None)  # a new turn started
            fresh = fresh and now - unseen[-1]["at"] >= REPORT_SETTLE_SECONDS
        elif status == "gone":
            changed = False  # pane_closed reports it, once it has stayed gone
        elif status == "idle":
            changed = seen.get("status") == "working"
        else:
            changed = seq != seen.get("seq")
        seen["status"], seen["seq"] = status, seq
        line = None
        if fresh:
            seen["report_at"] = unseen[-1]["at"]
            closed = " (pane closed)" if task.get("closed_at") else ""
            *earlier, last = unseen
            lines += [
                f"{name} {r['kind']}: {r['text']}{closed}"
                for r in earlier
                if r["kind"] != "phase"
            ]
            if last["kind"] == "phase":
                if status != "gone":
                    phase_step(name, task, last, now, steps)
                seen.pop("pending", None)
            else:
                line = f"{name} {last['kind']}: {last['text']}{closed}"
        elif changed and status == "blocked":
            line = f"{name}: stalled at an approval or question prompt"
        elif status in ("done", "idle") and (changed or "pending" in seen):
            line = turn_end(name, task, agent, now)
            if line:
                lines.append(line)
            if steps is not None and "pending" not in seen:
                compact_step(name, task, agent, steps)
            continue
        if line:
            seen.pop("pending", None)
            lines.append(line)
    return lines


def taken(name: str, task: dict[str, Any]) -> list[str]:
    """The lines for reports the driver had not seen when the user took the
    task. They came while the driver owned it, so they are still its news."""
    at = task["owned_since"]
    before = [r for r in unseen_reports(task) if r["at"] < at]
    if before:
        task["seen"]["report_at"] = before[-1]["at"]
    return [f"{name} {r['kind']}: {r['text']}" for r in before if r["kind"] != "phase"]


def settle_answered(name: str, task: dict[str, Any], now: float) -> None:
    """Settle an open question or blocked report from before the user took the
    task, as moto settle would, since the user answers in the pane.

    This runs on every pass while the user owns the worker, after passed_on
    has taken the reports the driver hears of, so the sidebar never shows a
    question the user already answered.
    """
    at: float | None = task.get("owned_since")
    report: dict[str, Any] | None = task.get("report")
    if (
        at is not None
        and report
        and report["kind"] in ("question", "blocked")
        and report["at"] < at
    ):
        settle_report(task, USER_ANSWERS, now)
        record("settle", name, text=USER_ANSWERS)


def child_report(name: str, task: dict[str, Any], parent: str) -> list[str]:
    """The lines for a child task's new wrap, snooze and passed-on reports, once
    each.

    The user runs or asks for those in the child's pane, so they are the
    driver's news. The child's done, question and blocked reports are for its
    parent, so they queue in seen.for_parent for to_parent.
    """
    lines: list[str] = []
    closed = " (pane closed)" if task.get("closed_at") else ""
    for report in new_reports(task):
        if not (report["kind"] in ADOPT_KINDS or report.get("to_driver")):
            # A report sent straight to its parent under hc is delivered.
            if report["kind"] in CHILD_KINDS and not report.get("direct"):
                task["seen"].setdefault("for_parent", []).append(report)
            continue
        lines.append(
            f"{name} {report['kind']} (child of {parent}): {report['text']}{closed}"
        )
    return lines


def to_parent(
    name: str,
    task: dict[str, Any],
    parent: str,
    tasks: dict[str, dict[str, Any]],
    live: dict[str, dict[str, Any]],
    now: float,
    outbox: list[Delivery] | None,
) -> list[str]:
    """Hand a child's queued reports to its parent once, returning driver lines.

    The parent takes them once its turn ends, even while the user owns the
    parent, since the child is its own work; mid-turn, at a prompt or between panes, they wait. A parent
    that is gone, snoozed or closed would never take them, so the driver gets
    them instead. Delivering counts as writing to the parent, like moto tell.
    """
    queued: list[dict[str, Any]] = task["seen"].get("for_parent") or []
    if not queued:
        return []
    host = tasks.get(parent) or {}
    if not host:
        why = "gone"
    elif host.get("snoozed"):
        why = "snoozed"
    elif host.get("closed_at"):
        why = "closed"
    else:
        why = None
    if why:
        del task["seen"]["for_parent"]
        for report in queued:
            record("deliver", name, to="driver", kind=report["kind"], at=report["at"])
        return [
            f"{name} {r['kind']} (child of {parent}, which is {why}): {r['text']}"
            for r in queued
        ]
    agent = live.get(host["pane_id"])
    if outbox is None or not agent or agent.get("agent_status") not in TURN_OVER:
        return []
    del task["seen"]["for_parent"]
    text = "\n".join(f"[{name} {r['kind']}] {r['text']}" for r in queued)
    outbox.append(Delivery(name, host["agent"], text))
    host["told"] = now
    for report in queued:
        record("deliver", name, to=parent, kind=report["kind"], at=report["at"])
    return []


def passed_on(name: str, task: dict[str, Any]) -> list[str]:
    """The lines for new --to-driver reports of a task the user owns, once each.

    The user asked the worker to send them. Its other reports are the user's,
    so they pass unseen.
    """
    return [
        f"{name} {r['kind']} (passed on): {r['text']}"
        for r in new_reports(task)
        if r.get("to_driver")
    ]


def pane_closed(name: str, task: dict[str, Any], gone: bool, now: float) -> str | None:
    """The line for a pane the user closed, once, or None.

    A pane counts as closed once it has stayed gone for PANE_GONE_GRACE, so a
    session resumed in a new pane, which attach moves the task to, is never
    news. closed_at marks the task until a live pane clears it.
    """
    seen = task["seen"]
    if not gone:
        seen.pop("gone_since", None)
        task.pop("closed_at", None)
        return None
    since = seen.setdefault("gone_since", now)
    if task.get("closed_at") or now - since < PANE_GONE_GRACE:
        return None
    task["closed_at"] = since
    record("pane_closed", name, pane_id=task["pane_id"], at=since)
    if parent := task.get("parent"):
        return f"{name} (child of {parent}): pane closed"
    return f"{name}: pane closed"


def turn_end(
    name: str, task: dict[str, Any], agent: dict[str, Any] | None, now: float
) -> str | None:
    """The stall line for a turn that ended without a report, or None to stay quiet.

    Quiet, and logged as an absorb event, when moto handoff is moving the worker
    to a new session, when the task's flow is grill (the worker ends each turn
    with a question in its pane, and the worker's done report ends the grill, see
    end_grill), when the worker reported since the driver last wrote to it, or
    when Herdr announces a turn the watch already handled. A turn end stays pending while
    the worker's background work runs, however long, and is rechecked every
    poll. With no transcript to read, every turn end is news.
    """
    seen = task["seen"]
    pending: dict[str, Any] = seen.setdefault("pending", {"since": now})
    turn, _ = last_turn(task, agent)
    reason = None
    report: dict[str, Any] | None = task.get("report")
    told = task.get("told")
    if handoff := handoff_turn(task, now):
        reason = handoff
    elif task.get("flow") == "grill":
        reason = "grill turn ends with a question in the pane"
    elif turn is not None and turn == seen.get("turn"):
        if now - pending["since"] < TURN_SETTLE_SECONDS:
            return None  # the transcript may not hold the new turn yet
        reason = "Herdr announced a turn the watch already handled"
    elif report and told is not None and report["at"] >= told:
        reason = "it reported since the driver last wrote to it"
    work = None if reason else background_work(task["pane_id"])
    if work:
        pending["busy_at"] = now
        if not pending.get("logged"):
            pending["logged"] = True
            record("absorb", name, reason=f"{work} still running", turn=turn)
        return None
    busy_at = pending.get("busy_at")
    if not reason and busy_at is not None and now - busy_at < TURN_SETTLE_SECONDS:
        return None  # its background work just ended, so a new turn may start
    del seen["pending"]
    seen["turn"] = turn
    if reason:
        record("absorb", name, reason=reason, turn=turn)
        return None
    return f"{name}: stalled, its turn ended without a report"


def phase_step(
    name: str,
    task: dict[str, Any],
    report: dict[str, Any],
    now: float,
    steps: list[Step] | None,
) -> None:
    """Start the handoff for a phase report decided to hand off, once the
    worker's turn has ended.

    cmd_report decided the report's action from the worker's context size. A
    worker that carries on already did, in its own turn, so the watch does
    nothing. One over the limit was told to end its turn, and now it has. The
    driver hears of a phase only when its handoff fails.
    """
    if report.get("action") != "handoff" or steps is None:
        return
    # Absorbs the /handoff turn until moto handoff sets its own marker.
    task["handoff"] = {"at": now, "old": task.get("session")}
    steps.append(Step(name, "handoff", report["text"]))
    record("phase_handoff", name, phase=report["text"], tokens=report.get("tokens"))


def compact_step(
    name: str, task: dict[str, Any], agent: dict[str, Any] | None, steps: list[Step]
) -> None:
    """Send /compact to a worker whose turn ended over the compact limit.

    seen.compact_at holds the context size at the last /compact, or the size
    since, if the context shrank. The worker gets /compact again only once its
    context grew COMPACT_GROWTH past that. A worker a handoff is moving is
    left alone, and one the user owns never gets here. The driver does not hear
    of it.
    """
    if task.get("handoff"):
        return
    tokens = context_tokens(task, agent)
    if tokens is None:
        return
    seen = task["seen"]
    last = seen.get("compact_at")
    if last is not None and tokens < last:
        seen["compact_at"] = last = tokens  # compacted since
    if tokens <= settings()["compact_tokens"]:
        return
    if last is not None and tokens - last < COMPACT_GROWTH:
        return
    seen["compact_at"] = tokens
    record("compact", name, tokens=tokens)
    steps.append(Step(name, "compact", "/compact"))


def handoff_turn(task: dict[str, Any], now: float) -> str | None:
    """Why a turn end belongs to a running moto handoff, or None.

    The turn before the new session is the /handoff turn, and the turn after it
    is takeoff's. A marker that outlived HANDOFF_MARKER_LIFE is dropped.
    """
    marker = task.get("handoff")
    if not marker:
        return None
    if now - marker["at"] > HANDOFF_MARKER_LIFE:
        del task["handoff"]
        return None
    return "takeoff turn of a handoff" if marker.get("new") else "handoff turn"


def background_work(pane_id: str) -> str | None:
    """What the worker's footer says still runs, as in "1 shell", or None."""
    try:
        screen = backend.screen(pane_id)
    except (MotoError, subprocess.TimeoutExpired):
        return None
    found = BACKGROUND_WORK.findall("\n".join(screen.splitlines()[-3:]))
    return " and ".join(found) or None


def unwatched(task: dict[str, Any]) -> bool:
    """A task the user owns is the user's, a snoozed one has no pane, and a
    worker that started another one takes its reports, so moto watch counts
    none of the three, apart from what pane_watched, child_report, to_parent
    and passed_on cover."""
    return bool(
        task.get("owner") == "user" or task.get("snoozed") or task.get("parent")
    )


def pane_watched(task: dict[str, Any]) -> bool:
    """Whether moto watch looks for a closed pane, which it does for tasks the
    user owns and those another worker started too."""
    return not task.get("snoozed")


def watch() -> dict[str, Any]:
    """One pass for the moto-watch mod, which runs it every few seconds in the driver.

    watching counts the tasks the pass covers, lines has one line per worker that
    needs the driver, and notes holds what scheduled jobs left, removed as the
    pass hands them over, or None. tasks names every task moto tracks, so the mod
    can drop held lines of a task closed since.
    """
    outbox: list[Delivery] = []
    steps: list[Step] = []
    with tasks_for_update() as tasks:
        drop_held(tasks)
        names = sorted(tasks)
        watching = sum(1 for t in tasks.values() if not unwatched(t))
        panes = any(pane_watched(t) for t in tasks.values())
        now = time.time()
        lines = check(tasks, live_agents(), now, outbox, steps) if panes else []
    # Sent after the update, so a slow Herdr never holds the task lock.
    for delivery in outbox:
        try:
            terminal = tasks[delivery.parent]["pane_id"]
            backend.prompt(delivery.parent, terminal, delivery.text)
        except (MotoError, subprocess.TimeoutExpired) as error:
            lines.append(
                f"{delivery.child} could not reach {delivery.parent} ({error}):"
                + f" {delivery.text}"
            )
    for step in steps:
        try:
            run_step(step, tasks[step.agent]["pane_id"])
        except (MotoError, OSError, subprocess.TimeoutExpired) as error:
            lines.append(f"{step.agent}: could not {step.action} ({error})")
    return {
        "watching": watching,
        "lines": lines,
        "notes": take_notes(),
        "tasks": names,
    }


def run_step(step: Step, terminal: str) -> None:
    """Run what phase_step or compact_line decided for a worker.

    A handoff waits minutes for the new session, longer than a watch pass may
    take, so it runs as its own moto handoff in the background. That process
    tells the driver if it fails.
    """
    if step.action == "tell":
        backend.prompt(step.agent, terminal, f"{DRIVER_TAG} {step.text}")
    elif step.action == "compact":
        backend.prompt(step.agent, terminal, step.text)
    elif step.action == "handoff":
        state_dir().mkdir(parents=True, exist_ok=True)
        brief = (
            f"Start the next phase: {step.text}. The handoff above holds what it"
            + f" needs.\n\n{BRIEF_FOOTER}"
        )
        command = list(SELF)
        with open(state_dir() / f"handoff-{step.agent}.log", "a") as log:
            process = subprocess.Popen(
                command + ["handoff", "--from-watch", step.agent, step.text],
                stdin=subprocess.PIPE,
                stdout=log,
                stderr=subprocess.STDOUT,
                start_new_session=True,
                text=True,
            )
        if process.stdin:
            process.stdin.write(brief)
            process.stdin.close()


def cmd_watch(_: argparse.Namespace) -> int:
    print(json.dumps(watch()))
    return 0
