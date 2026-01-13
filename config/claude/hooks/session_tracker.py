#!/usr/bin/env python3
"""Track active Claude sessions with their niri and tmux window IDs."""
import json
import os
import subprocess
import sys
from pathlib import Path

SESSIONS_FILE = Path.home() / ".claude" / "active-sessions.json"


def get_niri_window_id():
    """Get focused window ID from niri."""
    try:
        result = subprocess.run(
            ["niri", "msg", "-j", "focused-window"],
            capture_output=True, text=True, timeout=2
        )
        if result.returncode == 0:
            data = json.loads(result.stdout)
            return str(data.get("id", ""))
    except (FileNotFoundError, subprocess.TimeoutExpired, json.JSONDecodeError):
        pass
    return None


def get_tmux_window_id():
    """Get current tmux window ID (e.g., @0, @1)."""
    if not os.environ.get("TMUX"):
        return None
    try:
        result = subprocess.run(
            ["tmux", "display-message", "-p", "#{window_id}"],
            capture_output=True, text=True, timeout=2
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass
    return None


def load_sessions():
    """Load existing sessions from file."""
    if SESSIONS_FILE.exists():
        try:
            return json.loads(SESSIONS_FILE.read_text())
        except json.JSONDecodeError:
            pass
    return {}


def save_sessions(sessions):
    """Save sessions to file."""
    SESSIONS_FILE.write_text(json.dumps(sessions, indent=2))


def main():
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(1)

    event = input_data.get("hook_event_name", "")
    sessions = load_sessions()

    if event == "SessionStart":
        niri_id = get_niri_window_id()
        tmux_id = get_tmux_window_id()
        # Use niri ID as primary key, fall back to tmux ID
        window_id = niri_id or tmux_id
        if window_id:
            sessions[window_id] = {
                "session_id": input_data.get("session_id"),
                "transcript_path": input_data.get("transcript_path"),
                "cwd": input_data.get("cwd"),
                "niri_window_id": niri_id,
                "tmux_window_id": tmux_id,
            }
            save_sessions(sessions)

    elif event == "SessionEnd":
        niri_id = get_niri_window_id()
        tmux_id = get_tmux_window_id()
        window_id = niri_id or tmux_id
        if window_id and window_id in sessions:
            del sessions[window_id]
            save_sessions(sessions)


if __name__ == "__main__":
    main()
