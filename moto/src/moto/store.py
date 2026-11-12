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
from moto.common import DRIVER_TAG, EVENTS_VERSION, MotoError, pending_events, state_dir
from moto.sessions import user_prompt


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


def hold_task(task: dict[str, Any], reason: str | None = None) -> None:
    """Stop the watch covering a task until moto resume, as moto hold does."""
    task["held"] = True
    show_hold(task)
    record("hold", task["agent"], **({"reason": reason} if reason else {}))


def show_hold(task: dict[str, Any], held: bool | None = None) -> None:
    """Make the task's pane show whether the user holds it, or the given state.

    A snoozed or closed task has no pane, and Herdr may have reused its id for
    another worker, so it gets no call.
    """
    if task.get("snoozed") or task.get("closed_at"):
        return
    backend.mark_held(task["pane_id"], bool(task.get("held")) if held is None else held)


def clear_hold_mark(task: dict[str, Any]) -> None:
    """Clear the mark of a held task whose pane is about to close or stay open
    without the task, leaving its held flag as the record of the task."""
    if task.get("held"):
        show_hold(task, False)


def end_hold(task: dict[str, Any]) -> None:
    """Hand a held task back and clear its mark in the pane."""
    task["held"] = False
    show_hold(task)


def mark_seen(task: dict[str, Any], live: dict[str, dict[str, Any]]) -> None:
    """Treat the pane's current state and the last report as already seen."""
    agent = live.get(task["pane_id"])
    report: dict[str, Any] = task.get("report") or {}
    task["seen"] = {
        "status": agent.get("agent_status") if agent else "gone",
        "seq": agent.get("state_change_seq") if agent else None,
        "report_at": report.get("at"),
    }
    try:
        # Only a user turn after this one holds the task again.
        task["seen"]["user_turn"] = user_prompt(task, agent)
    except (MotoError, OSError):
        pass  # the watch records the first one it can read


def resume(task: dict[str, Any], live: dict[str, dict[str, Any]]) -> None:
    """Hand a held task back, treating what happened while held as seen."""
    end_hold(task)
    mark_seen(task, live)


def pane_owner(tasks: dict[str, dict[str, Any]], pane_id: str) -> str | None:
    return next((n for n, t in tasks.items() if t["pane_id"] == pane_id), None)
