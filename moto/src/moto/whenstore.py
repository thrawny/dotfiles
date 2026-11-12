from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
import time
from typing import Any

from moto.adopting import name_from
from moto.common import JOB_TICK_SECONDS, SELF, MotoError, run
from moto.jobstate import (
    job_event,
    jobs_dir,
    load_jobs,
    read_state,
    run_check,
    state_for_update,
)
from moto.store import caller, find_task, read_tasks

# One-off checks, which moto when adds and the job loop runs.
WHEN_EVERY = "10m"
WHEN_EXPIRES = "7d"
# Errors in a row before the driver hears that a check is broken, not waiting.
WHEN_ERROR_LIMIT = 3
# The exit code of a check that ends without waking anyone: its wait is over,
# and nothing needs the task. Any other non-zero exit waits.
SETTLED_EXIT = 3
# How many lines of a passing check's stdout go out with its brief.
WHEN_TAIL_LINES = 20
DURATION = re.compile(r"(\d+)([smhd])")
DURATION_UNITS = {"s": 1, "m": 60, "h": 3600, "d": 86400}


def parse_duration(text: str) -> int:
    """The seconds in a duration such as 90s, 30m, 1h or 7d."""
    match = DURATION.fullmatch(text.strip())
    if not match or not int(match.group(1)):
        raise MotoError(f"{text!r} is not a duration such as 30m, 1h or 7d")
    return int(match.group(1)) * DURATION_UNITS[match.group(2)]


def read_whens() -> dict[str, dict[str, Any]]:
    return read_state("when")


def check_verdict(command: str, cwd: str) -> tuple[str, str]:
    """A check's verdict, pass, settled, wait or error, and its text.

    Exit 0 passes and SETTLED_EXIT settles, which ends the check without
    waking anyone. Any other exit waits, quietly: a non-zero exit that
    writes to stderr is an error, as is 126 or 127, the shell finding no such
    command, or a check that could not start or timed out. Otherwise a broken
    check would look like a condition that never comes, until it expires.
    """
    code, out, err = run_check(command, cwd)
    if code == 0:
        return "pass", out
    if code is None:
        return "error", f"the check {err}"
    if code == SETTLED_EXIT and not err:
        return "settled", out
    if err or code in (126, 127) or code < 0:
        return "error", f"the check exited {code}: {err or out or 'no output'}"
    return "wait", out


def tail(text: str) -> str:
    return "\n".join(text.splitlines()[-WHEN_TAIL_LINES:])


UNTIL_PR_HELP = (
    "The check passes, and wakes the task with which of these fired, once the PR"
    + " is merged or closed, has a review decision (approved or changes"
    + " requested), has a review or comment newer than the snooze, conflicts"
    + " with its base branch, or fails a required CI check"
)
AUTOMERGE_HELP = (
    "With --automerge, something else merges the PR once it is approved with CI"
    + " green, so only what blocks the merge wakes the task: changes requested, a"
    + " new review comment or PR comment from someone other than the PR's author,"
    + " a conflict with the base branch, failing required CI, or the PR closed"
    + " without merging. An approval does not wake it. A merge does not wake it"
    + " either: the check ends quietly, and moto closes the snoozed task"
)
PR_REF = re.compile(
    r"(?:https?://[^/\s]+/)?(?P<repo>[\w.-]+/[\w.-]+)(?:/pull/|#)(?P<number>\d+)"
)


def parse_pr_ref(text: str) -> tuple[str, int]:
    """The repo and number in a PR URL or an owner/repo#N reference."""
    match = PR_REF.fullmatch(text.strip().rstrip("/"))
    if not match:
        raise MotoError(f"{text!r} is not a PR URL or owner/repo#N")
    return match["repo"], int(match["number"])


def gh_json(args: list[str]) -> Any:
    return json.loads(run(["gh", *args], timeout=60) or "null")


