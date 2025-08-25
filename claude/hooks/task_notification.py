#!/usr/bin/env python3
"""
Claude Code Notification Hook
Plays a sound when Claude needs user input
"""

import json
import subprocess
import sys

# Configuration
SOUND_FILE = "/System/Library/Sounds/Glass.aiff"  # Change to your preference
VOLUME = 1.5  # Volume level (0.0 to 2.0)


def play_sound():
    """Play a sound using afplay"""
    try:
        subprocess.run(
            ["afplay", "-v", str(VOLUME), SOUND_FILE], capture_output=True, timeout=5
        )
    except Exception as e:
        print(f"Failed to play sound: {e}", file=sys.stderr)


def main():
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"Error parsing input: {e}", file=sys.stderr)
        sys.exit(1)

    hook_event = input_data.get("hook_event_name", "")

    if hook_event == "Notification":
        # Play sound for all notification events (idle, needs input, etc.)
        message = input_data.get("message", "")
        play_sound()
        print(f"✅ Notification - {message}")

    sys.exit(0)


if __name__ == "__main__":
    main()
