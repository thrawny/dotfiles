from __future__ import annotations

import fcntl
import json
import os
import time
from collections.abc import Generator
from contextlib import contextmanager
from pathlib import Path
from typing import Any

from moto import backend
from moto.common import (
    DRIVER_TAG,
    ENDED_BY_USER,
    EVENTS_VERSION,
    MotoError,
    pending_events,
    state_dir,
)
from moto.sessions import settings, user_prompt_at


def read_tasks() -> dict[str, dict[str, Any]]:
    try:
        data = json.loads((state_dir() / "tasks.json").read_text())
    except FileNotFoundError:
        return {}
    except ValueError as error:
        raise MotoError(f"{state_dir() / 'tasks.json'} is not valid JSON") from error
    return data.get("tasks", {})


def record(event: str, agent: str, **fields: Any) -> None:
    """Log an event; the enclosing tasks_for_update appends it if it commits."""
    pending_events.append(
        {"v": EVENTS_VERSION, "ts": time.time(), "event": event, "agent": agent}
        | fields
    )


def append_events(
    directory: Path, events: list[dict[str, Any]], tasks: dict[str, dict[str, Any]]
) -> None:
    """Append to the event log, opening it with a snapshot of every task."""
    path = directory / "events.jsonl"
    if not path.exists():
        now = time.time()
        events = [
            {"v": EVENTS_VERSION, "ts": now, "event": "snapshot", "agent": name}
            | {"task": task}
            for name, task in sorted(tasks.items())
        ] + events
    if events:
        with path.open("a") as log:
            log.write("".join(json.dumps(e) + "\n" for e in events))


