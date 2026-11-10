from __future__ import annotations

import argparse
import json
import subprocess
import time
from typing import Any

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
    herdr,
    herdr_binary,
    live_agents,
    run,
    state_dir,
)
from moto.driverstate import take_notes
from moto.sessions import context_tokens, last_turn, settings, user_prompt
from moto.store import hold_task, new_reports, record, tasks_for_update, unseen_reports


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
    A held task is news only when its pane closes and when it passes a report on
    with --to-driver, which a done does by itself; pane_closed and passed_on
    decide when. A task another
    worker started is news only when its pane closes, when the user ends or
    hands it back, and when it passes a report on. Its done, question and
    blocked reports go to that worker through outbox, which the caller sends
    after the update; to_parent decides when. Without an outbox they wait.

    A phase report waits for the worker's turn to end, then phase_step decides
    whether the worker hands off or carries on. A turn end without a report may
    earn /compact, which compact_line decides. Both add to steps, which the
    caller runs after the update. Without steps, phase reports wait.
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
        lines += taken_over(name, task, agent)
        if parent := task.get("parent"):
            lines += child_report(name, task, parent)
            lines += to_parent(name, task, parent, tasks, live, now, outbox)
            continue
        if task.get("held"):
            lines += passed_on(name, task)
            continue
        unseen = unseen_reports(task)
        if unseen and unseen[-1]["kind"] == "phase":
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
            if last["kind"] == "phase" and steps is not None and status != "gone":
                line = phase_step(name, task, agent, last, now, steps)
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


def taken_over(
    name: str, task: dict[str, Any], agent: dict[str, Any] | None
) -> list[str]:
    """Hold a task whose worker the user started talking to, and say so once.

    The user's turn is a typed prompt that is not the driver's, the parent's, a
    child's report or a command moto submitted, which user_prompt decides. The
    first pass only records the latest one, so a task's history never holds it.
    A turn the driver has not seen a report for comes first, because holding
    makes the watch skip it. A wrap, snooze or handback it has not seen ends
    the hold, so the typing is dropped. A running handoff is moto's own typing.
    """
    if task.get("held") or task.get("handoff"):
        return []
    seen = task["seen"]
    try:
        turn = user_prompt(task, agent)
    except (MotoError, OSError):
        return []  # nothing to read yet, so the baseline waits
    if "user_turn" not in seen:
        seen["user_turn"] = turn
        return []
    if turn is None or turn == seen["user_turn"]:
        return []
    if any(r["kind"] in ADOPT_KINDS for r in unseen_reports(task)):
        # A wrap, snooze or handback the watch has not seen ends the hold, as for
        # a manual hold, so it supersedes the typing: the normal path delivers it.
        seen["user_turn"] = turn
        return []
    lines = [f"{name} {r['kind']}: {r['text']}" for r in new_reports(task)]
    hold_task(task, "the user typed in the pane")
    return lines + [f"{name}: the user took it over, held"]


def child_report(name: str, task: dict[str, Any], parent: str) -> list[str]:
    """The lines for a child task's new wrap, snooze, handback and passed-on
    reports, once each.

    The user runs or asks for those in the child's pane, so they are the
    driver's news. The child's done, question and blocked reports are for its
    parent, held or not, so they queue in seen.for_parent for to_parent.
    """
    lines: list[str] = []
    closed = " (pane closed)" if task.get("closed_at") else ""
    for report in new_reports(task):
        if not (report["kind"] in ADOPT_KINDS or report.get("to_driver")):
            if report["kind"] in CHILD_KINDS:
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

    The parent takes them once its turn ends, held or not, since the child is
    its own work; mid-turn, at a prompt or between panes, they wait. A parent
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
    """The lines for a held task's new --to-driver and phase reports, once each.

    The user asked the worker to send the first, or it is a done, which
    cmd_report marks to_driver in a held task. Both are the driver's news.
    A phase report is never handed off in a held task, but the driver hears
    of it. The held task's other reports are the user's, so they pass unseen.
    """
    lines: list[str] = []
    for report in new_reports(task):
        if report.get("to_driver"):
            lines.append(f"{name} {report['kind']} (held, passed on): {report['text']}")
        elif report["kind"] == "phase":
            lines.append(f"{name} phase (held, not handed off): {report['text']}")
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
    to a new session, when the user is talking to the worker, when the worker
    reported since the driver last wrote to it, or when Herdr announces a turn
    the watch already handled. A turn end stays pending while
    the worker's background work runs, up to BUSY_LIMIT, and is rechecked every
    poll. With no transcript to read, every turn end is news.
    """
    seen = task["seen"]
    pending: dict[str, Any] = seen.setdefault("pending", {"since": now})
    turn, prompt = last_turn(task, agent)
    reason = None
    report: dict[str, Any] | None = task.get("report")
    told = task.get("told")
    if handoff := handoff_turn(task, now):
        reason = handoff
    elif turn is not None and turn == seen.get("turn"):
        if now - pending["since"] < TURN_SETTLE_SECONDS:
            return None  # the transcript may not hold the new turn yet
        reason = "Herdr announced a turn the watch already handled"
    elif from_user(prompt):
        reason = "the user is talking to the worker"
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


def from_user(prompt: str | None) -> bool:
    """Whether the worker's last typed prompt is the user's, not the driver's
    or a child's report."""
    return (
        prompt is not None
        and not prompt.startswith(DRIVER_TAG)
        and not CHILD_REPORT.match(prompt)
    )


