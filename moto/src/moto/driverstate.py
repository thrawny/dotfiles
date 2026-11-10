from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any

from moto.common import DRIVER_ROLE, JOB_TAG, MOTO_HOME, WORKER_ENV, state_dir
from moto.jobstate import job_event, jobs_for_update, read_jobs


def driver_path() -> Path:
    return state_dir() / "driver.json"


def read_driver() -> dict[str, Any]:
    """Where the driver is, and its open question if it has one."""
    try:
        return json.loads(driver_path().read_text())
    except (OSError, ValueError):
        return {}


def write_driver(**fields: Any) -> None:
    """Merge into the driver record, keeping the fields already there.

    The pane and session outlive a question, so moto ask --clear drops the
    question's own fields rather than the file.
    """
    state_dir().mkdir(parents=True, exist_ok=True)
    driver_path().write_text(json.dumps(read_driver() | fields) + "\n")


def driver_session(cwd: Any) -> bool:
    """Whether this Claude session is the driver.

    A session with a role is the driver only in the driver role. One without
    a role is the driver when it started in MOTO_HOME itself.
    """
    if role := os.environ.get("MOTO_ROLE"):
        return role == DRIVER_ROLE
    if os.environ.get(WORKER_ENV):
        return False
    try:
        return Path(str(cwd or "")).resolve() == MOTO_HOME.resolve()
    except OSError:
        return False


def wake_driver(name: str, text: str, label: str = JOB_TAG) -> str:
    """Leave the driver a note, which the moto-watch mod's next pass hands over.

    One note per job: a newer run replaces an unread one, because a review
    queue's value is the current list and two stale lists are worse than one
    fresh one. The replaced note stays in the event log.
    """
    replaced = False
    with jobs_for_update() as jobs:
        state = jobs.setdefault(name, {})
        replaced = bool(state.get("note"))
        state["note"] = {"text": f"{label} {text}", "at": time.time()}
    if replaced:
        job_event("note-replaced", name)
    return "left a note for the driver"


def pending_notes() -> list[tuple[str, dict[str, Any]]]:
    return [
        (name, state["note"])
        for name, state in sorted(read_jobs().items())
        if state.get("note")
    ]


def take_notes() -> str | None:
    """Every pending note, removed as it is handed over, or None if there are none.

    Removing on delivery is what keeps a note from reaching the driver twice.
    """
    notes = pending_notes()
    if not notes:
        return None
    with jobs_for_update() as jobs:
        for name, _ in notes:
            jobs.get(name, {}).pop("note", None)
            # A moto when check keeps no state here beyond its notes.
            if name in jobs and not jobs[name]:
                del jobs[name]
    for name, _ in notes:
        job_event("note-read", name)
    return "\n\n".join(note["text"] for _, note in notes)
