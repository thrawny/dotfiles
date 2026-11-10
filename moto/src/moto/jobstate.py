from __future__ import annotations

import contextlib
import fcntl
import json
import os
import signal
import subprocess
import tomllib
from collections.abc import Generator
from contextlib import contextmanager, suppress
from datetime import datetime, timedelta
from datetime import time as dt_time
from pathlib import Path
from typing import Any, cast

from moto.common import (
    GATE_SKIP,
    GATE_TIMEOUT,
    JOB_FIELDS,
    MOTO_HOME,
    WEEKDAYS,
    MotoError,
    age,
    state_dir,
)
from moto.store import record, tasks_for_update


def jobs_dir() -> Path:
    """Where job files live, beside the work skills in MOTO_HOME."""
    return MOTO_HOME / "jobs"


def read_state(kind: str) -> dict[str, dict[str, Any]]:
    """The entries in kind.json in the state folder, under the key kind."""
    path = state_dir() / f"{kind}.json"
    try:
        data = json.loads(path.read_text())
    except FileNotFoundError:
        return {}
    except ValueError as error:
        raise MotoError(f"{path} is not valid JSON") from error
    return data.get(kind, {})


@contextmanager
def state_for_update(kind: str) -> Generator[dict[str, dict[str, Any]]]:
    """kind.json under its own lock, written back on exit if it changed."""
    directory = state_dir()
    directory.mkdir(parents=True, exist_ok=True)
    with open(directory / f"{kind}.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        entries = read_state(kind)
        before = json.dumps(entries, sort_keys=True)
        yield entries
        if json.dumps(entries, sort_keys=True) != before:
            path = directory / f"{kind}.json"
            tmp = path.with_suffix(".tmp")
            tmp.write_text(json.dumps({kind: entries}, indent=2) + "\n")
            tmp.replace(path)


def read_jobs() -> dict[str, dict[str, Any]]:
    """Each job's scheduling state: last run, last outcome and pending note."""
    return read_state("jobs")


def jobs_for_update() -> contextlib.AbstractContextManager[dict[str, dict[str, Any]]]:
    """Job state under its own lock, not the task lock, because a job's state
    changes while it spawns a worker, and spawning takes the task lock itself."""
    return state_for_update("jobs")


def job_event(event: str, name: str, **fields: Any) -> None:
    """Append a job event to the same log the tasks use, so moto log prints it."""
    with tasks_for_update():
        record(event, name, **fields)


def parse_times(values: Any) -> list[tuple[int, int]]:
    """The HH:MM strings in a job's `at`, as hour and minute pairs."""
    if not isinstance(values, list) or not values:
        raise ValueError("at must be a non-empty list of HH:MM times")
    given = cast("list[Any]", values)
    times: list[tuple[int, int]] = []
    for value in given:
        hour, _, minute = str(value).partition(":")
        if not hour.isdigit() or not minute.isdigit():
            raise ValueError(f"{value!r} is not an HH:MM time")
        if not (0 <= int(hour) <= 23 and 0 <= int(minute) <= 59):
            raise ValueError(f"{value!r} is not a time of day")
        times.append((int(hour), int(minute)))
    return sorted(set(times))


def parse_days(values: Any) -> set[int]:
    """The weekdays a job may run on, as Monday 0 to Sunday 6.

    Takes names, comma lists and ranges: mon, mon-fri, "sat,sun". A range reads
    forwards and wraps, so fri-mon is Friday through Monday.
    """
    if values is None:
        return set(range(7))
    if not isinstance(values, list):
        raise ValueError('days must be a list, as in ["mon-fri"]')
    given = cast("list[Any]", values)
    days: set[int] = set()
    for value in given:
        for part in str(value).replace(" ", "").lower().split(","):
            if not part:
                continue
            start, _, end = part.partition("-")
            if start not in WEEKDAYS or (end and end not in WEEKDAYS):
                raise ValueError(f"{part!r} is not a weekday or a range of them")
            first = WEEKDAYS[start]
            span = (WEEKDAYS[end] - first) % 7 if end else 0
            days.update((first + step) % 7 for step in range(span + 1))
    if not days:
        raise ValueError("days names no weekday")
    return days


def job_problem(job: dict[str, Any]) -> str | None:
    """Why a job file cannot be used, or None. Rejects rather than guesses."""
    try:
        parse_times(job.get("at"))
        parse_days(job.get("days"))
    except ValueError as error:
        return str(error)
    deliver = job.get("deliver")
    if deliver not in ("driver", "worker"):
        return 'deliver must be "driver" or "worker"'
    if not str(job.get("brief") or "").strip():
        return "no brief, and no .md file of the same name beside it"
    if deliver == "worker" and not job.get("repo"):
        return "a worker job needs a repo"
    if deliver == "worker" and not job.get("title"):
        return "a worker job needs a title, the Claude session name"
    stale = job.get("stale_after")
    if stale is not None and (not isinstance(stale, int) or stale <= 0):
        return "stale_after must be a whole number of minutes"
    unknown = set(job) - JOB_FIELDS
    if unknown:
        return f"unknown field(s): {', '.join(sorted(unknown))}"
    return None


def load_jobs() -> tuple[dict[str, dict[str, Any]], list[str]]:
    """Every usable job file, and one line per file that is not.

    A job without a brief follows the .md file of the same name beside it, so
    the brief points the agent at that file rather than inlining it.
    A broken file is reported and skipped rather than stopping the tick, so one
    bad edit cannot silence every other job.
    """
    jobs: dict[str, dict[str, Any]] = {}
    problems: list[str] = []
    directory = jobs_dir()
    if not directory.is_dir():
        return jobs, problems
    for path in sorted(directory.glob("*.toml")):
        try:
            job = tomllib.loads(path.read_text())
        except (OSError, ValueError) as error:
            problems.append(f"{path.name}: {error}")
            continue
        job["name"] = str(job.get("name") or path.stem)
        source = "inline"
        notes = path.with_suffix(".md")
        if not str(job.get("brief") or "").strip() and notes.is_file():
            job["brief"] = f"Follow {directory.name}/{notes.name}."
            source = notes.name
        if problem := job_problem(job):
            problems.append(f"{path.name}: {problem}")
            continue
        # Set after the check, which rejects fields a job file may not carry.
        job["brief_source"] = source
        jobs[job["name"]] = job
    return jobs, problems


def occurrence(job: dict[str, Any], now: float, ahead: bool) -> float | None:
    """The job's next run after now, or its last one at or before it."""
    times = parse_times(job.get("at"))
    days = parse_days(job.get("days"))
    today = datetime.fromtimestamp(now)
    for step in range(8):
        day = (today + timedelta(days=step if ahead else -step)).date()
        if day.weekday() not in days:
            continue
        for hour, minute in sorted(times, reverse=not ahead):
            when = datetime.combine(day, dt_time(hour, minute)).timestamp()
            if (when > now) if ahead else (when <= now):
                return when
    return None


def due(
    job: dict[str, Any], state: dict[str, Any], now: float
) -> tuple[float | None, str | None]:
    """The occurrence a job owes, and why it will be recorded missed instead.

    A job whose time passed while the laptop slept runs on the next tick, since
    the occurrence is read off the wall clock. stale_after opts out of that.
    A job owes nothing from before the loop first saw it, so a new job waits
    for its next slot.
    """
    when = occurrence(job, now, ahead=False)
    last = max(float(state.get("ran_at") or 0), float(state.get("added") or 0))
    if when is None or last >= when:
        return None, None
    stale = job.get("stale_after")
    if stale and now - when > float(stale) * 60:
        return when, f"missed by {age(now - when)}"
    return when, None


def run_gate(job: dict[str, Any]) -> tuple[str, str]:
    """A job's gate verdict and the text it produced.

    Shepherd's contract, copied deliberately: exit 0 runs the job, exit 75
    skips this occurrence, and anything else is a broken gate. A broken gate
    must not silently kill a schedule, so it is never treated as a skip; what
    happens instead depends on the delivery mode. The gate's stdout is kept and
    handed to the job, so a check that queried GitHub is not run twice.
    """
    gate = str(job.get("gate") or "").strip()
    if not gate:
        return "run", ""
    code, out, err = run_check(gate, MOTO_HOME)
    if code is None:
        return "broken", f"the gate {err}"
    if code == 0:
        return "run", out
    if code == GATE_SKIP:
        return "skip", out
    return "broken", f"the gate exited {code}: {err or out or 'no output'}"


def run_check(command: str, cwd: Path | str) -> tuple[int | None, str, str]:
    """Run a gate or a check: its exit code, stdout and stderr, stripped.

    The code is None when it could not start or ran past GATE_TIMEOUT, and
    stderr then says which. A cwd that is gone runs it from moto's own folder.
    """
    folder = cwd if os.path.isdir(cwd) else None
    try:
        # Its own process group, so a timeout kills what the command started too.
        process = subprocess.Popen(
            ["sh", "-c", command],
            cwd=folder,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
    except OSError as error:
        return None, "", f"could not start: {error}"
    try:
        out, err = process.communicate(timeout=GATE_TIMEOUT)
    except subprocess.TimeoutExpired:
        with suppress(OSError, ProcessLookupError):
            os.killpg(os.getpgid(process.pid), signal.SIGKILL)
        process.communicate()
        return None, "", f"still ran after {GATE_TIMEOUT}s, so it was killed"
    return process.returncode, out.strip(), err.strip()


@contextmanager
def running(name: str) -> Generator[bool]:
    """Whether this process got the lock that lets one run of a job or check
    at a time, held until the block ends."""
    directory = state_dir()
    directory.mkdir(parents=True, exist_ok=True)
    with open(directory / f"job-{name}.lock", "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            yield False
            return
        yield True
