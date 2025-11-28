#!/usr/bin/env python3
"""
Claude Code Notification Hook
Shows visual notification and plays sound when Claude needs user input
"""

import json
import logging
import subprocess
import sys
from pathlib import Path

LOG_FILE = Path.home() / ".claude" / "notification_debug.log"
MIN_TRANSCRIPT_LINES = 5
DEBUG = False

logger = logging.getLogger(__name__)
if DEBUG:
    logging.basicConfig(
        filename=LOG_FILE,
        level=logging.DEBUG,
        format="%(asctime)s %(levelname)s %(message)s",
    )


def has_meaningful_transcript(transcript_path: str) -> bool:
    """Check if transcript has enough content to warrant notification."""
    try:
        path = Path(transcript_path)
        if not path.exists():
            return False
        lines = path.read_text().strip().splitlines()
        return len(lines) >= MIN_TRANSCRIPT_LINES
    except Exception as e:
        logger.warning("Failed to read transcript: %s", e)
        return False


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
        if not has_meaningful_transcript(transcript_path):
            logger.debug("Skipping notification - transcript too short")
            sys.exit(0)

        message = input_data.get("message", "Claude needs attention")
        send_notification(message)

    sys.exit(0)


if __name__ == "__main__":
    main()
