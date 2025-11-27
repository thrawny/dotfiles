#!/usr/bin/env python3
"""
Claude Code Notification Hook
Shows visual notification and plays sound when Claude needs user input
"""

import json
import subprocess
import sys


def send_notification(message: str):
    """Send notification using the notify command"""
    try:
        subprocess.run(["notify", message], capture_output=True, timeout=5)
    except Exception as e:
        print(f"Failed to send notification: {e}", file=sys.stderr)


def main():
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        print(f"Error parsing input: {e}", file=sys.stderr)
        sys.exit(1)

    hook_event = input_data.get("hook_event_name", "")

    if hook_event == "Notification":
        message = input_data.get("message", "Claude needs attention")
        send_notification(message)
        print(f"✅ Notification - {message}")

    sys.exit(0)


if __name__ == "__main__":
    main()
