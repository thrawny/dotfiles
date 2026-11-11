from __future__ import annotations

import argparse
import subprocess
import time
from typing import Any

from moto.closing import cmd_close
from moto.common import MotoError, age
from moto.driverstate import wake_driver
from moto.jobstate import job_event, running, state_for_update
from moto.reporting import tell_task
from moto.snoozing import wake_task
from moto.store import read_tasks
from moto.whenstore import WHEN_ERROR_LIMIT, check_verdict, read_whens, tail


def when_tick(now: float) -> list[str]:
    """Every check that is due, run, and every one past its expiry, given up."""
    lines: list[str] = []
    for name, entry in sorted(read_whens().items()):
        if now >= entry["expires"]:
            lines.append(f"{name}: {expire_when(name)}")
        elif now >= entry["next"]:
            lines.append(f"{name}: {run_when(name, now, 'schedule')}")
    return lines


def run_when(name: str, now: float, trigger: str) -> str:
    """Run one check, and fire it or note how it went.

    The next run is stamped before the check, as run_job stamps a job, and
    the check is removed before it fires, so it fires once.
    """
    with running(name) as free:
        if not free:
            return "still running, so this run is skipped"
        with state_for_update("when") as whens:
            if name not in whens:
                return "cancelled"
            entry = whens[name]
            entry["next"] = now + entry["every"]
        verdict, text = check_verdict(entry["check"], entry["cwd"])
        warn = False
        with state_for_update("when") as whens:
            if name not in whens:
                return "cancelled while it ran"
            if verdict in ("pass", "settled"):
                del whens[name]
            else:
                errors = whens[name]["errors"] + 1 if verdict == "error" else 0
                whens[name]["errors"] = errors
                whens[name]["last"] = {
                    "verdict": verdict,
                    "text": tail(text),
                    "at": time.time(),
                }
                # Once per streak, so a check that keeps failing says so once.
                warn = errors == WHEN_ERROR_LIMIT
        if verdict == "pass":
            outcome = fire_when(name, entry, text)
        elif verdict == "settled":
            outcome = settle_when(name, entry, text)
        elif warn:
            wake_driver(
                name,
                f"The check {name} failed {WHEN_ERROR_LIMIT} runs in a row:"
                + f" {text}\n\nIt keeps trying until it expires in"
                + f" {age(entry['expires'] - now)}; moto job rm {name} cancels it."
                + f" Its check: `{entry['check']}`. Its brief:\n\n{entry['brief']}",
            )
            outcome = f"{text}; told the driver"
        else:
            outcome = text if verdict == "error" else "not yet"
        job_event("when", name, outcome=outcome, verdict=verdict, trigger=trigger)
        return outcome


def fire_when(name: str, entry: dict[str, Any], output: str) -> str:
    """Deliver a check that passed: to the driver, or to the task it wakes.

    The task gets the brief as the driver's own message, since the driver
    wrote it, and the driver hears what happened either way.
    """
    printed = f"\n\nWhat it printed:\n\n{tail(output)}" if output else ""
    check, brief, target = entry["check"], entry["brief"], entry.get("target")
    if not target:
        lead = f"The check {name} passed: `{check}`."
        return wake_driver(name, f"{lead}\n\n{brief}{printed}")
    text = f"{brief}\n\nThe check `{check}` passed.{printed}"
    try:
        task = read_tasks().get(target)
        if task is None:
            raise MotoError(f"{target} is no longer a task")
        if task.get("snoozed"):
            wake_task(target, text, None)
            done = f"woke {target}"
        else:
            tell_task(target, text, None)
            done = f"told {target}"
    except (MotoError, OSError, subprocess.TimeoutExpired) as error:
        wake_driver(
            name,
            f"The check {name} passed, but could not reach {target}: {error}"
            + f"\n\nWhat it would have told {target}:\n\n{text}",
        )
        return f"failed: {error}; told the driver"
    wake_driver(name, f"The check {name} passed and {done} with its brief.")
    return done


def settle_when(name: str, entry: dict[str, Any], output: str) -> str:
    """End a check whose wait is over without waking anyone.

    A snoozed task it would have woken is closed, as moto close does: its work
    is merged, and nothing is left to tell it. A task that is not snoozed is
    working, so it is left alone. The driver hears only when the close fails.
    """
    target = entry.get("target")
    task = read_tasks().get(target) if target else None
    if not task or not task.get("snoozed"):
        return f"settled: {output.strip() or 'done'}"
    try:
        cmd_close(argparse.Namespace(agent=target, force=False))
    except (MotoError, OSError, subprocess.TimeoutExpired) as error:
        wake_driver(
            name,
            f"The check {name} settled ({output.strip() or 'done'}), but moto"
            + f" could not close {target}: {error}\n\nIt stays snoozed until you"
            + " close or wake it.",
        )
        return f"settled, but could not close {target}: {error}; told the driver"
    return f"settled; closed {target}"


def expire_when(name: str) -> str:
    """Remove a check that never passed, and tell the driver it gave up."""
    with state_for_update("when") as whens:
        entry = whens.pop(name, None)
    if entry is None:
        return "cancelled"
    target = f" for {entry['target']}" if entry.get("target") else ""
    last: dict[str, Any] = entry.get("last") or {}
    found = (
        f"\n\nIts last run ({last['verdict']}): {last['text']}"
        if last.get("text")
        else ""
    )
    wake_driver(
        name,
        f"The check {name}{target} gave up: `{entry['check']}` did not pass in"
        + f" {age(entry['expires'] - entry['created'])}. Its brief:"
        + f"\n\n{entry['brief']}{found}",
    )
    job_event("when", name, outcome="expired", verdict="expired", trigger="schedule")
    return "expired; told the driver"
