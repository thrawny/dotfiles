#!/usr/bin/env python3
"""Install on-demand helpers and retire only the legacy unattended updater."""

import argparse
import fcntl
import hashlib
import os
import subprocess
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    args = parser.parse_args()
    if not (args.package / "bin/nightly-app-update").is_file():
        raise SystemExit("Missing on-demand maintenance command")
    os.umask(0o077)
    state = Path.home() / ".local/state/nightly-app-update"
    state.mkdir(parents=True, exist_ok=True)
    state.chmod(0o700)
    with (state / "lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit("Updater is running; retirement deferred") from None
        # Keep this fence permanently; no old runner may resume unattended work.
        (state / "paused").touch(mode=0o600)
        label = "org.nix-community.home.nightly-app-update"
        domain = f"gui/{os.getuid()}"
        service = f"{domain}/{label}"
        target = Path.home() / "Library/LaunchAgents" / f"{label}.plist"
        if target.exists():
            data = target.read_bytes()
            archive = state / "retired-launchd"
            archive.mkdir(mode=0o700, exist_ok=True)
            (archive / f"{hashlib.sha256(data).hexdigest()}.plist").write_bytes(data)
        # Disable before bootout so login/activation cannot revive the old label.
        subprocess.run(["/bin/launchctl", "disable", service], check=True)
        loaded = subprocess.run(
            ["/bin/launchctl", "print", service], capture_output=True
        )
        if loaded.returncode == 0:
            subprocess.run(["/bin/launchctl", "bootout", service], check=True)
        probe = subprocess.run(
            ["/bin/launchctl", "print", service], capture_output=True
        )
        if probe.returncode == 0:
            raise SystemExit("Legacy updater is still loaded")
        # Keep all original receipts, backups and GC roots. Only its launch file
        # is retired; the on-demand command has its own durable runtime root.
        target.unlink(missing_ok=True)
        subprocess.run(
            [
                "nix-store",
                "--add-root",
                str(state / "executor"),
                "--indirect",
                "--realise",
                str(args.package.resolve()),
            ],
            check=True,
        )
        print("On-demand helpers installed; legacy updater disabled and unloaded.")


if __name__ == "__main__":
    main()
