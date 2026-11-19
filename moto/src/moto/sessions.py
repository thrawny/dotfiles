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
    QUEUED_BY_CLAUDE,
    RETIRED_SETTINGS,
    SETTINGS,
    USER_PROMPT_TAIL,
    MotoError,
    timestamp,
)


def user_prompts(lines: list[str], task: dict[str, Any]) -> list[tuple[float, str]]:
    """When and what the user typed into the worker's pane, in file order.

    A prompt typed while the worker is mid-turn is queued, and Claude records
    it as a queue-operation enqueue instead of a prompt. A popAll pulls the
    queued messages back into the input box, so each one it names is
    withdrawn unless the user sends it again. Prompts from the driver, from
    the worker that started this one, the reports of the workers it started
    and Claude's own task notifications carry a sender's tag or a known
    shape and are not the user's.
    """
    tags = (DRIVER_TAG, HC_NOTE) + (
        (f"[{task['parent']}]",) if task.get("parent") else ()
    )
    found: list[tuple[float, str]] = []
    queued: list[tuple[float, str]] = []
    for line in lines:
        if '"typed"' not in line and '"queue-operation"' not in line:
            continue
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        at = timestamp(entry.get("timestamp"))
        if at is None:
            continue
        if entry.get("type") == "queue-operation":
            content = entry.get("content")
            if not isinstance(content, str):
                continue
            text = PASTED.sub("", content, count=1)
            if entry.get("operation") == "enqueue":
                queued.append((at, text))
            elif entry.get("operation") == "popAll":
                for index in range(len(queued) - 1, -1, -1):
                    if queued[index][1] == text:
                        del queued[index]
                        break
            continue
        if entry.get("promptSource") != "typed" or entry.get("isSidechain"):
            continue
        found.append((at, typed_text(entry)))
    # A dequeue or a remove only says Claude took the message in, so the
    # message stays. Only a popAll takes it out of `queued`.
    found += queued
    found.sort(key=lambda item: item[0])
    return [
        (at, text)
        for at, text in found
        if not text.startswith(tags + QUEUED_BY_CLAUDE) and not CHILD_REPORT.match(text)
    ]


def user_turns(
    task: dict[str, Any], agent: dict[str, Any] | None, since: float
) -> list[float]:
    """When the user typed each prompt into the worker's pane after since,
    queued ones included."""
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
    return [at for at, _ in user_prompts(lines, task) if at > since]


def user_prompt_at(task: dict[str, Any], agent: dict[str, Any] | None) -> float | None:
    """When the user last typed a prompt into the worker's pane, or None when the
    transcript has none. A message queued mid-turn counts from when it was queued.

    Raises MotoError or OSError when there is no transcript to read. moto's own
    slash commands have a known name and are not the user's. Only the end of a
    long transcript is read.
    """
    path = transcript(task, agent)
    if path is None:
        raise MotoError("no transcript")
    with path.open("rb") as handle:
        handle.seek(max(0, path.stat().st_size - USER_PROMPT_TAIL))
        lines = handle.read().decode(errors="replace").splitlines()
    times = [
        at
        for at, text in user_prompts(lines, task)
        if not text.startswith(MOTO_COMMANDS)
    ]
    return max(times, default=None)


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


def settings_file() -> dict[str, Any]:
    """MOTO_HOME/settings.toml as a table, empty when the file is missing."""
    path = MOTO_HOME / "settings.toml"
    try:
        return tomllib.loads(path.read_text())
    except FileNotFoundError:
        return {}
    except (OSError, tomllib.TOMLDecodeError) as error:
        raise MotoError(f"{path} cannot be read: {error}") from error


def settings() -> dict[str, int]:
    """SETTINGS, with what MOTO_HOME/settings.toml sets in their place."""
    path = MOTO_HOME / "settings.toml"
    found = {
        k: v
        for k, v in settings_file().items()
        if k not in RETIRED_SETTINGS and k != "doc_limits"
    }
    if unknown := sorted(set(found) - set(SETTINGS)):
        raise MotoError(
            f"{path} has unknown settings: {', '.join(unknown)}."
            + f" Known: {', '.join(SETTINGS)}"
        )
    for key, value in found.items():
        if type(value) is not int or value <= 0:
            raise MotoError(f"{path}: {key} must be a positive whole number")
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