def pr_activity(repo: str, number: int, automerge: bool = False) -> tuple[int, int]:
    """The PR's review count and comment count, inline review comments included.

    With automerge, approvals and the PR author's own reviews and comments do
    not count: an approval is what the merge waits on, and the author is the
    task itself.
    """
    view = gh_json(
        ["pr", "view", str(number), "-R", repo, "--json", "reviews,comments,author"]
    )
    inline = gh_json(["api", "--paginate", f"repos/{repo}/pulls/{number}/comments"])
    reviews, comments, inline = view["reviews"], view["comments"], inline or []
    if automerge:
        author = (view.get("author") or {}).get("login")
        reviews = [
            r
            for r in reviews
            if r.get("state") != "APPROVED"
            and (r.get("author") or {}).get("login") != author
        ]
        comments = [
            c for c in comments if (c.get("author") or {}).get("login") != author
        ]
        inline = [c for c in inline if (c.get("user") or {}).get("login") != author]
    return len(reviews), len(comments) + len(inline)


def required_checks(repo: str, number: int) -> list[dict[str, Any]]:
    """The required CI checks on the PR's head commit, as gh reports them.

    A PR with no required checks, or a merged one, has none to report: gh
    says so on stderr and exits 1, which is not an error here.
    """
    result = subprocess.run(
        ["gh", "pr", "checks", str(number), "-R", repo, "--required"]
        + ["--json", "name,bucket"],
        capture_output=True,
        text=True,
        timeout=60,
        check=False,
    )
    if result.stdout.strip():
        return json.loads(result.stdout)
    if "no required checks" in result.stderr or "no checks" in result.stderr:
        return []
    raise MotoError(result.stderr.strip() or "gh pr checks failed")


def pr_reasons(
    view: dict[str, Any],
    checks: list[dict[str, Any]],
    seen: tuple[int, int],
    now: tuple[int, int],
    automerge: bool = False,
) -> list[str]:
    """Why a snoozed task's PR needs it again: one line per reason, none to wait.

    seen and now are (reviews, comments) at snooze time and now, counted as
    pr_activity counts them for the same automerge. A mergeable state of
    UNKNOWN is GitHub still working it out, so it never counts. With
    automerge, an approval is no reason. A merge is none either, but the
    caller settles that before it asks, so only a closed PR gets here.
    """
    number, base = view["number"], view["baseRefName"]
    reasons: list[str] = []
    if view["state"] != "OPEN":
        reasons.append(f"PR #{number} is {view['state'].lower()}")
        return reasons
    if view["reviewDecision"] == "APPROVED":
        if not automerge:
            reasons.append(f"PR #{number} is approved")
    elif view["reviewDecision"] == "CHANGES_REQUESTED":
        reasons.append(f"PR #{number} has changes requested")
    if now[0] > seen[0]:
        reasons.append(f"PR #{number} has {now[0] - seen[0]} new review(s)")
    if now[1] > seen[1]:
        reasons.append(f"PR #{number} has {now[1] - seen[1]} new comment(s)")
    if view["mergeable"] == "CONFLICTING":
        reasons.append(f"PR #{number} conflicts with {base}")
    if failed := [c["name"] for c in checks if c["bucket"] == "fail"]:
        reasons.append(f"PR #{number} has failing required CI: {', '.join(failed)}")
    return reasons


def cmd_pr_check(args: argparse.Namespace) -> int:
    """The check that --until-pr stores.

    Exit 0 and say why, or exit 1 quietly. With automerge, a merged PR exits
    SETTLED_EXIT instead: nothing needs the task, and the check is over.
    """
    repo, number = parse_pr_ref(args.pr)
    automerge = args.automerge
    view = gh_json(
        ["pr", "view", str(number), "-R", repo]
        + ["--json", "number,state,reviewDecision,mergeable,baseRefName"]
    )
    if automerge and view["state"] == "MERGED":
        print(f"PR #{number} is merged")
        return SETTLED_EXIT
    now = pr_activity(repo, number, automerge)
    # A closed PR needs no CI read, and a PR with no new activity is not waiting on it.
    checks = required_checks(repo, number) if view["state"] == "OPEN" else []
    reasons = pr_reasons(view, checks, (args.reviews, args.comments), now, automerge)
    print("\n".join(reasons))
    return 0 if reasons else 1


def pr_check_command(pr: str, automerge: bool = False) -> str:
    """The shell check that waits on a PR, with its review and comment counts now."""
    repo, number = parse_pr_ref(pr)
    reviews, comments = pr_activity(repo, number, automerge)
    return (
        f"{shlex.join(SELF)} pr-check {shlex.quote(f'{repo}#{number}')}"
        + f" --reviews {reviews} --comments {comments}"
        + (" --automerge" if automerge else "")
    )


