from __future__ import annotations

import json
import re
import tomllib
from pathlib import Path
from typing import Any

from moto.common import (
    CHILD_REPORT,
    CLAUDE_HOME,
    CONTEXT_USAGE,
    DRIVER_TAG,
    HC_NOTE,
    MOTO_COMMANDS,
    MOTO_HOME,
    PASTED,
    SETTINGS,
    USER_PROMPT_TAIL,
    MotoError,
    timestamp,
)


def user_turns(
    task: dict[str, Any], agent: dict[str, Any] | None, since: float
) -> list[float]:
    """When the user typed each prompt into the worker's pane after since.

    Prompts from the driver, from the worker that started this one, and the
    reports of the workers this one started carry their sender's tag and do
    not count.
    """
    snooze = task.get("snoozed")
    try:
        if snooze:
            cwd = snooze.get("cwd") or task["cwd"]
            path = session_path(cwd, snooze["session"])
        else:
            path = transcript(task, agent)
        lines = path.read_text(errors="replace").splitlines() if path else []
    except (MotoError, OSError):
        return []
    tags = (DRIVER_TAG, HC_NOTE) + (
        (f"[{task['parent']}]",) if task.get("parent") else ()
    )
    times: list[float] = []
    for line in lines:
        if '"typed"' not in line:
            continue
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if entry.get("promptSource") != "typed" or entry.get("isSidechain"):
            continue
        at = timestamp(entry.get("timestamp"))
        text = typed_text(entry)
        if (
            at is not None
            and at > since
            and not text.startswith(tags)
            and not CHILD_REPORT.match(text)
        ):
            times.append(at)
    return times


def user_prompt(task: dict[str, Any], agent: dict[str, Any] | None) -> str | None:
    """The uuid of the latest prompt the user typed into the worker's pane, or
    None when the transcript has none.

    Raises MotoError or OSError when there is no transcript to read. Prompts
    from the driver, from the worker's parent and the reports of its children
    carry a tag, and moto's own slash commands have a known name; none of them
    is the user's. Only the end of a long transcript is read.
    """
    path = transcript(task, agent)
    if path is None:
        raise MotoError("no transcript")
    with path.open("rb") as handle:
        handle.seek(max(0, path.stat().st_size - USER_PROMPT_TAIL))
        lines = handle.read().decode(errors="replace").splitlines()
    tags = (DRIVER_TAG, HC_NOTE) + (
        (f"[{task['parent']}]",) if task.get("parent") else ()
    )
    for line in reversed(lines):
        if '"typed"' not in line:
            continue
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if entry.get("promptSource") != "typed" or entry.get("isSidechain"):
            continue
        text = typed_text(entry)
        if (
            entry.get("uuid")
            and not text.startswith(tags + MOTO_COMMANDS)
            and not CHILD_REPORT.match(text)
        ):
            return str(entry["uuid"])
    return None


def context_tokens(task: dict[str, Any], agent: dict[str, Any] | None) -> int | None:
    """How many tokens the worker's context holds, from its transcript.

    Each reply records the context Claude sent for it. A compaction after the
    last reply leaves little of it, so the size then counts as 0. None means no
    transcript, or no reply in it yet.
    """
    try:
        path = transcript(task, agent)
        lines = path.read_text(errors="replace").splitlines() if path else []
    except (MotoError, OSError):
        return None
    for line in reversed(lines):
        if '"compact_boundary"' not in line and '"usage"' not in line:
            continue
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if entry.get("isSidechain"):
            continue
        if entry.get("subtype") == "compact_boundary":
            return 0
        message: dict[str, Any] = entry.get("message") or {}
        if entry.get("type") == "assistant" and (usage := message.get("usage")):
            return sum(int(usage.get(key) or 0) for key in CONTEXT_USAGE)
    return None


def settings() -> dict[str, int]:
    """SETTINGS, with what MOTO_HOME/settings.toml sets in their place."""
    path = MOTO_HOME / "settings.toml"
    try:
        found = tomllib.loads(path.read_text())
    except FileNotFoundError:
        return dict(SETTINGS)
    except (OSError, tomllib.TOMLDecodeError) as error:
        raise MotoError(f"{path} cannot be read: {error}") from error
    if unknown := sorted(set(found) - set(SETTINGS)):
        raise MotoError(
            f"{path} has unknown settings: {', '.join(unknown)}."
            + f" Known: {', '.join(SETTINGS)}"
        )
    for key, value in found.items():
        if type(value) is not int or value <= 0:
            raise MotoError(f"{path}: {key} must be a positive number of tokens")
    return SETTINGS | found


