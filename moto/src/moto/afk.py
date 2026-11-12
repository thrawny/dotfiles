from __future__ import annotations

import argparse
import json
import time
from pathlib import Path
from typing import Any

from moto.common import FINISHED, PR_URL, MotoError, clock, state_dir
from moto.store import record, tasks_for_update


def afk_path() -> Path:
    return state_dir() / "afk.json"


def read_afk() -> dict[str, Any] | None:
    try:
        return json.loads(afk_path().read_text())
    except (OSError, ValueError):
        return None


def cmd_afk(args: argparse.Namespace) -> int:
    """Record that the user is away, with their note exactly as written."""
    note = " ".join(args.text).strip()
    with tasks_for_update():
        away = read_afk()
        if away and not note:
            print(f"Already away since {clock(away['since'])}; the note is unchanged.")
            return 0
        since = away["since"] if away else time.time()
        previous = away["note"] if away else None
        afk_path().write_text(json.dumps({"since": since, "note": note}) + "\n")
        record("afk", "driver", note=note, since=since, previous=previous)
    verb = "Replaced the note" if away else "Away"
    print(f"{verb} since {clock(since)}: {note or 'no note, so no instructions'}")
    return 0


def cmd_back(_: argparse.Namespace) -> int:
    """End away mode and print what happened since it started."""
    with tasks_for_update() as tasks:
        away = read_afk()
        if away is None:
            raise MotoError("Not away; moto afk starts away mode")
        afk_path().unlink()
        record("back", "driver", since=away["since"], note=away["note"])
        brief = return_brief(away, read_events(), tasks)
    print("\n".join(brief))
    return 0


def return_brief(
    away: dict[str, Any], events: list[dict[str, Any]], tasks: dict[str, dict[str, Any]]
) -> list[str]:
    """The events since away mode started, in four groups, oldest first in each."""
    since = away["since"]
    recent = [e for e in events if e.get("ts", 0) >= since]
    prs: dict[str, str] = {}  # PR URL → the line for it, for tasks still open
    actions: list[str] = []
    finished: list[str] = []
    for event in recent:
        name, kind, at = event["agent"], event["event"], clock(event["ts"])
        if kind == "pr" and name in tasks:
            prs[event["pr"]] = f"{at} {name}: {event['pr']}"
        elif kind == "report" and event.get("kind") in FINISHED:
            finished.append(f"{at} {name} {event['kind']}: {event['text']}")
            if (match := PR_URL.search(event["text"])) and name in tasks:
                prs.setdefault(match.group(0), f"{at} {name}: {match.group(0)}")
        elif kind in ("close", "drop"):
            finished.append(
                f"{at} {name}: {'closed' if kind == 'close' else 'dropped'}"
            )
        elif kind == "action":
            actions.append(f"{at} {name}: {event['text']}")
    # A worker's question waits until the driver writes to that worker again.
    answered = {e["agent"]: e["ts"] for e in recent if e["event"] in ("tell", "wake")}
    questions = [
        (
            report["at"],
            f"{clock(report['at'])} {name} {report['kind']}: {report['text']}",
        )
        for name, task in tasks.items()
        if (report := task.get("report"))
        and report["kind"] in ("question", "blocked")
        and report["at"] >= since
        and answered.get(name, 0) < report["at"]
    ]
    try:
        ask = json.loads((state_dir() / "driver.json").read_text())
        questions.append((ask["at"], f"{clock(ask['at'])} driver: {ask['text']}"))
    except (OSError, ValueError, KeyError):
        pass
    lines = [
        f"Away {clock(since)} to {clock(time.time())}. Note: {away['note'] or 'none'}"
    ]
    for title, group in (
        ("PRs ready for review", list(prs.values())),
        ("Questions waiting on the user", [line for _, line in sorted(questions)]),
        ("What the driver did under the note", actions),
        ("Tasks finished or closed", finished),
    ):
        lines += ["", f"{title}:"] + ([f"  {line}" for line in group] or ["  none"])
    return lines


def cmd_log_action(args: argparse.Namespace) -> int:
    """Log something the driver did, for the return brief and the history."""
    text = " ".join(args.text).strip()
    with tasks_for_update():
        record("action", args.agent or "driver", text=text)
    print("Logged.")
    return 0


def read_events() -> list[dict[str, Any]]:
    try:
        lines = (state_dir() / "events.jsonl").read_text().splitlines()
    except FileNotFoundError:
        return []
    events: list[dict[str, Any]] = []
    for line in lines:
        try:
            events.append(json.loads(line))
        except ValueError:
            continue
    return events


def cmd_log(args: argparse.Namespace) -> int:
    """Print the event log, or one task's lines of it."""
    try:
        lines = (state_dir() / "events.jsonl").read_text().splitlines()
    except FileNotFoundError:
        lines = []
    for line in lines:
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if args.agent in (None, event.get("agent")):
            print(line)
    return 0
