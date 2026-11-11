#!/usr/bin/env python3
"""Make the live Claude settings equal this host's filtered example.

Home Manager wraps this with the host's paths and flags; activation and
`just check` both run that wrapper, so the filter lives only here.
"""

from __future__ import annotations

import argparse
import difflib
import json
import os
import sys
import tempfile
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

STORE_STATUS_LINE = "python3 ~/.claude/status_line.py"
DIFF_LINES = 40
BACKUPS_KEPT = 30


def strip_agent_switch(settings: dict[str, Any]) -> dict[str, Any]:
    """Drop agent-switch hook commands and any matcher or event left empty."""
    hooks = settings.get("hooks")
    if not isinstance(hooks, dict):
        return settings
    kept_events: dict[str, Any] = {}
    for event, entries in hooks.items():
        kept_entries = []
        for entry in entries:
            commands = [
                hook
                for hook in entry.get("hooks", [])
                if "agent-switch" not in (hook.get("command") or "")
            ]
            if commands:
                kept_entries.append({**entry, "hooks": commands})
        if kept_entries:
            kept_events[event] = kept_entries
    return {**settings, "hooks": kept_events}


def filtered(
    example: dict[str, Any], agent_switch: bool, store: bool
) -> dict[str, Any]:
    settings = example if agent_switch else strip_agent_switch(example)
    if store:
        # Store-backed hosts have no repo checkout for plugins or the status line.
        settings = {k: v for k, v in settings.items() if k != "enabledPlugins"}
        settings["statusLine"] = {
            **settings.get("statusLine", {}),
            "command": STORE_STATUS_LINE,
        }
    return settings


def render(settings: Any, sort_keys: bool = False) -> str:
    return (
        json.dumps(settings, indent=2, ensure_ascii=False, sort_keys=sort_keys) + "\n"
    )


def read_live(target: Path) -> tuple[bytes | None, Any]:
    """Return the live bytes and their parsed value; unparseable files give None."""
    try:
        raw = target.read_bytes()
    except FileNotFoundError:
        return None, None
    try:
        return raw, json.loads(raw.decode())
    except (UnicodeDecodeError, json.JSONDecodeError):
        return raw, None


def diff_summary(old_text: str, new: Any) -> list[str]:
    try:
        old = render(json.loads(old_text), sort_keys=True)
    except json.JSONDecodeError:
        old = old_text
    lines = list(
        difflib.unified_diff(
            old.splitlines(),
            render(new, sort_keys=True).splitlines(),
            "live",
            "example",
            n=1,
            lineterm="",
        )
    )
    if len(lines) > DIFF_LINES:
        lines = [*lines[:DIFF_LINES], f"... {len(lines) - DIFF_LINES} more diff lines"]
    return lines


def backup(raw: bytes, backup_dir: Path) -> Path:
    backup_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(UTC).strftime("%Y%m%dT%H%M%S%fZ")
    path = backup_dir / f"settings.json.{stamp}"
    path.write_bytes(raw)
    for old in sorted(backup_dir.glob("settings.json.*"))[:-BACKUPS_KEPT]:
        old.unlink()
    return path


def write_atomic(target: Path, text: str) -> None:
    # Replacing the path also replaces a stale symlink with a regular file.
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(dir=target.parent, prefix=".settings.json.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.chmod(temp, 0o644)
        os.replace(temp, target)
    except BaseException:
        Path(temp).unlink(missing_ok=True)
        raise


def sync(
    example: Path,
    target: Path,
    backup_dir: Path,
    agent_switch: bool,
    store: bool,
    dry_run: bool = False,
) -> str:
    """Sync target to the filtered example and return what happened."""
    wanted = filtered(
        json.loads(example.read_text(encoding="utf-8")), agent_switch, store
    )
    raw, live = read_live(target)
    present = raw is not None and raw.strip() != b""
    if present and live == wanted:
        return "in sync"
    if not present:
        state = "missing"
        lines: list[str] = []
    else:
        state = "drifted" if live is not None else "invalid JSON"
        lines = diff_summary(raw.decode(errors="replace"), wanted)
    if dry_run:
        return "\n".join([f"{state}; would update {target}", *lines])
    saved = backup(raw, backup_dir) if raw is not None and present else None
    write_atomic(target, render(wanted))
    report = [f"{state}; updated {target}"]
    if saved:
        report.append(f"backup: {saved}")
    return "\n".join([*report, *lines])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--example", type=Path, required=True)
    parser.add_argument("--target", type=Path, required=True)
    parser.add_argument("--backup-dir", type=Path, required=True)
    parser.add_argument(
        "--agent-switch", action="store_true", help="keep agent-switch hooks"
    )
    parser.add_argument(
        "--store", action="store_true", help="apply the store-backed variant"
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        result = sync(
            args.example,
            args.target,
            args.backup_dir,
            args.agent_switch,
            args.store,
            args.dry_run,
        )
    except (OSError, json.JSONDecodeError) as error:
        print(f"claude-settings-sync: {error}", file=sys.stderr)
        return 1
    print(f"claude-settings-sync: {result}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
