from __future__ import annotations

import argparse
import fcntl
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from moto.common import (
    JOB_BEAT_STALE_SECONDS,
    JOB_FOOTER,
    JOB_TAG,
    PACKAGE,
    SELF,
    MotoError,
    age,
    clock,
    exit_on_signal,
    run,
    state_dir,
)
from moto.driverstate import wake_driver
from moto.jobstate import (
    due,
    job_event,
    jobs_dir,
    jobs_for_update,
    load_jobs,
    occurrence,
    read_jobs,
    run_gate,
    running,
)
from moto.spawning import start_worker
from moto.whens import run_when, when_tick
from moto.whenstore import read_whens, when_rows


def job_brief(job: dict[str, Any], gate_output: str, broken: str | None) -> str:
    """What a job hands the driver or a worker: its brief, then what it found."""
    parts = [str(job["brief"]).strip()]
    if broken:
        parts.append(f"The job's check failed, so this ran anyway: {broken}")
    elif gate_output:
        parts.append(f"What the job's check found:\n\n{gate_output}")
    return "\n\n".join(parts)


def deliver(name: str, job: dict[str, Any], verdict: str, output: str) -> str:
    """Hand a due job to the driver or to a new worker, and say what happened.

    A broken gate wakes the driver either way. For a worker job it leaves a note
    instead of spawning, because starting an agent on a broken premise is worse
    than not starting one.
    """
    broken = output if verdict == "broken" else None
    text = job_brief(job, output, broken)
    if job["deliver"] == "driver" or broken:
        lead = f"The scheduled job {name} fired."
        return wake_driver(name, f"{lead}\n\n{text}")
    spec = {key: job.get(key) for key in ("repo", "worktree", "base", "name", "title")}
    spec["name"] = job.get("agent") or name
    info = start_worker(spec, f"{JOB_TAG} {text}\n\n{JOB_FOOTER}\n", None)
    return f"started {info['agent']}"


def run_job(name: str, job: dict[str, Any], when: float, trigger: str) -> str:
    """Run one job: stamp it, gate it, deliver it, and record the outcome.

    The stamp and the lock come before the gate, never after, so a loop killed
    between the check and the spawn cannot fire the same occurrence twice.
    """
    with running(name) as free:
        if not free:
            return "still running, so this occurrence is skipped"
        with jobs_for_update() as jobs:
            jobs.setdefault(name, {})["ran_at"] = when
        verdict, output = run_gate(job)
        if verdict == "skip":
            outcome = "nothing to do"
        else:
            try:
                outcome = deliver(name, job, verdict, output)
            except (MotoError, OSError, subprocess.TimeoutExpired) as error:
                outcome = f"failed: {error}"
            if verdict == "broken":
                outcome = f"broken gate, {outcome}"
        with jobs_for_update() as jobs:
            jobs.setdefault(name, {})["outcome"] = {"text": outcome, "at": time.time()}
        job_event("job", name, outcome=outcome, verdict=verdict, trigger=trigger)
        return outcome


def tick(now: float) -> list[str]:
    """One pass over the job files and the checks: everything due, run. One line
    per thing done."""
    jobs, problems = load_jobs()
    lines = [f"job file {problem}" for problem in problems]
    state = read_jobs()
    for name, job in sorted(jobs.items()):
        if job.get("enabled") is False:
            continue
        if name not in state:
            with jobs_for_update() as live:
                live.setdefault(name, {}).setdefault("added", now)
            continue
        when, missed = due(job, state.get(name, {}), now)
        if when is None:
            continue
        if missed:
            with jobs_for_update() as live:
                live.setdefault(name, {})["ran_at"] = when
                live[name]["outcome"] = {"text": missed, "at": now}
            job_event("job", name, outcome=missed, verdict="missed", trigger="schedule")
            lines.append(f"{name}: {missed}")
            continue
        lines.append(f"{name}: {run_job(name, job, when, 'schedule')}")
    return lines + when_tick(now)


def job_beat_path() -> Path:
    return state_dir() / "jobs.beat"


def job_loop_problem() -> str | None:
    """Why no job loop is ticking, or None when one is.

    The loop runs in a Herdr pane and nothing restarts it, so a dead loop has to
    look different from a quiet morning.
    """
    try:
        pid = int(job_beat_path().read_text().split()[0])
        silent = time.time() - job_beat_path().stat().st_mtime
    except (OSError, ValueError, IndexError):
        return "no moto job loop is running"
    try:
        if "moto" not in run(["ps", "-p", str(pid), "-o", "command="]):
            return "no moto job loop is running"
    except MotoError:
        return "no moto job loop is running"
    if silent > JOB_BEAT_STALE_SECONDS:
        return f"moto job loop (pid {pid}) last ticked {age(silent)} ago"
    return None


