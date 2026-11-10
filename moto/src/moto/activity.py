from __future__ import annotations

import os
import subprocess
from typing import Any

from moto.common import PR_TIMEOUT, MotoError, age, run, timestamp
from moto.sessions import user_turns


def since_report(
    task: dict[str, Any],
    agent: dict[str, Any] | None,
    pr: str | None,
    events: list[dict[str, Any]],
) -> dict[str, Any] | None:
    """What happened in a held or snoozed task since its last report.

    The driver sees none of it, so the report may be stale. A task with no
    report counts from the hold. Every source is optional: a missing
    transcript, checkout or answer from GitHub leaves its count out.
    """
    if report := task.get("report"):
        mark, since = "report", report["at"]
    else:
        holds = [
            e["ts"]
            for e in events
            if e.get("event") == "hold" and e.get("agent") == task["agent"]
        ]
        if not holds:
            return None
        mark, since = "hold", holds[-1]
    turns = user_turns(task, agent, since)
    updated = pr_updated(pr) if pr else None
    return {
        "since": mark,
        "at": since,
        "turns": len(turns),
        "last_turn_at": max(turns, default=None),
        "commits": commits_since(task, since),
        "pr_updated_at": updated if updated and updated > since else None,
    }


def commits_since(task: dict[str, Any], since: float) -> int | None:
    """How many commits the user made on the task's branch after since.

    Counting only the user's own commits leaves out what a merge or rebase
    brings in from the base branch. A snoozed worktree is gone, so its branch
    is read from the repo.
    """
    snooze: dict[str, Any] = task.get("snoozed") or {}
    cwd = task["cwd"] if os.path.isdir(task["cwd"]) else task["repo"]
    ref = snooze.get("branch") or "HEAD"
    try:
        email = run(["git", "config", "user.email"], cwd=cwd, timeout=5).strip()
        log = run(
            ["git", "log", f"--since=@{int(since)}", "--format=%ct"]
            + ["--fixed-strings", f"--author=<{email}>", ref, "--"],
            cwd=cwd,
            timeout=5,
        )
    except (MotoError, subprocess.TimeoutExpired):
        return None
    return len(log.split())


def pr_updated(url: str) -> float | None:
    """When the PR last changed, or None when GitHub does not answer in time."""
    try:
        output = run(
            ["gh", "pr", "view", url, "--json", "updatedAt", "--jq", ".updatedAt"],
            timeout=PR_TIMEOUT,
        )
    except (MotoError, subprocess.TimeoutExpired):
        return None
    return timestamp(output.strip())


def activity_line(info: dict[str, Any] | None, now: float) -> str | None:
    """since_report as one line, or None when nothing happened."""
    if not info:
        return None
    parts: list[str] = []
    if turns := info["turns"]:
        plural = "s" if turns != 1 else ""
        last = age(now - info["last_turn_at"])
        parts.append(f"{turns} turn{plural} with the user, last {last} ago")
    if commits := info["commits"]:
        parts.append(f"{commits} commit{'s' if commits != 1 else ''}")
    if updated := info["pr_updated_at"]:
        parts.append(f"PR updated {age(now - updated)} ago")
    return f"since the {info['since']}: " + " · ".join(parts) if parts else None
