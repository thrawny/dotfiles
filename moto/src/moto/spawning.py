from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any

from moto.common import (
    BRIEF_FOOTER,
    CHILD_FOOTER,
    DRIVER_ROLE,
    MODEL_FLAGS,
    MOTO_HOME,
    SPAWN_DEFAULTS,
    WORKER_ENV,
    MotoError,
    run,
)
from moto.roles import role_file, role_folder
from moto.store import caller, read_tasks, record, tag, tasks_for_update


def start_worker(
    spec: dict[str, Any],
    prompt: str,
    parent: str | None,
    requested_by: str | None = None,
) -> dict[str, Any]:
    """Open a worker's pane on this prompt and record its task.

    spec holds the spawn flags; prompt is the whole first message, its tag and
    footer included, because a scheduled job tags and footers its workers
    differently from the driver.
    """
    command = ["spawn-session", "--json", "--repo", str(spec["repo"])]
    for flag in (
        "cwd",
        "worktree",
        "base",
        "name",
        "title",
        "resume",
        "pane",
        *MODEL_FLAGS,
    ):
        if value := spec.get(flag):
            command += [f"--{flag}", str(value)]
    if role := spec.get("role"):
        command += ["--env", f"MOTO_ROLE={role}"]
    if not spec.get("worktree") and not spec.get("pane"):
        command += ["--env", f"{WORKER_ENV}=1"]
    if parent:
        command.append("--child")
    # Worktree creation, agent startup and the first prompt each wait on Herdr.
    output = run(command, timeout=600, stdin=prompt)
    try:
        info: dict[str, Any] = json.loads(output)
    except ValueError as error:
        raise MotoError(f"spawn-session printed no JSON: {output.strip()}") from error
    now = time.time()
    with tasks_for_update() as tasks:
        tasks[info["agent"]] = {
            "agent": info["agent"],
            "repo": info["repo"],
            "branch": info.get("branch"),
            "pane_id": info["pane_id"],
            "workspace_id": info["workspace_id"],
            "tab_id": info["tab_id"],
            "cwd": info["cwd"],
            "title": spec.get("title"),
            "started": now,
            "told": now,
            "report": None,
            "pr": None,
            "seen": {"status": "working"},
        } | ({"parent": parent} if parent else {})
        if requested_by:
            tasks[info["agent"]]["requested_by"] = requested_by
        if role:
            tasks[info["agent"]]["role"] = role
        # Kept so wake resumes the session on the model it started with.
        for flag in MODEL_FLAGS:
            if value := spec.get(flag):
                tasks[info["agent"]][flag] = value
        record(
            "spawn",
            info["agent"],
            repo=info["repo"],
            branch=info.get("branch"),
            worktree=info["cwd"] if info.get("branch") else None,
            title=spec.get("title"),
            session=spec.get("resume"),
            parent=parent,
            requested_by=requested_by,
            model=spec.get("model"),
            effort=spec.get("effort"),
            role=role,
        )
    return info


def cmd_spawn(args: argparse.Namespace) -> int:
    brief = sys.stdin.read().strip()
    if not brief:
        raise MotoError("Pass the task brief on stdin")
    # A worker that starts its own worker watches it itself, unless it hands the
    # task to the driver, which then treats it as one it started.
    worker = caller(read_tasks())
    requested_by = worker if getattr(args, "to_driver", False) else None
    parent = None if requested_by else worker
    footer = CHILD_FOOTER.format(parent=parent) if parent else BRIEF_FOOTER
    spec = {
        flag: getattr(args, flag, None)
        for flag in (
            "repo",
            "worktree",
            "base",
            "name",
            "title",
            "resume",
            "pane",
            *MODEL_FLAGS,
        )
    }
    for flag, default in SPAWN_DEFAULTS.items():
        spec[flag] = spec[flag] or default
    if role := getattr(args, "role", None):
        if role == DRIVER_ROLE:
            raise MotoError("The driver role is the driver's; moto focus starts it")
        if spec["worktree"] or spec["pane"]:
            raise MotoError(
                "--role sessions work in MOTO_HOME's own folder, so they take no"
                + " --worktree or --pane"
            )
        role_file(role)
        spec |= {
            "repo": MOTO_HOME.resolve(),
            "cwd": role_folder(spec["repo"]),
            "role": role,
        }
    elif not spec["repo"]:
        raise MotoError("Pass --repo, or --role for a session in MOTO_HOME")
    info = start_worker(
        spec, f"{tag(parent)} {brief}\n\n{footer}\n", parent, requested_by
    )
    if getattr(args, "json", False):
        print(json.dumps(info))
        return 0
    where = f"{Path(info['repo']).name} {info.get('branch') or '(main checkout)'}"
    print(f"Started {info['agent']} on {where}")
    if parent:
        print(
            f"{info['agent']}'s done, question and blocked reports arrive in this"
            + f" pane once your turn ends, tagged as in [{info['agent']} done]."
            + " Answer it with moto tell."
        )
    elif requested_by:
        print(
            f"The driver watches {info['agent']}, so you cannot moto tell it."
            + " To pass anything on, moto report to the driver."
        )
    return 0