@contextmanager
def tasks_for_update() -> Generator[dict[str, dict[str, Any]]]:
    """The task table under an exclusive lock, written back on exit if it changed.

    Events recorded inside are appended under the same lock, so log lines never
    interleave and a failed update logs nothing.
    """
    directory = state_dir()
    directory.mkdir(parents=True, exist_ok=True)
    with open(directory / "tasks.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        pending_events.clear()
        tasks = read_tasks()
        before = json.dumps(tasks, sort_keys=True)
        try:
            yield tasks
        except BaseException:
            pending_events.clear()
            raise
        append_events(directory, pending_events, json.loads(before))
        pending_events.clear()
        if json.dumps(tasks, sort_keys=True) != before:
            path = directory / "tasks.json"
            tmp = path.with_suffix(".tmp")
            tmp.write_text(json.dumps({"tasks": tasks}, indent=2) + "\n")
            tmp.replace(path)


def forked() -> bool:
    """Whether this runs in a session fork-window forked, which owns no task."""
    return bool(os.environ.get("MOTO_FORK"))


def find_task(tasks: dict[str, dict[str, Any]], agent: str) -> dict[str, Any]:
    if agent not in tasks:
        raise MotoError(f"No task named {agent}")
    return tasks[agent]


def caller(tasks: dict[str, dict[str, Any]]) -> str | None:
    """The task in the caller's Herdr pane, or None when the driver calls."""
    pane_id = backend.here()
    return next((n for n, t in tasks.items() if t["pane_id"] == pane_id), None)


def message_sender(
    tasks: dict[str, dict[str, Any]], agent: str, text: str
) -> str | None:
    """The worker sending a message to agent, or None for the driver.

    A worker can message only the tasks it started.
    """
    sender = caller(tasks)
    if sender is None:
        return None
    if parent := tasks[sender].get("parent"):
        hint = f"{parent} started you, so moto report reaches it"
    else:
        hint = "To reach the driver, use moto report"
    if agent not in tasks:
        raise MotoError(f"No task named {agent}. {hint}")
    if tasks[agent].get("requested_by") == sender:
        hint = "The driver watches it, so use moto report to pass something on"
    if tasks[agent].get("parent") != sender:
        raise MotoError(
            f"{sender} can message only the tasks it started, and {agent} is not one"
            + f" of them. {hint}"
        )
    if text.startswith(DRIVER_TAG):
        raise MotoError(
            f"Only the driver's messages start with {DRIVER_TAG}; moto tags yours"
            + f" [{sender}]"
        )
    return sender


def tag(sender: str | None) -> str:
    return f"[{sender}]" if sender else DRIVER_TAG


def decorator_links() -> dict[str, dict[str, str]]:
    """Pane id → the PR and Jira links herdr-decorator found for it."""
    base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
    try:
        panes = json.loads((Path(base) / "herdr-decorator/panes.json").read_text())
    except (OSError, ValueError):
        return {}
    return {pane_id: info.get("links") or {} for pane_id, info in panes.items()}


def unseen_reports(task: dict[str, Any]) -> list[dict[str, Any]]:
    """The task's reports the watch has not seen, oldest first.

    A task saved before moto kept reports has only its last report.
    """
    reports: list[dict[str, Any]] = task.get("reports") or (
        [task["report"]] if task.get("report") else []
    )
    seen_at = task.get("seen", {}).get("report_at")
    if seen_at is None:
        return reports
    return [r for r in reports if r["at"] > seen_at]


def new_reports(task: dict[str, Any]) -> list[dict[str, Any]]:
    """The task's reports the watch has not seen, oldest first, marking them seen."""
    reports = unseen_reports(task)
    if reports:
        task["seen"]["report_at"] = reports[-1]["at"]
    return reports


def settle_report(task: dict[str, Any], text: str, at: float) -> None:
    """Replace the task's last report with a done report the watch has already
    seen. The settled flag lets the user window's end tell it from a real one."""
    task["report"] = {"kind": "done", "text": text, "at": at, "settled": True}
    task.setdefault("seen", {})["report_at"] = at


def user_window() -> float:
    """How long after the user's last prompt a worker stays with the user, in seconds."""
    return settings()["user_window_minutes"] * 60


def window_reset(task: dict[str, Any]) -> float:
    """When the user last handed the task to the driver: a wrap or snooze report,
    or a wake. The user's prompts before it no longer count."""
    reports: list[dict[str, Any]] = task.get("reports") or []
    ended = [r["at"] for r in reports if r["kind"] in ENDED_BY_USER]
    return max([*ended, task.get("user_reset") or 0])


def in_window(task: dict[str, Any], at: float | None, now: float) -> bool:
    """Whether a user prompt typed at this time keeps the worker with the user."""
    return at is not None and at > window_reset(task) and now - at < user_window()


def with_user(
    task: dict[str, Any], agent: dict[str, Any] | None, now: float
) -> float | None:
    """When the user last typed in the worker's pane, while the worker is with
    the user, else None.

    A worker is with the user for user_window after the user's last prompt in
    its pane. A snoozed task has no pane, and an unreadable transcript counts
    as no prompt.
    """
    if task.get("snoozed"):
        return None
    try:
        at = user_prompt_at(task, agent)
    except (MotoError, OSError):
        return None
    return at if at is not None and in_window(task, at, now) else None


def mark_seen(task: dict[str, Any], live: dict[str, dict[str, Any]]) -> None:
    """Treat the pane's current state and the last report as already seen."""
    agent = live.get(task["pane_id"])
    report: dict[str, Any] = task.get("report") or {}
    task["seen"] = {
        "status": agent.get("agent_status") if agent else "gone",
        "seq": agent.get("state_change_seq") if agent else None,
        "report_at": report.get("at"),
    }


def drop_held(tasks: dict[str, dict[str, Any]]) -> None:
    """Remove what moto hold left behind: the held flag, and the held mark in
    the pane of each task that still has the flag.

    moto hold is gone. A task kept its flag for as long as its pane had the
    mark, so the flag also says which panes to clear. Dropping it in the same
    update makes this run once. A snoozed task's pane id may belong to another
    worker by now, so it gets no call.
    """
    for task in tasks.values():
        if "held" in task:
            del task["held"]
            if not task.get("snoozed"):
                backend.clear_held_mark(task["pane_id"])


def pane_owner(tasks: dict[str, dict[str, Any]], pane_id: str) -> str | None:
    return next((n for n, t in tasks.items() if t["pane_id"] == pane_id), None)
