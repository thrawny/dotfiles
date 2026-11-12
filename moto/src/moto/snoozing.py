from __future__ import annotations

import argparse
import json
import os
import sys
import time
from typing import Any

from moto import backend
from moto.backend import live_agents
from moto.closing import branch_checkout, close_own, owns_worktree, release_adopted
from moto.common import CLAUDE_HOME, MODEL_FLAGS, WORKER_ENV, MotoError, run
from moto.roles import role_file
from moto.sessions import (
    find_session,
    session_cwd,
    session_dir,
    session_path,
    task_title,
    transcript,
)
from moto.store import (
    find_task,
    message_sender,
    read_tasks,
    record,
    resume,
    tag,
    tasks_for_update,
)
from moto.whenstore import (
    add_when,
    cancel_whens,
    check_verdict,
    pr_check_command,
    tail,
)


def cmd_snooze(args: argparse.Namespace) -> int:
    """Park a task, or on one that is snoozed already, replace its wake check."""
    reason = " ".join(args.reason).strip()
    check = getattr(args, "until_check", None)
    automerge = getattr(args, "automerge", False)
    if automerge and not getattr(args, "until_pr", None):
        raise MotoError("--automerge goes with --until-pr")
    if until_pr := getattr(args, "until_pr", None):
        if check:
            raise MotoError("Pass --until-check or --until-pr, not both")
        # The counts are the ones the check compares against, so take them
        # before the task closes.
        check = pr_check_command(until_pr, automerge)
    already = bool(find_task(read_tasks(), args.agent).get("snoozed"))
    if already and not check:
        raise MotoError(
            f"{args.agent} is already snoozed; pass --until-pr or --until-check"
            + " to replace its wake check"
        )
    if not already and not reason:
        raise MotoError("Say why it waits: moto snooze TASK REASON")
    if already:
        assert check
        return replace_check(args, check, reason)
    if check:
        # Run before anything closes, so a check that errors or already
        # passes leaves the task as it was.
        verdict, output = check_verdict(check, os.getcwd())
        if verdict == "error":
            raise MotoError(f"{output}; {args.agent} was not snoozed")
        if verdict in ("pass", "settled"):
            printed = f" It printed:\n{tail(output)}" if output else ""
            raise MotoError(
                f"The check is over already, so {args.agent} was not snoozed.{printed}"
            )
    live = live_agents()
    with tasks_for_update() as tasks:
        task = find_task(tasks, args.agent)
        if task.get("snoozed"):
            raise MotoError(f"{args.agent} is already snoozed")  # raced a snooze
        agent = live.get(task["pane_id"])
        if agent and agent.get("agent_status") == "working":
            raise MotoError(f"{args.agent} is mid-turn; snooze it once the turn ends")
        cwd, repo, linked = task["cwd"], task["repo"], owns_worktree(task)
        path = transcript(task, agent)
        if path:
            # A session the user started may have no name; its id is enough.
            title = task.get("title") or (agent or {}).get("terminal_title_stripped")
            session = path.stem
        else:
            title = task_title(task, agent)
            session = find_session(cwd, title)
        if linked:
            branch = task["branch"]
            exists = os.path.isdir(cwd)
            if exists and run(["git", "status", "--porcelain"], cwd=cwd).strip():
                raise MotoError(f"{args.agent}: the worktree has uncommitted changes")
            # All three keep the branch; wake checks it out again at the same path.
            if task.get("adopted"):
                release_adopted(task, tasks, True, False)
            elif exists:
                backend.remove_worktree(
                    task["pane_id"], task["tab_id"], cwd, repo, False
                )
        else:
            # The main checkout, or a worktree an adopted task shares, stays as
            # it is, on whatever branch it is on.
            try:
                branch = run(
                    ["git", "symbolic-ref", "--quiet", "--short", "HEAD"], cwd=cwd
                ).strip()
            except MotoError:
                branch = None  # detached HEAD
            close_own(task, tasks)
        task["snoozed"] = {
            "session": session,
            "title": title,
            "reason": reason,
            "repo": repo,
            "cwd": cwd,
            "branch": branch,
            "worktree": linked,
            "at": time.time(),
        }
        record("snooze", args.agent, **task["snoozed"])
    print(f"Snoozed {args.agent} (session {session}); bring it back with moto wake")
    if check:
        brief = f"You were snoozed waiting on: {reason}. That wait looks over."
        name, _ = add_when(
            check, brief, args.agent, None, args.every, args.expires, time.time()
        )
        if name is None:
            print(
                "The check was over while it snoozed; moto wake brings it back,"
                + " moto close closes it."
            )
        else:
            print(
                f"Check {name} wakes it once `{check}` passes, every {args.every},"
                + f" giving up in {args.expires}."
            )
    return 0


