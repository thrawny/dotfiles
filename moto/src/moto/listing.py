from __future__ import annotations

import argparse
import json
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any

from moto.activity import activity_line, since_report
from moto.afk import read_afk
from moto.backend import live_agents
from moto.common import MotoError, age, clock
from moto.scheduler import print_jobs
from moto.store import decorator_links, read_tasks, with_user


def cmd_list(args: argparse.Namespace) -> int:
    tasks = read_tasks()
    try:
        live: dict[str, dict[str, Any]] | None = live_agents()
    except MotoError:
        live = None
    links = decorator_links()
    now = time.time()
    rows: list[dict[str, Any]] = []
    # Tasks with the user and snoozed ones, whose last report may be stale.
    stale: list[tuple[dict[str, Any], dict[str, Any], dict[str, Any] | None]] = []
    for name, task in sorted(tasks.items()):
        agent = live.get(task["pane_id"]) if live is not None else None
        status = (
            "unknown" if live is None else (agent or {}).get("agent_status", "gone")
        )
        if task.get("snoozed"):
            status = "snoozed"
        elif status == "gone" and (closed := task.get("closed_at")):
            status = f"pane closed by hand {age(now - closed)} ago"
        pr = task.get("pr") or links.get(task["pane_id"], {}).get("pr")
        talking = with_user(task, agent, now)
        rows.append(
            {**task, "name": name, "status": status, "pr": pr, "user_at": talking}
        )
        if talking or task.get("snoozed"):
            stale.append((rows[-1], task, agent))
    if stale:
        # Each task's checks run side by side, so a slow GitHub costs PR_TIMEOUT once.
        with ThreadPoolExecutor() as pool:
            found = [
                pool.submit(since_report, task, agent, row["pr"])
                for row, task, agent in stale
            ]
        for (row, _, _), future in zip(stale, found, strict=True):
            row["since_report"] = future.result()
    if args.json:
        print(json.dumps(rows, indent=2))
        return 0
    if away := read_afk():
        print(
            f"The user is away since {clock(away['since'])} ({age(now - away['since'])})."
        )
        print(f"  Note: {away['note'] or 'none, so no instructions'}")
    if not rows:
        print("No tasks.")
        print_jobs(now)
        return 0
    if live is None:
        print("Herdr is unavailable, so live states are unknown.")
    snoozed = [row for row in rows if row.get("snoozed")]
    for row in rows:
        if row.get("snoozed"):
            continue
        branch = row.get("branch") or "main checkout"
        extra = ""
        if at := row.get("user_at"):
            extra = f" · with the user, last prompt {age(now - at)} ago"
        if role := row.get("role"):
            extra = f" · role {role}{extra}"
        if parent := row.get("parent"):
            extra += f" · started by {parent}"
        elif requested_by := row.get("requested_by"):
            extra += f" · requested by {requested_by}"
        print(
            f"{row['name']} · {Path(row['repo']).name} · {branch} · {row['status']}{extra}"
        )
        if row["pr"]:
            print(f"  PR: {row['pr']}")
        if report := row.get("report"):
            ago = age(now - report["at"])
            print(f"  {report['kind']} ({ago} ago): {report['text']}")
        if line := activity_line(row.get("since_report"), now):
            print(f"  {line}")
    if snoozed:
        print("\nSnoozed:")
    for row in snoozed:
        snooze = row["snoozed"]
        branch = snooze.get("branch") or row.get("branch") or "main checkout"
        ago = age(now - snooze["at"])
        role = f" · role {row['role']}" if row.get("role") else ""
        print(f"{row['name']} · {Path(row['repo']).name} · {branch} · {ago}{role}")
        print(f"  {snooze.get('reason') or 'no reason recorded'}")
        if row["pr"]:
            print(f"  PR: {row['pr']}")
        if line := activity_line(row.get("since_report"), now):
            print(f"  {line}")
    print_jobs(now)
    return 0