def last_turn(
    task: dict[str, Any], agent: dict[str, Any] | None
) -> tuple[str | None, str | None]:
    """The uuid of the worker's last reply and its last typed prompt, from its transcript.

    Claude marks a prompt typed into the pane, by a person or by herdr agent
    prompt, apart from the ones it makes itself, such as a background task's
    notification. A pasted prompt comes wrapped in a pasted_content tag.
    """
    try:
        path = transcript(task, agent)
        lines = path.read_text(errors="replace").splitlines() if path else []
    except (MotoError, OSError):
        return None, None
    turn = prompt = None
    for line in reversed(lines):
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if entry.get("isSidechain"):
            continue
        if turn is None and entry.get("type") == "assistant":
            turn = entry.get("uuid")
        elif prompt is None and entry.get("promptSource") == "typed":
            prompt = typed_text(entry)
        if turn is not None and prompt is not None:
            break
    return turn, prompt


def typed_text(entry: dict[str, Any]) -> str:
    """A typed prompt's text, unwrapped from a pasted_content tag."""
    message: dict[str, Any] = entry.get("message") or {}
    content: str | list[dict[str, Any]] = message.get("content") or ""
    if isinstance(content, list):
        content = "".join(str(b.get("text") or "") for b in content)
    return PASTED.sub("", content, count=1)


def session_dir(cwd: str) -> Path:
    """Where Claude keeps the sessions that ran in this folder."""
    return CLAUDE_HOME / "projects" / re.sub(r"[^A-Za-z0-9]", "-", cwd)


def session_path(cwd: str, session: str) -> Path | None:
    """The session's transcript, in cwd's folder or any other.

    Claude files a session under the folder it started in, which can be
    another checkout than the task's, such as a worktree the worker opened.
    """
    path = session_dir(cwd) / f"{session}.jsonl"
    if path.is_file():
        return path
    found = sorted((CLAUDE_HOME / "projects").glob(f"*/{session}.jsonl"))
    return found[0] if found else None


def session_cwd(path: Path) -> str | None:
    """The folder the session ran in, from which claude --resume must start.

    Each entry records the shell's folder, which a cd moves, so the one that
    maps to the transcript's own folder is where Claude started.
    """
    with path.open(errors="replace") as lines:
        for line in lines:
            if '"cwd"' not in line:
                continue
            try:
                cwd = json.loads(line).get("cwd")
            except ValueError:
                continue
            if isinstance(cwd, str) and session_dir(cwd) == path.parent:
                return cwd
    return None


def last_title(session: Path) -> str | None:
    title = None
    with session.open(errors="replace") as lines:
        for line in lines:
            if '"customTitle"' not in line:
                continue
            try:
                title = json.loads(line).get("customTitle") or title
            except ValueError:
                pass
    return title


def newest_session(cwd: str, title: str) -> Path | None:
    """The transcript of the newest Claude session in this folder named title."""
    sessions = sorted(
        session_dir(cwd).glob("*.jsonl"), key=lambda s: s.stat().st_mtime, reverse=True
    )
    return next((s for s in sessions if last_title(s) == title), None)


def transcript(task: dict[str, Any], agent: dict[str, Any] | None) -> Path | None:
    """The worker's transcript: its recorded session's, else the newest one named
    after it. A fork of the worker copies the name, so the session id comes first."""
    session = task.get("session")
    if session and (path := session_path(task["cwd"], session)):
        return path
    return newest_session(task["cwd"], task_title(task, agent))


def find_session(cwd: str, title: str) -> str:
    """The id of the newest Claude session in this folder that is named title."""
    directory = session_dir(cwd)
    if not directory.is_dir():
        raise MotoError(f"No Claude sessions recorded for {cwd} in {directory}")
    if session := newest_session(cwd, title):
        return session.stem
    raise MotoError(f"No Claude session in {directory} is named {title!r}")


def task_title(task: dict[str, Any], agent: dict[str, Any] | None) -> str:
    """The worker's Claude session name, which spawn records and Claude shows as the pane title."""
    if title := task.get("title"):
        return title
    if agent and (title := agent.get("terminal_title_stripped")):
        return title
    raise MotoError(
        f"{task['agent']} has no recorded title and no live pane to read one from"
    )