def replace_check(args: argparse.Namespace, check: str, reason: str) -> int:
    """Swap a snoozed task's wake check, leaving the task as it is.

    Nothing wakes, opens or is sent: the session, its worktree state and the
    snooze record stay, apart from the reason when a new one is given. The new
    check goes in first, so one that errors or already passes leaves the old
    check running. Every check that would wake the task then goes, the one the
    old snooze added included.
    """
    snooze = find_task(read_tasks(), args.agent)["snoozed"]
    reason = reason or snooze["reason"]
    brief = f"You were snoozed waiting on: {reason}. That wait looks over."
    name, output = add_when(
        check, brief, args.agent, None, args.every, args.expires, time.time()
    )
    if name is None:
        printed = f" It printed:\n{tail(output)}" if output else ""
        raise MotoError(
            f"The check is over already, so {args.agent}'s check was not"
            + f" replaced.{printed}"
        )
    old = cancel_whens(args.agent, keep=name)
    with tasks_for_update() as tasks:
        snoozed = find_task(tasks, args.agent).get("snoozed")
        if not snoozed:
            cancel_whens(args.agent)
            raise MotoError(f"{args.agent} was woken meanwhile; snooze it again")
        snoozed["reason"] = reason
        record("recheck", args.agent, reason=reason, check=check, replaced=old)
    gone = f", replacing {', '.join(old)}" if old else ""
    print(
        f"Check {name} wakes {args.agent} once `{check}` passes, every {args.every},"
        + f" giving up in {args.expires}{gone}. {args.agent} stays snoozed."
    )
    return 0


def cmd_wake(args: argparse.Namespace) -> int:
    text = " ".join(args.text).strip()
    sender = message_sender(read_tasks(), args.agent, text)
    session = wake_task(args.agent, text, sender)
    print(f"Woke {args.agent} on session {session}: moto watch covers it again")
    return 0


def check_branch(name: str, repo: str, branch: str | None) -> None:
    """Refuse a wake that cannot bring the task's own worktree back.

    The branch must still exist, and no checkout but a linked worktree may
    have it, because a wake into the main checkout would work beside the
    sessions already there.
    """
    if branch:
        try:
            run(
                ["git", "rev-parse", "--verify", "--quiet", f"refs/heads/{branch}"],
                cwd=repo,
            )
        except MotoError:
            branch = None
    if not branch:
        raise MotoError(
            f"{name}: its branch is gone from {repo}, so wake cannot bring its"
            + " worktree back; moto close or moto drop ends the task"
        )
    found = branch_checkout(repo, branch)
    if found and not found[1]:
        raise MotoError(
            f"{name}: {found[0]} has {branch} checked out, and it is not the"
            + f" task's own worktree; switch {found[0]} to another branch, then wake"
        )


def wake_task(name: str, text: str, sender: str | None) -> str:
    """Bring a snoozed task back with text as its prompt, and return its session."""
    task = find_task(read_tasks(), name)
    snooze: dict[str, Any] | None = task.get("snoozed")
    if not snooze:
        raise MotoError(f"{name} is not snoozed")
    session = snooze["session"]
    repo = snooze.get("repo") or task["repo"]
    cwd = snooze.get("cwd") or task["cwd"]
    linked = snooze.get("worktree", bool(task.get("branch")))
    branch = snooze.get("branch") or task.get("branch")
    path = session_path(cwd, session)
    if not path:
        raise MotoError(f"Session {session} is not in {CLAUDE_HOME / 'projects'}")
    if linked:
        check_branch(name, repo, branch)
    # claude --resume finds a session only from the folder it ran in, which
    # can be another checkout than the task's.
    if path.parent != session_dir(cwd):
        if linked:
            # Resuming there would leave the task's worktree behind.
            raise MotoError(f"Session {session} ran outside the worktree {cwd}: {path}")
        folder = session_cwd(path)
        if not folder or not os.path.isdir(folder):
            raise MotoError(f"Session {session} ran in a folder that is gone: {path}")
        cwd = folder
    role = task.get("role")
    # A checkout that stayed may be a worktree an adopted task shared, not the
    # repo. A role's folder is in MOTO_HOME, which spawn-session takes as is.
    checkout = repo if linked or role else cwd
    command = ["spawn-session", "--json", "--repo", checkout, "--name", task["agent"]]
    if role:
        role_file(role)
        command += ["--cwd", cwd, "--env", f"MOTO_ROLE={role}"]
    if linked:
        command += ["--worktree", str(branch), "--path", cwd]
    elif not os.path.isdir(cwd):
        raise MotoError(f"The checkout {cwd} is gone")
    else:
        command += ["--env", f"{WORKER_ENV}=1"]
    if title := snooze.get("title") or task.get("title"):
        command += ["--title", title]
    command += ["--resume", session]
    if task.get("parent"):
        command.append("--child")
    # claude --resume starts on the default model, not the one the session used.
    for flag in MODEL_FLAGS:
        if value := task.get(flag):
            command += [f"--{flag}", value]
    stdin = f"{tag(sender)} {text}\n" if text else ""
    output = run(command, timeout=600, stdin=stdin)
    try:
        info: dict[str, Any] = json.loads(output)
    except ValueError as error:
        raise MotoError(f"spawn-session printed no JSON: {output.strip()}") from error
    if info["cwd"] != cwd:
        print(
            f"moto: the worktree came back at {info['cwd']}, not {cwd}", file=sys.stderr
        )
    live = live_agents()
    with tasks_for_update() as tasks:
        task = find_task(tasks, name)
        for key in ("pane_id", "workspace_id", "tab_id", "cwd"):
            task[key] = info[key]
        task["title"] = title or task.get("title")
        task["session"] = session
        task.pop("closed_at", None)
        del task["snoozed"]
        resume(task, live)
        if text:
            task["told"] = time.time()
        record(
            "wake",
            name,
            session=session,
            message=text or None,
            cwd=info["cwd"],
            branch=branch if linked else None,
            worktree=linked,
            **{"from": sender or "driver"},
            pane_id=info["pane_id"],
        )
    return session
