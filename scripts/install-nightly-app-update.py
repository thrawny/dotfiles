#!/usr/bin/env python3
"""Install only the updater's repo-native launch agent, without activating apps."""

import argparse
import datetime as dt
import fcntl
import json
import os
import plistlib
import subprocess
from pathlib import Path
from zoneinfo import ZoneInfo


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("plist", type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    state = Path.home() / ".local/state/nightly-app-update"
    state.mkdir(parents=True, exist_ok=True)
    state.chmod(0o700)
    with (state / "lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit(
                "Updater is running; installation deferred without interruption"
            ) from None
        latest = state / "latest.json"
        if latest.exists():
            receipt = json.loads(latest.read_text())
            if receipt.get("outcome") in {"maintaining", "uncertain", "pending-push"}:
                raise SystemExit(
                    "Reconcile the retained maintenance receipt before replacing the schedule"
                )
        else:
            now = dt.datetime.now(ZoneInfo("Europe/Stockholm"))
            night = now.date() if now.hour >= 2 else now.date() - dt.timedelta(days=1)
            latest.write_text(
                json.dumps({"outcome": "initialized", "night": night.isoformat()})
                + "\n"
            )
        with args.plist.open("rb") as stream:
            config = plistlib.load(stream)
        label = "org.nix-community.home.nightly-app-update"
        if config["Label"] != label or config["StartInterval"] != 60:
            raise SystemExit("Unexpected launch agent")
        domain = f"gui/{os.getuid()}"
        target = Path.home() / "Library/LaunchAgents" / f"{label}.plist"
        target.parent.mkdir(parents=True, exist_ok=True)
        # Only this scheduler is unloaded; no app/HM activation takes place.
        loaded = subprocess.run(
            ["/bin/launchctl", "print", f"{domain}/{label}"], capture_output=True
        )
        if loaded.returncode == 0:
            subprocess.run(
                ["/bin/launchctl", "bootout", f"{domain}/{label}"], check=True
            )
        temporary = target.with_suffix(".new")
        with temporary.open("wb") as stream:
            plistlib.dump(config, stream)
        temporary.replace(target)
        subprocess.run(["/bin/launchctl", "bootstrap", domain, str(target)], check=True)
        subprocess.run(["/bin/launchctl", "print", f"{domain}/{label}"], check=True)
        print("Installed; initial run is suppressed until the next Stockholm night.")


if __name__ == "__main__":
    main()
