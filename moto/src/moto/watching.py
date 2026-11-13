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
    BUSY_LIMIT,
    CHILD_KINDS,
    CHILD_REPORT,
    COMPACT_GROWTH,
    DRIVER_TAG,
    ENDED_BY_USER,
    HANDOFF_MARKER_LIFE,
    PANE_GONE_GRACE,
    REPORT_SETTLE_SECONDS,
    SELF,
    TURN_OVER,
    TURN_SETTLE_SECONDS,
    Delivery,
    MotoError,
    Step,
    age,
    state_dir,
)
from moto.driverstate import take_notes
from moto.sessions import context_tokens, last_turn, settings, user_prompt_at
from moto.store import (
    drop_held,
    in_window,
    new_reports,
    record,
    settle_report,
    tasks_for_update,
    unseen_reports,
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

    A worker needs the driver when it reports, when its turn ends, when it waits at a
    prompt, and when its pane closes. Herdr's state_change_seq catches a turn
    that ended while nothing was watching. A done worker that someone looked at
    turns idle, and that is not news. turn_end decides which turn ends are news.
    A task the user is talking to is news only when its pane closes, when it
    passes a report on with --to-driver, which a done does by itself, and once
    the user window passes; pane_closed, passed_on and user_talk decide when.
    A task another
    worker started is news only when its pane closes, when the user ends or
    hands it back, and when it passes a report on. Its done, question and
    blocked reports go to that worker through outbox, which the caller sends
    after the update; to_parent decides when. Without an outbox they wait.

    A phase report was decided when the worker made it: cmd_report told the
    worker to carry on in its turn, or to end it for a handoff. Only a handoff
    waits for the turn to end, and then phase_step adds it to steps. A turn end
    without a report may earn /compact, which compact_line decides. Both add to
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
        if parent := task.get("parent"):
            lines += child_report(name, task, parent)
            lines += to_parent(name, task, parent, tasks, live, now, outbox)
            continue
        news, talking = user_talk(name, task, agent, status, now)
        lines += news
        if talking:
            lines += passed_on(name, task)
            settle_answered(name, task, now)
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
            lines += [f"{name} {r['kind']}: {r['text']}{closed}" for r in earlier]
            if last["kind"] == "phase" and status != "gone":
                line = phase_step(name, task, last, now, steps)
            else:
                line = f"{name} {last['kind']}: {last['text']}{closed}"
        elif changed and status == "blocked":
            line = f"{name} blocked: waiting at an approval or question prompt"
        elif status in ("done", "idle") and (changed or "pending" in seen):
            line = turn_end(name, task, agent, now)
            if line:
                lines.append(line)
            if steps is not None and "pending" not in seen:
                if compact := compact_line(name, task, agent, steps):
                    lines.append(compact)
            continue
        if line:
            seen.pop("pending", None)
            lines.append(line)
    return lines


def user_talk(
    name: str,
    task: dict[str, Any],
    agent: dict[str, Any] | None,
    status: str,
    now: float,
) -> tuple[list[str], bool]:
    """The driver's lines about the user talking to a worker, and whether the
    user still is.

    The worker is with the user while the user's last prompt in its pane, which
    user_prompt_at finds, is within the user window. When that starts, the
    driver hears the reports it has not seen, since passed_on skips them. The
    window keeps the driver hands-off and moto from typing into the pane, and
    nothing more: it never makes the worker stop. settle_answered reads the
    prompt's time from with_user. Once the window passes and the turn the user
    started has ended, the worker is the driver's again. The driver hears once
    with the worker's latest state, and only when that state needs action
    (back_to_driver decides). A wrap or snooze report ends the window early, and the normal path
    delivers it. While a handoff runs, the typing is moto's own, so nothing
    changes. with_user in task keeps the last prompt's time between passes.
    """
    since: float | None = task.get("with_user")
    if task.get("handoff"):
        return [], since is not None
    try:
        at = user_prompt_at(task, agent)
    except (MotoError, OSError):
        return [], since is not None  # nothing to read now, so nothing changes
    if in_window(task, at, now):
        task["with_user"] = at
        if since is not None:
            return [], True
        lines = [f"{name} {r['kind']}: {r['text']}" for r in new_reports(task)]
        record("with_user", name, at=at)
        return lines, True
    if since is None:
        return [], False
    if any(r["kind"] in ENDED_BY_USER for r in unseen_reports(task)):
        del task["with_user"]
        return [], False
    if status == "working":
        return [], True  # the turn the user started still runs
    del task["with_user"]
    record("back_to_driver", name, at=since)
    line = back_to_driver(name, task, agent, status, since, now)
    return [line] if line else [], False


def settle_answered(name: str, task: dict[str, Any], now: float) -> None:
    """Settle an open question or blocked report that the user's last prompt came
    after, as moto settle would, since the user answers in the pane.

    This runs on every pass while the user is with the worker, after passed_on
    has taken the reports the driver hears of, so the sidebar never shows a
    question the user already answered. A report made after the prompt stays
    open until the user's next one.
    """
    at: float | None = task.get("with_user")
    report: dict[str, Any] | None = task.get("report")
    if (
        at is not None
        and report
        and report["kind"] in ("question", "blocked")
        and report["at"] < at
    ):
        settle_report(task, USER_ANSWERS, now)
        record("settle", name, text=USER_ANSWERS)


def back_to_driver(
    name: str,
    task: dict[str, Any],
    agent: dict[str, Any] | None,
    status: str,
    since: float,
    now: float,
) -> str | None:
    """The line that hands a worker back to the driver after the user window, or
    None when the worker needs no action. Marks its state seen, so the normal
    path does not repeat it.

    The worker's last report counts as its state only when it came after the
    user's last prompt, and a settled one never counts. The worker needs action
    when that report is a question or blocked, when it waits at a prompt, and
    when its last turn ended without a report. Any other report, such as a done,
    wrap, snooze or phase, reached the driver already.
    """
    seen = task["seen"]
    seen.pop("pending", None)
    seen["status"] = status
    seen["seq"] = agent.get("state_change_seq") if agent else None
    seen["turn"], _ = last_turn(task, agent)
    new_reports(task)
    report: dict[str, Any] | None = task.get("report")
    if report and report["at"] >= since and not report.get("settled"):
        if report["kind"] not in ("question", "blocked"):
            return None
        ago = age(now - report["at"])
        state = f"last report {report['kind']} ({ago} ago): {report['text']}"
    elif status == "blocked":
        state = "it waits at an approval or question prompt"
    else:
        state = "its last turn ended without a report"
    last = age(now - since)
    return (
        f"{name}: back with the driver, the user's last prompt was {last} ago; {state}"
    )


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

    The parent takes them once its turn ends, even while the user talks to the
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
    """The lines for new --to-driver and phase reports of a task the user is
    talking to, once each.

    The user asked the worker to send the first, or it is a done, which
    cmd_report marks to_driver while the worker is with the user. Both are the
    driver's news. The driver hears of a phase report too, which moto does not
    act on while the user is typing to the worker. The other reports are the user's, so they pass unseen.
    """
    lines: list[str] = []
    for report in new_reports(task):
        if report.get("to_driver"):
            lines.append(
                f"{name} {report['kind']} (with the user, passed on): {report['text']}"
            )
        elif report["kind"] == "phase":
            lines.append(f"{name} phase (with the user): {report['text']}")
    return lines


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
    """The line for a turn that ended without a report, or None to stay quiet.

    Quiet, and logged as an absorb event, when moto handoff is moving the worker
    to a new session, when the worker reported since the driver last wrote to it, or when Herdr announces a turn
    the watch already handled. A turn end stays pending while
    the worker's background work runs, up to BUSY_LIMIT, and is rechecked every
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
    elif turn is not None and turn == seen.get("turn"):
        if now - pending["since"] < TURN_SETTLE_SECONDS:
            return None  # the transcript may not hold the new turn yet
        reason = "Herdr announced a turn the watch already handled"
    elif report and told is not None and report["at"] >= told:
        reason = "it reported since the driver last wrote to it"
    work = None if reason else background_work(task["pane_id"])
    if work and now - pending["since"] < BUSY_LIMIT:
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
    if work:
        running = age(now - pending["since"])
        return (
            f"{name}: turn ended without a report; {work} still running after {running}"
        )
    return f"{name}: turn ended without a report"


def kilo(tokens: int) -> str:
    return f"{round(tokens / 1000)}k"


def phase_step(
    name: str,
    task: dict[str, Any],
    report: dict[str, Any],
    now: float,
    steps: list[Step] | None,
) -> str:
    """The driver's line for a phase report, and for one decided to hand off
    whose turn has ended, the handoff step.

    cmd_report decided the report's action from the worker's context size. A
    worker that carries on already did, in its own turn, so the watch types
    nothing. One over the limit was told to end its turn, and now it has, so the
    handoff starts. The driver hears of the phase once either way.
    """
    phase = report["text"]
    head = f"{name} phase: {phase}"
    tokens = report.get("tokens")
    size = f" at {kilo(tokens)} tokens" if tokens is not None else ""
    if report.get("action") != "handoff" or steps is None:
        return f"{head} (carrying on in the same session{size})"
    # Absorbs the /handoff turn until moto handoff sets its own marker.
    task["handoff"] = {"at": now, "old": task.get("session")}
    steps.append(Step(name, "handoff", phase))
    return f"{head}; handing it off to a fresh session{size}"


def compact_line(
    name: str, task: dict[str, Any], agent: dict[str, Any] | None, steps: list[Step]
) -> str | None:
    """Send /compact to a worker whose turn ended over the compact limit.

    seen.compact_at holds the context size at the last /compact, or the size
    since, if the context shrank. The worker gets /compact again only once its
    context grew COMPACT_GROWTH past that. A worker a handoff is moving is
    left alone, and one the user is talking to never gets here.
    """
    if task.get("handoff"):
        return None
    tokens = context_tokens(task, agent)
    if tokens is None:
        return None
    seen = task["seen"]
    last = seen.get("compact_at")
    if last is not None and tokens < last:
        seen["compact_at"] = last = tokens  # compacted since
    if tokens <= settings()["compact_tokens"]:
        return None
    if last is not None and tokens - last < COMPACT_GROWTH:
        return None
    seen["compact_at"] = tokens
    record("compact", name, tokens=tokens)
    steps.append(Step(name, "compact", "/compact"))
    return f"{name}: sent /compact at {kilo(tokens)} tokens"


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
    """A task the user is talking to is the user's, a snoozed one has no pane,
    and a worker that started another one takes its reports, so moto watch
    counts none of the three, apart from what pane_watched, child_report,
    to_parent, passed_on and user_talk cover."""
    return bool(task.get("with_user") or task.get("snoozed") or task.get("parent"))


def pane_watched(task: dict[str, Any]) -> bool:
    """Whether moto watch looks for a closed pane, which it does for tasks the
    user is talking to and those another worker started too."""
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
