#!/usr/bin/env python3
"""Track active Claude sessions with their niri window IDs."""
import json
import subprocess
import sys
from pathlib import Path

SESSIONS_FILE = Path.home() / ".claude" / "active-sessions.json"


def get_focused_window_id():
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
        window_id = get_focused_window_id()
        if window_id:
            sessions[window_id] = {
                "session_id": input_data.get("session_id"),
                "transcript_path": input_data.get("transcript_path"),
                "cwd": input_data.get("cwd"),
            }
            save_sessions(sessions)

    elif event == "SessionEnd":
        window_id = get_focused_window_id()
        if window_id and window_id in sessions:
            del sessions[window_id]
            save_sessions(sessions)


if __name__ == "__main__":
    main()