def add_when(
    check: str,
    brief: str,
    target: str | None,
    name: str | None,
    every: str,
    expires: str,
    now: float,
) -> tuple[str | None, str]:
    """Run a new check once, and keep it unless that run settles it.

    Returns the check's name, or None when it already passes or is settled,
    with what that run printed. An error refuses the check, so a typo never
    waits a week.
    """
    seconds, lasts = parse_duration(every), parse_duration(expires)
    if seconds < JOB_TICK_SECONDS:
        raise MotoError(f"--every is at least {JOB_TICK_SECONDS}s, the loop's tick")
    cwd = os.getcwd()
    verdict, text = check_verdict(check, cwd)
    if verdict == "error":
        raise MotoError(f"{text}; fix it, or make it exit non-zero quietly")
    if verdict in ("pass", "settled"):
        return None, text
    whens = read_whens()
    jobs, _ = load_jobs()
    taken: set[str | None] = {
        *whens,
        *jobs,
        *(p.stem for p in jobs_dir().glob("*.toml")),
    }
    if name and name in taken:
        raise MotoError(f"A job or check named {name} exists already")
    name = name or name_from([target, brief], taken)
    entry = {
        "check": check,
        "brief": brief,
        "target": target,
        "cwd": cwd,
        "every": seconds,
        "created": now,
        "expires": now + lasts,
        "next": now + seconds,
        "errors": 0,
        "last": {"verdict": verdict, "text": tail(text), "at": now},
    }
    with state_for_update("when") as stored:
        stored[name] = entry
    job_event("when-add", name, check=check, brief=brief, target=target)
    return name, text


def cancel_whens(target: str, keep: str | None = None) -> list[str]:
    """Remove the checks that would wake target, except keep, a new one."""
    with state_for_update("when") as whens:
        names = [n for n, e in whens.items() if e.get("target") == target and n != keep]
        for name in names:
            del whens[name]
    for name in names:
        job_event("when-cancel", name, target=target)
    return names


def when_rows() -> list[dict[str, Any]]:
    return [
        {"name": name, "kind": "when"}
        | {k: entry.get(k) for k in ("check", "target", "every", "next", "expires")}
        | {"last": entry.get("last"), "errors": entry.get("errors", 0)}
        for name, entry in sorted(read_whens().items())
    ]


def cmd_when(args: argparse.Namespace) -> int:
    brief = " ".join(args.text).strip() or sys.stdin.read().strip()
    if not brief:
        raise MotoError("Pass the brief as arguments or on stdin")
    tasks = read_tasks()
    if worker := caller(tasks):
        raise MotoError(
            f"{worker} is a worker, and only the driver adds checks;"
            + " moto report what you wait on instead"
        )
    if args.wake:
        find_task(tasks, args.wake)
    if bool(args.check) == bool(args.until_pr):
        raise MotoError("Pass --check or --until-pr, one of them")
    if args.automerge and not args.until_pr:
        raise MotoError("--automerge goes with --until-pr")
    check = args.check or pr_check_command(args.until_pr, args.automerge)
    name, output = add_when(
        check, brief, args.wake, args.name, args.every, args.expires, time.time()
    )
    if name is None:
        print("The check is over already, so nothing was scheduled.")
        if output:
            print(f"It printed:\n{tail(output)}")
        return 0
    to = f"wakes {args.wake}" if args.wake else "tells the driver"
    print(
        f"Added check {name}: every {args.every}, it {to} once the check passes,"
        + f" and gives up in {args.expires}. moto job rm {name} cancels it."
    )
    return 0


def cmd_job_rm(args: argparse.Namespace) -> int:
    with state_for_update("when") as whens:
        entry = whens.pop(args.name, None)
    if entry is None:
        path = jobs_dir() / f"{args.name}.toml"
        if path.exists():
            raise MotoError(f"{args.name} is a job file; delete {path} to remove it")
        raise MotoError(f"No check named {args.name}")
    job_event("when-cancel", args.name, target=entry.get("target"))
    print(f"Cancelled {args.name}")
    return 0