def kilo(tokens: int) -> str:
    return f"{round(tokens / 1000)}k"


def phase_step(
    name: str,
    task: dict[str, Any],
    agent: dict[str, Any] | None,
    report: dict[str, Any],
    now: float,
    steps: list[Step],
) -> str:
    """Hand a worker whose turn ended on a phase report off, or tell it to carry on.

    A worker over the handoff limit starts the next phase in a fresh session,
    and one under it carries on. The driver gets the line either way. When the
    user is talking to the worker, or the context size is unknown, the watch
    does neither and the line leaves it to the driver.
    """
    phase = report["text"]
    head = f"{name} phase: {phase}"
    _, prompt = last_turn(task, agent)
    tokens = None if from_user(prompt) else context_tokens(task, agent)
    if tokens is None:
        why = "the user is talking to it" if from_user(prompt) else "no transcript"
        record("phase", name, phase=phase, action="driver", reason=why)
        return f"{head} (not handed off: {why})"
    limit = settings()["handoff_tokens"]
    if tokens > limit:
        record("phase", name, phase=phase, action="handoff", tokens=tokens)
        # Absorbs the /handoff turn until moto handoff sets its own marker.
        task["handoff"] = {"at": now, "old": task.get("session")}
        steps.append(Step(name, "handoff", phase))
        return f"{head}; handing it off to a fresh session at {kilo(tokens)} tokens"
    text = (
        f"Carry on with {phase} in this session. Its context holds"
        + f" {kilo(tokens)} tokens, under the {kilo(limit)} that start a fresh one."
    )
    record("phase", name, phase=phase, action="carry on", tokens=tokens)
    record("tell", name, text=text, **{"from": "watch"})
    task["told"] = now
    steps.append(Step(name, "tell", text))
    return f"{head}; told it to carry on at {kilo(tokens)} tokens"


def compact_line(
    name: str, task: dict[str, Any], agent: dict[str, Any] | None, steps: list[Step]
) -> str | None:
    """Send /compact to a worker whose turn ended over the compact limit.

    seen.compact_at holds the context size at the last /compact, or the size
    since, if the context shrank. The worker gets /compact again only once its
    context grew COMPACT_GROWTH past that. A worker the user is talking to, or
    one a handoff is moving, is left alone.
    """
    _, prompt = last_turn(task, agent)
    if task.get("handoff") or from_user(prompt):
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
        screen = run([herdr_binary(), "pane", "read", pane_id, "--source", "visible"])
    except (MotoError, subprocess.TimeoutExpired):
        return None
    found = BACKGROUND_WORK.findall("\n".join(screen.splitlines()[-3:]))
    return " and ".join(found) or None


def unwatched(task: dict[str, Any]) -> bool:
    """A held task is the user's, a snoozed one has no pane, and a worker that
    started another one takes its reports, so moto watch counts none of the
    three, apart from what pane_watched, child_report, to_parent and passed_on
    cover."""
    return bool(task.get("held") or task.get("snoozed") or task.get("parent"))


def pane_watched(task: dict[str, Any]) -> bool:
    """Whether moto watch looks for a closed pane, which it does for held tasks
    and those another worker started too."""
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
        names = sorted(tasks)
        watching = sum(1 for t in tasks.values() if not unwatched(t))
        panes = any(pane_watched(t) for t in tasks.values())
        now = time.time()
        lines = check(tasks, live_agents(), now, outbox, steps) if panes else []
    # Sent after the update, so a slow Herdr never holds the task lock.
    for delivery in outbox:
        try:
            herdr("agent", "prompt", delivery.parent, delivery.text)
        except (MotoError, subprocess.TimeoutExpired) as error:
            lines.append(
                f"{delivery.child} could not reach {delivery.parent} ({error}):"
                + f" {delivery.text}"
            )
    for step in steps:
        try:
            run_step(step)
        except (MotoError, OSError, subprocess.TimeoutExpired) as error:
            lines.append(f"{step.agent}: could not {step.action} ({error})")
    return {
        "watching": watching,
        "lines": lines,
        "notes": take_notes(),
        "tasks": names,
    }


def run_step(step: Step) -> None:
    """Run what phase_step or compact_line decided for a worker.

    A handoff waits minutes for the new session, longer than a watch pass may
    take, so it runs as its own moto handoff in the background. That process
    tells the driver if it fails.
    """
    if step.action == "tell":
        herdr("agent", "prompt", step.agent, f"{DRIVER_TAG} {step.text}")
    elif step.action == "compact":
        herdr("agent", "prompt", step.agent, step.text)
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