def job_rows(now: float) -> list[dict[str, Any]]:
    jobs, problems = load_jobs()
    state = read_jobs()
    rows = [
        {
            "name": name,
            "enabled": job.get("enabled") is not False,
            "deliver": job["deliver"],
            "brief": job["brief_source"],
            "next": occurrence(job, now, ahead=True),
            "outcome": state.get(name, {}).get("outcome"),
            "note": state.get(name, {}).get("note"),
        }
        for name, job in sorted(jobs.items())
    ]
    return rows + [{"name": problem, "broken": True} for problem in problems]


def print_jobs(now: float) -> None:
    rows = job_rows(now)
    checks = when_rows()
    if not rows and not checks:
        return
    print("\nJobs:")
    if problem := job_loop_problem():
        print(f"  {problem}")
    for row in rows:
        if row.get("broken"):
            print(f"{row['name']} · unusable job file")
            continue
        when = row["next"]
        nxt = clock(when) if when else "never"
        state = "" if row["enabled"] else " · disabled"
        brief = f"brief {row['brief']}"
        print(f"{row['name']} · {row['deliver']} · {brief} · next {nxt}{state}")
        if outcome := row["outcome"]:
            print(f"  last ({age(now - outcome['at'])} ago): {outcome['text']}")
        if row["note"]:
            print("  a note is waiting for the driver")
    for row in checks:
        to = f"wakes {row['target']}" if row["target"] else "driver"
        print(
            f"{row['name']} · check · {to} · every {age(row['every'])}"
            + f" · next in {age(row['next'] - now)}"
            + f" · expires in {age(row['expires'] - now)}"
        )
        print(f"  check: {row['check']}")
        if last := row["last"]:
            ago = age(now - last["at"])
            if last["verdict"] == "error":
                text = f"error, {row['errors']} in a row: {last['text']}"
            else:
                text = "not yet"
            print(f"  last ({ago} ago): {text}")


def cmd_job_list(args: argparse.Namespace) -> int:
    now = time.time()
    if args.json:
        rows = [{"kind": "job"} | row for row in job_rows(now)]
        print(json.dumps(rows + when_rows(), indent=2))
        return 0
    if not job_rows(now) and not when_rows():
        print(f"No job files in {jobs_dir()}, and no checks.")
        return 0
    print_jobs(now)
    return 0


def cmd_job_run(args: argparse.Namespace) -> int:
    if args.name in read_whens():
        print(f"{args.name}: {run_when(args.name, time.time(), 'manual')}")
        return 0
    jobs, problems = load_jobs()
    if args.name not in jobs:
        hint = f" ({'; '.join(problems)})" if problems else ""
        raise MotoError(f"No job named {args.name} in {jobs_dir()}{hint}")
    print(f"{args.name}: {run_job(args.name, jobs[args.name], time.time(), 'manual')}")
    return 0


def cmd_job_tick(_: argparse.Namespace) -> int:
    for line in tick(time.time()) or ["nothing due"]:
        print(line)
    return 0


def source_mtime(source: Path) -> float | None:
    """The newest change to the package's Python files, or None."""
    try:
        return max(f.stat().st_mtime for f in source.glob("*.py"))
    except (OSError, ValueError):
        return None


def compiles(source: Path) -> bool:
    """Whether every Python file in the package compiles."""
    try:
        for f in source.glob("*.py"):
            compile(f.read_bytes(), str(f), "exec")
    except (OSError, SyntaxError, ValueError):
        return False
    return True


def cmd_job_loop(args: argparse.Namespace) -> int:
    """The long-lived scheduler.

    Python reads the package once, so a loop that runs for days would keep the
    code it started with and never learn of a feature added since. Once a file
    in the package changes and all of them still compile, the loop replaces
    itself with the new code, keeping its pid, pane and arguments. A file that
    does not compile leaves it on the old code until the next edit.
    """
    signal.signal(signal.SIGTERM, exit_on_signal)
    directory = state_dir()
    directory.mkdir(parents=True, exist_ok=True)
    source = PACKAGE
    loaded = source_mtime(source)
    with open(directory / "job-loop.lock", "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("Another moto job loop is already running.")
            return 0
        print(f"moto job loop: every {args.every}s over {jobs_dir()}", flush=True)
        try:
            while True:
                job_beat_path().write_text(f"{os.getpid()}\n")
                for line in tick(time.time()):
                    print(f"{clock(time.time())} {line}", flush=True)
                time.sleep(args.every)
                mtime = source_mtime(source)
                if mtime == loaded:
                    continue
                loaded = mtime
                if not compiles(source):
                    print(f"{source} changed but does not compile", flush=True)
                    continue
                print(f"{source} changed, so the loop restarts on it", flush=True)
                # The lock file is not inheritable, so exec releases the lock
                # for the new code to take.
                try:
                    os.execv(SELF[0], [*SELF, *sys.argv[1:]])
                except OSError as error:
                    print(f"could not restart on {source}: {error}", flush=True)
        finally:
            job_beat_path().unlink(missing_ok=True)
