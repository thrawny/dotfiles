#!/usr/bin/env python3
"""
Claude Code Notification Hook
Shows visual notification and plays sound when Claude needs user input
Only notifies if Claude was working for longer than MIN_DURATION_SECONDS
"""

import json
import logging
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

LOG_FILE = Path.home() / ".claude" / "notification_debug.log"
MIN_DURATION_SECONDS = 120
DEBUG = False

logger = logging.getLogger(__name__)
if DEBUG:
    logging.basicConfig(
        filename=LOG_FILE,
        level=logging.DEBUG,
        format="%(asctime)s %(levelname)s %(message)s",
    )


def get_last_user_message_time(transcript_path: str) -> datetime | None:
    """Get timestamp of the last user message from transcript."""
    try:
        path = Path(transcript_path)
        if not path.exists():
            return None

        last_user_time = None
        for line in path.read_text().strip().splitlines():
            try:
                entry = json.loads(line)
                if entry.get("type") == "user" and entry.get("timestamp"):
                    ts = entry["timestamp"].replace("Z", "+00:00")
                    last_user_time = datetime.fromisoformat(ts)
            except (json.JSONDecodeError, ValueError):
                continue

        return last_user_time
    except Exception as e:
        logger.warning("Failed to parse transcript: %s", e)
        return None


def was_working_long_enough(transcript_path: str) -> bool:
    """Check if Claude was working for at least MIN_DURATION_SECONDS."""
    last_user_time = get_last_user_message_time(transcript_path)
    if not last_user_time:
        return False

    now = datetime.now(timezone.utc)
    duration = (now - last_user_time).total_seconds()
    logger.debug("Work duration: %.1f seconds", duration)
    return duration >= MIN_DURATION_SECONDS


def send_notification(message: str):
    try:
        subprocess.run(["notify", message], capture_output=True, timeout=5)
    except Exception as e:
        logger.exception("Failed to send notification: %s", e)


def main():
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError as e:
        logger.error("Error parsing input: %s", e)
        sys.exit(1)

    logger.debug("Notification payload: %s", json.dumps(input_data, indent=2))

    hook_event = input_data.get("hook_event_name", "")
    if hook_event == "Notification":
        transcript_path = input_data.get("transcript_path", "")
        if not was_working_long_enough(transcript_path):
            logger.debug("Skipping notification - task was too short")
            sys.exit(0)

        message = input_data.get("message", "Claude needs attention")
        send_notification(message)

    sys.exit(0)


if __name__ == "__main__":
    main()
