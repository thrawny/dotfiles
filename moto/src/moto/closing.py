from __future__ import annotations

import argparse
import json
import os
import time
from pathlib import Path
from typing import Any

from moto.common import (
    BACKGROUND_WORKSPACE,
    BUSY,
    ENDED_BY_USER,
    MotoError,
    age,
    herdr,
    live_agents,
    run,
)
from moto.sessions import user_turns
from moto.store import find_task, hold_task, record, resume, tasks_for_update
from moto.whenstore import cancel_whens


def unsaved_work(cwd: str, branch: str | None = None) -> str | None:
    """Why removing this checkout would lose work, or None when it is safe.

    With a branch, cwd is the repo and the check covers that branch's commits,
    for a branch no worktree has checked out.
    """
    if branch is None and run(["git", "status", "--porcelain"], cwd=cwd).strip():
        return "the worktree has uncommitted changes"
    ref = f"refs/heads/{branch}" if branch else "HEAD"
    unpushed = int(
        run(["git", "rev-list", "--count", ref, "--not", "--remotes"], cwd=cwd)
    )
    if unpushed == 0:
        return None
    # A squash merge leaves the branch's own commits off every remote branch.
    pr: dict[str, Any]
    try:
        pr = json.loads(
            run(
                ["gh", "pr", "view", *([branch] if branch else [])]
                + ["--json", "state,headRefOid"],
                cwd=cwd,
            )
        )
    except (MotoError, ValueError):
        pr = {}
    head = run(["git", "rev-parse", ref], cwd=cwd).strip()
    if pr.get("state") == "MERGED" and pr.get("headRefOid") == head:
        return None
    commits = "1 commit is" if unpushed == 1 else f"{unpushed} commits are"
    return f"{commits} on no remote and in no merged PR"


def checkout_workspace(path: str) -> str | None:
    """The Herdr workspace opened on this checkout, if any.

    The background workspace never counts: its long-running tabs often sit in a
    repo's main checkout, and Herdr may record that checkout as its own.
    """
    workspaces = [
        w
        for w in herdr("workspace", "list")["workspaces"]
        if w.get("label") != BACKGROUND_WORKSPACE
    ]
    for workspace in workspaces:
        worktree: dict[str, Any] = workspace.get("worktree") or {}
        if worktree.get("checkout_path") == path:
            return workspace["workspace_id"]
    # `workspace create --cwd` records no checkout, so fall back to a pane
    # there, in the workspace named after the folder first.
    folder = Path(path).name
    labels = {w["workspace_id"]: w.get("label") for w in workspaces}
    found = [
        pane["workspace_id"]
        for pane in herdr("pane", "list")["panes"]
        if pane.get("cwd") == path and pane.get("workspace_id") in labels
    ]
    found.sort(key=lambda workspace_id: labels[workspace_id] != folder)
    return found[0] if found else None


def still_working(
    name: str, task: dict[str, Any], agent: dict[str, Any] | None
) -> str | None:
    """Why closing this worker could cut off its work, or None when it is safe.

    A done report alone is not enough: the user may have typed a new prompt
    into the pane since. A wrap or snooze report means the user ended the
    worker, so a busy pane is that turn finishing, but prompts after it still
    count, unless the user closed the pane after the last of them, which ends
    the worker too.
    """
    report: dict[str, Any] = task.get("report") or {}
    problems: list[str] = []
    status = agent.get("agent_status") if agent else None
    if status in BUSY and report.get("kind") not in ENDED_BY_USER:
        problems.append(f"{name} is {status}")
    since = report.get("at") or task.get("started") or 0
    turns = user_turns(task, agent, since)
    if (closed := task.get("closed_at")) and max(turns, default=0) <= closed:
        turns = []
    if turns:
        times = "time" if len(turns) == 1 else "times"
        mark = "its last report" if report else "it started"
        last = age(time.time() - max(turns))
        problems.append(
            f"the user typed in {name}'s pane {len(turns)} {times} since {mark},"
            + f" last {last} ago"
        )
    return "; ".join(problems) or None


