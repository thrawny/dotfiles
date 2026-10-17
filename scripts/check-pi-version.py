#!/usr/bin/env python3
"""Check that Pi's runtime, declared SDK pins, and installed SDKs agree."""

import json
import subprocess
import sys
from pathlib import Path

PI_PACKAGES = (
    "@earendil-works/pi-ai",
    "@earendil-works/pi-coding-agent",
    "@earendil-works/pi-tui",
)


def main() -> int:
    try:
        runtime = subprocess.run(
            ["pi", "--version"], check=True, capture_output=True, text=True, timeout=10
        ).stdout.strip()
    except (OSError, subprocess.SubprocessError) as error:
        print(f"Cannot determine installed Pi version: {error}", file=sys.stderr)
        return 1

    directory = Path(__file__).resolve().parents[1] / "config" / "pi"
    manifest = json.loads((directory / "package.json").read_text())
    declared = manifest.get("dependencies", {}) | manifest.get("devDependencies", {})
    errors: list[str] = []
    for package in PI_PACKAGES:
        if declared.get(package) != runtime:
            errors.append(
                f"{package}: declared {declared.get(package)!r}, runtime {runtime}"
            )
        try:
            installed = json.loads(
                (directory / "node_modules" / package / "package.json").read_text()
            ).get("version")
        except FileNotFoundError:
            installed = "missing"
        if installed != runtime:
            errors.append(f"{package}: installed {installed}, runtime {runtime}")
    if errors:
        print("Pi version mismatch:\n  " + "\n  ".join(errors), file=sys.stderr)
        print(
            "Align config/pi/package.json, then run: just pi-update-deps "
            + " ".join(PI_PACKAGES),
            file=sys.stderr,
        )
        return 1
    print(f"Pi runtime and SDK dependencies match: {runtime}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
