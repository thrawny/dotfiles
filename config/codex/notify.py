#!/usr/bin/env python3

import subprocess
import sys

SOUND_FILE = "/System/Library/Sounds/Glass.aiff"
VOLUME = "1.5"  # 0.0 to 2.0


def main() -> int:
    # Accept and ignore the JSON payload if present
    try:
        subprocess.run(["afplay", "-v", VOLUME, SOUND_FILE], timeout=5)
    except Exception:
        # Keep hook non-fatal
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