def owns_worktree(task: dict[str, Any]) -> bool:
    """Whether close and snooze may remove the task's checkout.

    A spawned task with a branch made its own worktree. An adopted task ran
    where the user put it, often a tab in a repo workspace that other sessions
    share, so its checkout counts as its own only when it is a linked worktree
    that no pane outside the task's tab works in. A snoozed adopted task
    already settled this when it snoozed.
    """
    if not task.get("branch"):
        return False
    if not task.get("adopted"):
        return True
    if snooze := task.get("snoozed"):
        return bool(snooze.get("worktree"))
    try:
        top = Path(
            run(["git", "rev-parse", "--show-toplevel"], cwd=task["cwd"]).strip()
        )
    except (MotoError, OSError):
        return True  # the worktree is gone; its branch is still checked for work
    try:
        panes = herdr("pane", "list")["panes"]
    except MotoError:
        return False  # without Herdr nobody can tell who else works there
    for pane in panes:
        if pane.get("tab_id") == task["tab_id"]:
            continue
        for key in ("cwd", "foreground_cwd"):
            if (folder := pane.get(key)) and Path(folder).is_relative_to(top):
                return False
    return True


def release_adopted(task: dict[str, Any], own: bool, force: bool) -> None:
    """Close an adopted task's tab, and remove its worktree when it owns one.

    Only the tab goes, never the workspace, because the user may run other
    sessions as tabs beside it; Herdr closes a workspace with its last tab.
    """
    if not task.get("snoozed"):
        try:
            herdr("tab", "close", task["tab_id"])
        except MotoError:
            pass  # the tab is already gone
    if own and os.path.isdir(task["cwd"]):
        top = run(["git", "rev-parse", "--show-toplevel"], cwd=task["cwd"]).strip()
        flags = ["--force"] if force else []
        run(["git", "worktree", "remove", *flags, top], cwd=task["repo"], timeout=120)


def cmd_close(args: argparse.Namespace) -> int:
    live = {} if args.force else live_agents()
    with tasks_for_update() as tasks:
        task = find_task(tasks, args.agent)
        cwd, repo = task["cwd"], task["repo"]
        # A checkout close may not remove keeps its branch too.
        branch = task.get("branch") if owns_worktree(task) else None
        if not args.force and (
            # A snoozed task has no pane; Herdr may have reused its id.
            busy := still_working(
                args.agent,
                task,
                None if task.get("snoozed") else live.get(task["pane_id"]),
            )
        ):
            raise MotoError(
                f"{busy}; wait for it or ask the user, or pass --force to close anyway"
            )
        exists = os.path.isdir(cwd)
        if branch and not args.force:
            # A snoozed task's branch has no worktree, so check the branch itself.
            problem = unsaved_work(cwd) if exists else unsaved_work(repo, branch)
            if problem:
                raise MotoError(
                    f"{args.agent}: {problem}; pass --force to remove anyway"
                )
        if task.get("adopted"):
            release_adopted(task, bool(branch), args.force)
        elif branch:
            workspace = checkout_workspace(cwd)
            force = ["--force"] if args.force else []
            if workspace:
                herdr(
                    "worktree", "remove", "--workspace", workspace, *force, timeout=120
                )
            elif exists:
                run(["git", "worktree", "remove", *force, cwd], cwd=repo, timeout=120)
        else:
            try:
                herdr("tab", "close", task["tab_id"])
            except MotoError:
                pass  # the tab is already gone
        # Its commits are pushed or merged, so the local branch is a copy.
        if branch and not args.force:
            try:
                run(["git", "branch", "-D", branch], cwd=repo)
            except MotoError:
                pass
        record("close", args.agent, force=args.force, task=tasks.pop(args.agent))
    print(f"Closed {args.agent}")
    print_cancelled(args.agent)
    return 0


def cmd_drop(args: argparse.Namespace) -> int:
    with tasks_for_update() as tasks:
        find_task(tasks, args.agent)
        record("drop", args.agent, task=tasks.pop(args.agent))
    print(f"Dropped {args.agent}; its tab and worktree are untouched")
    print_cancelled(args.agent)
    return 0


def print_cancelled(agent: str) -> None:
    for name in cancel_whens(agent):
        print(f"Cancelled check {name}, which would have woken {agent}")


def cmd_hold(args: argparse.Namespace) -> int:
    with tasks_for_update() as tasks:
        hold_task(find_task(tasks, args.agent))
    print(f"Holding {args.agent}: moto watch skips it until moto resume")
    return 0


def cmd_resume(args: argparse.Namespace) -> int:
    live = live_agents()
    with tasks_for_update() as tasks:
        task = find_task(tasks, args.agent)
        if task.get("snoozed"):
            raise MotoError(f"{args.agent} is snoozed; bring it back with moto wake")
        resume(task, live)
        record("resume", args.agent)
    print(f"Resumed {args.agent}: moto watch covers it again")
    return 0
