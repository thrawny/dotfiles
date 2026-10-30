#!/usr/bin/env python3
"""Gate nightly fleet app maintenance and prepare isolated Nix candidates."""

import argparse
import datetime as dt
import fcntl
import json
import os
import re
import shutil
import signal
import sqlite3
import subprocess
import tempfile
import time
import urllib.request
from pathlib import Path
from zoneinfo import ZoneInfo

ZONE = ZoneInfo("Europe/Stockholm")
INPUTS = ("nix-openclaw", "thrawny-pkgs")
ATTRS = {
    "m1-t3": "homeConfigurations.thrawnym1.config.dotfiles.t3code.package",
    "m1-openclaw": "homeConfigurations.thrawnym1.config.dotfiles.openclawNode.package",
    "obelisk-t3": "nixosConfigurations.obelisk.config.system.build.t3code-runtime",
    "obelisk-openclaw": "nixosConfigurations.obelisk.config.system.build.openclaw-runtime",
}
TERMINAL_RUN_STATES = {"completed", "failed", "cancelled", "interrupted", "rolled_back"}


def activity_reason(runs, sessions):
    """Unknown status is busy: new server states must never bypass the idle gate."""
    if any(value not in TERMINAL_RUN_STATES for value in runs):
        return "active-or-unknown-t3-run"
    if any(value not in {"closed", "stopped", "disconnected"} for value in sessions):
        return "attached-or-unknown-provider-session"
    return None


def local_activity(database):
    # Open the real server database read-only; never create a missing database.
    with sqlite3.connect(
        f"{database.resolve().as_uri()}?mode=ro", uri=True
    ) as connection:
        runs = [
            row[0]
            for row in connection.execute(
                "SELECT status FROM orchestration_v2_projection_runs"
            )
        ]
        sessions = [
            row[0]
            for row in connection.execute(
                "SELECT status FROM orchestration_v2_projection_provider_sessions"
            )
        ]
    return activity_reason(runs, sessions)


def attempt_reason(previous, now):
    if previous.get("outcome") in {
        "activating",
        "migrating",
        "pushing",
        "maintaining",
        "uncertain",
        "pending-push",
    }:
        return "uncertain-mutation-requires-reconciliation"
    if not due_day(now, previous.get("night")):
        return "already-attempted-this-night"
    return None


def due_day(now, previous):
    """One attempt per Stockholm night, including a missed run after wake."""
    local = now.astimezone(ZONE)
    day = local.date() if local.hour >= 2 else local.date() - dt.timedelta(days=1)
    return day.isoformat() if previous != day.isoformat() else None


def version_key(value):
    match = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)(?:-nightly\.(\d{8})\.(\d+))?", value)
    if not match:
        raise ValueError("Unknown package version; refusing an update")
    return tuple(int(part or 0) for part in match.groups())


def changed_versions(before, after):
    if before.keys() != ATTRS.keys() or after.keys() != ATTRS.keys():
        raise ValueError("Incomplete fleet version inventory")
    changed = []
    for target in ATTRS:
        old, new = version_key(before[target]), version_key(after[target])
        if new < old:
            raise ValueError(f"Refusing downgrade for {target}")
        if new > old:
            changed.append(target)
    for app in ("t3", "openclaw"):
        if after[f"m1-{app}"] != after[f"obelisk-{app}"]:
            raise ValueError(f"Cross-host {app} version mismatch")
    return changed


def changed_apps(targets):
    return {target.split("-", 1)[1] for target in targets}


def validate_release(version, release, nightly):
    version_key(version)
    if release.get("tag_name") != f"v{version}" or release.get("draft") is not False:
        raise ValueError("Package version does not match a published upstream release")
    if release.get("prerelease") is not nightly:
        raise ValueError("Unexpected upstream release channel")
    if nightly != ("-nightly." in version):
        raise ValueError("Package version is on the wrong release channel")
    if not release.get("published_at"):
        raise ValueError("Upstream release has not been published")


def official_release(app, version):
    repository = {"t3": "pingdotgg/t3code", "openclaw": "openclaw/openclaw"}[app]
    url = f"https://api.github.com/repos/{repository}/releases/tags/v{version}"
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "User-Agent": "dotfiles-nightly-app-update",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        release = json.load(response)
    validate_release(version, release, nightly=app == "t3")
    return {key: release[key] for key in ("tag_name", "published_at", "html_url")}


def validate_input_scope(before, after):
    old_inputs = before["nodes"][before["root"]]["inputs"]
    new_inputs = after["nodes"][after["root"]]["inputs"]
    if old_inputs.keys() != new_inputs.keys():
        raise ValueError("Unexpected flake input additions or removals")
    for name in old_inputs.keys() - set(INPUTS):
        old_node, new_node = old_inputs[name], new_inputs[name]
        if not isinstance(old_node, str) or not isinstance(new_node, str):
            raise ValueError("Unsupported root input reference")
        if before["nodes"][old_node].get("locked") != after["nodes"][new_node].get(
            "locked"
        ):
            raise ValueError(f"Unrelated root input changed: {name}")


def run(args, cwd, timeout=900):
    return subprocess.run(
        args, cwd=cwd, check=True, text=True, capture_output=True, timeout=timeout
    ).stdout.strip()


def write_json(destination, value):
    temporary = destination.with_suffix(".tmp")
    with temporary.open("w") as stream:
        json.dump(value, stream, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(destination)


def record_preparation(directory, value):
    """Keep preparation separate from rollout receipts and uncertain mutations."""
    record = {"recorded_at": dt.datetime.now(dt.UTC).isoformat(), **value}
    write_json(directory / "preparation.json", record)
    with (directory / "preparation.jsonl").open("a") as stream:
        stream.write(json.dumps(record) + "\n")
        stream.flush()
        os.fsync(stream.fileno())


def prepare_recorded(checkout, destination, state_directory):
    record_preparation(state_directory, {"outcome": "preparing"})
    try:
        result = prepare(checkout, destination)
    except Exception as error:
        # Never persist captured tool output: it can contain operational secrets.
        record_preparation(
            state_directory, {"outcome": "failed", "error": type(error).__name__}
        )
        return False
    record_preparation(state_directory, result)
    return True


def persist(directory, value):
    value = {"recorded_at": dt.datetime.now(dt.UTC).isoformat(), **value}
    write_json(directory / "latest.json", value)
    with (directory / "events.jsonl").open("a") as stream:
        stream.write(json.dumps(value) + "\n")
        stream.flush()
        os.fsync(stream.fileno())


def remote_activity():
    code = (
        "import sqlite3,json; "
        "c=sqlite3.connect('file:/srv/t3code/.t3code/userdata/statev2.sqlite?mode=ro',uri=True); "
        "print(json.dumps([[r[0] for r in c.execute('SELECT status FROM '+t)] for t in "
        "['orchestration_v2_projection_runs','orchestration_v2_projection_provider_sessions']]))"
    )
    import shlex

    result = run(
        [
            "ssh",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=10",
            "root@obelisk",
            "python3 -c " + shlex.quote(code),
        ],
        Path.home(),
        timeout=30,
    )
    runs, sessions = json.loads(result)
    return activity_reason(runs, sessions)


def idle_reason():
    reason = local_activity(Path.home() / ".t3/userdata/statev2.sqlite")
    return reason or remote_activity()


def launch_maintenance(candidate, directory, task_file, manifest):
    """A separate launchd-owned agent survives T3's scoped service restart."""
    result_file = directory / "agent-result.json"
    schema = {
        "type": "object",
        "additionalProperties": False,
        "properties": {
            "outcome": {"type": "string", "enum": ["updated", "deferred", "failed"]},
            "reason": {"type": "string"},
            "mutated": {"type": "boolean"},
            "evidence": {"type": "array", "items": {"type": "string"}},
        },
        "required": ["outcome", "reason", "mutated", "evidence"],
    }
    schema_file = directory / "result-schema.json"
    write_json(schema_file, schema)
    prompt = (
        task_file.read_text()
        + "\n\nExact validated candidate and private evidence directory:\n"
        + json.dumps(
            {"candidate": manifest, "evidence_directory": str(directory)}, indent=2
        )
    )
    with (directory / "agent.log").open("w") as log:
        process = subprocess.Popen(
            [
                "codex",
                "exec",
                "--ephemeral",
                "--dangerously-bypass-approvals-and-sandbox",
                "--output-schema",
                str(schema_file),
                "--output-last-message",
                str(result_file),
                "--cd",
                str(candidate),
                "-",
            ],
            stdin=subprocess.PIPE,
            stdout=log,
            stderr=log,
            text=True,
            start_new_session=True,
        )
        assert process.stdin is not None
        process.stdin.write(prompt)
        process.stdin.close()
        deadline = time.monotonic() + 5400
        while process.poll() is None:
            if time.monotonic() >= deadline or log.tell() > 32 * 1024 * 1024:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                raise RuntimeError(
                    "Maintenance deadline exceeded; reconcile before replay"
                )
            time.sleep(2)
        if process.returncode != 0:
            raise RuntimeError("Maintenance agent failed; reconcile before replay")
    result = json.loads(result_file.read_text())
    if result["outcome"] not in {"updated", "deferred", "failed"}:
        raise ValueError("Unknown maintenance result")
    return result


def verify_commands(manifest):
    for target, package in manifest["builds"].items():
        if target.startswith("obelisk"):
            service = "t3code" if target.endswith("t3") else "openclaw"
            # Package paths were validated before reaching this command.
            command = f'pid=$(systemctl show {service} -p MainPID --value); test "$pid" -gt 0 && tr "\\0" " " < /proc/$pid/cmdline'
            command_line = run(
                ["ssh", "-o", "BatchMode=yes", "root@obelisk", command],
                Path.home(),
                timeout=30,
            )
        else:
            agent = "t3code" if target.endswith("t3") else "openclaw-node"
            description = run(
                [
                    "/bin/launchctl",
                    "print",
                    f"gui/{os.getuid()}/org.nix-community.home.{agent}",
                ],
                Path.home(),
            )
            match = re.search(r"\bpid = (\d+)", description)
            if not match:
                raise ValueError(f"No running PID for {target}")
            command_line = run(
                ["/bin/ps", "-p", match[1], "-o", "command="], Path.home()
            )
        if package not in command_line:
            raise ValueError(f"Running command does not match built {target} package")


def push_candidate(candidate, manifest, directory, night):
    if run(["git", "rev-parse", "HEAD"], candidate) != manifest["source"]:
        raise ValueError("Maintenance agent changed source commits")
    changes = run(
        ["git", "status", "--porcelain", "--untracked-files=all"], candidate
    ).splitlines()
    # run() strips leading whitespace; inspect Git's status code accordingly.
    if changes not in ([], ["M nix/flake.lock"]):
        raise ValueError("Unexpected maintenance source changes")
    if json.loads((candidate / "nix/flake.lock").read_text()) != manifest["lock"]:
        raise ValueError("Maintenance agent changed validated pins")
    if not changes:
        persist(
            directory,
            {
                "outcome": "updated",
                "night": night,
                "commit": manifest["source"],
                "pins_changed": False,
            },
        )
        return
    run(["git", "add", "--", "nix/flake.lock"], candidate)
    run(
        [
            "git",
            "commit",
            "-m",
            "chore(nix): update nightly fleet app pins",
            "--",
            "nix/flake.lock",
        ],
        candidate,
    )
    commit = run(["git", "rev-parse", "HEAD"], candidate)
    receipt = {
        "outcome": "pending-push",
        "night": night,
        "candidate": str(candidate),
        "commit": commit,
        "base": manifest["source"],
    }
    persist(directory, receipt)
    # A rejected push leaves this immutable candidate for a push-only reconciliation.
    run(["git", "push", "origin", "HEAD:main"], candidate, timeout=120)
    receipt["outcome"] = "updated"
    persist(directory, receipt)


def scheduled(checkout, state_directory, task_file):
    state_file = state_directory / "latest.json"
    previous = json.loads(state_file.read_text()) if state_file.exists() else {}
    now = dt.datetime.now(dt.UTC)
    if (state_directory / "paused").exists():
        return
    if previous.get("outcome") in {"maintaining", "uncertain", "pending-push"}:
        # Never repeat live work or guess whether a push/migration completed.
        return
    if attempt_reason(previous, now):
        return
    night = due_day(now, previous.get("night"))
    directory = state_directory / "runs" / night
    directory.mkdir(parents=True, exist_ok=False)
    candidate = directory / "candidate"
    receipt = {"night": night, "run_directory": str(directory)}
    persist(state_directory, {**receipt, "outcome": "preparing"})
    try:
        if tree_bytes(state_directory) > 32 * 1024**3:
            persist(
                state_directory,
                {
                    **receipt,
                    "outcome": "deferred",
                    "reason": "retained-evidence-capacity",
                },
            )
            return
        manifest = prepare(checkout, candidate, build=False)
        write_json(directory / "candidate.json", manifest)
        if manifest["outcome"] == "no-change":
            persist(state_directory, {**receipt, "outcome": "no-change"})
            discard_candidate(candidate, state_directory)
            return
        reason = idle_reason()
        if reason or (state_directory / "paused").exists():
            persist(
                state_directory,
                {
                    **receipt,
                    "outcome": "deferred",
                    "reason": reason or "operator-pause",
                },
            )
            discard_candidate(candidate, state_directory)
            return
        manifest["builds"] = build_candidates(candidate, manifest["changed"])
        write_json(directory / "candidate.json", manifest)
        reason = idle_reason()
        if reason or (state_directory / "paused").exists():
            persist(
                state_directory,
                {
                    **receipt,
                    "outcome": "deferred",
                    "reason": reason or "operator-pause",
                },
            )
            discard_candidate(candidate, state_directory)
            return
        persist(state_directory, {**receipt, "outcome": "maintaining"})
        result = launch_maintenance(candidate, directory, task_file, manifest)
        write_json(directory / "maintenance.json", result)
        if result["outcome"] != "updated":
            outcome = "uncertain" if result["mutated"] else result["outcome"]
            persist(
                state_directory,
                {**receipt, "outcome": outcome, "reason": result["reason"]},
            )
            return
        verify_commands(manifest)
        push_candidate(candidate, manifest, state_directory, night)
    except Exception as error:
        current = json.loads(state_file.read_text())
        phase = current.get("outcome")
        if phase == "pending-push":
            return
        outcome = "uncertain" if phase == "maintaining" else "failed"
        persist(
            state_directory,
            {**receipt, "outcome": outcome, "error": type(error).__name__},
        )


def versions(checkout):
    return {
        target: json.loads(
            run(["nix", "eval", "--json", f"./nix#{attr}.version"], checkout)
        )
        for target, attr in ATTRS.items()
    }


def tree_bytes(directory):
    return sum(
        item.stat().st_size
        for item in directory.rglob("*")
        if not item.is_symlink() and item.is_file()
    )


def discard_candidate(candidate, state_directory):
    expected = state_directory.resolve() / "runs"
    if (
        candidate.is_symlink()
        or candidate.name != "candidate"
        or candidate.resolve().parent.parent != expected
    ):
        raise ValueError("Refusing to remove a path outside a disposable source clone")
    shutil.rmtree(candidate)


def live_versions():
    import plistlib
    import shlex

    local = json.loads((Path.home() / ".t3/userdata/server-runtime.json").read_text())[
        "serverVersion"
    ]
    plist = (
        Path.home() / "Library/LaunchAgents/org.nix-community.home.openclaw-node.plist"
    )
    with plist.open("rb") as stream:
        arguments = plistlib.load(stream)["ProgramArguments"]
    match = re.search(r"/nix/store/[^\s]+/bin/openclaw", " ".join(arguments))
    if not match:
        raise ValueError("Cannot identify the installed M1 node runtime")
    node = run([match[0], "--version"], Path.home())
    remote_code = (
        "import json,pathlib,re,subprocess; "
        "t=json.loads(pathlib.Path('/srv/t3code/.t3code/userdata/server-runtime.json').read_text())['serverVersion']; "
        "s=subprocess.check_output(['systemctl','show','openclaw','-p','ExecStart','--value'],text=True); "
        "p=re.search(r'/nix/store/[^ ;}]+/bin/openclaw',s)[0]; "
        "v=subprocess.check_output([p,'--version'],text=True); print(json.dumps([t,v]))"
    )
    remote_t3, remote_gateway = json.loads(
        run(
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                "-o",
                "ConnectTimeout=10",
                "root@obelisk",
                "python3 -c " + shlex.quote(remote_code),
            ],
            Path.home(),
            timeout=45,
        )
    )

    def parsed(text):
        match = re.search(r"\b(\d+\.\d+\.\d+(?:-nightly\.\d{8}\.\d+)?)\b", text)
        if not match:
            raise ValueError("Unknown live version")
        version_key(match[1])
        return match[1]

    return {
        "m1-t3": parsed(local),
        "m1-openclaw": parsed(node),
        "obelisk-t3": parsed(remote_t3),
        "obelisk-openclaw": parsed(remote_gateway),
    }


def linux_builder():
    for line in Path("/etc/nix/linux-builder.conf").read_text().splitlines():
        if line.startswith("extra-builders = "):
            builder = line.split(" = ", 1)[1]
            if builder.startswith("ssh-ng://builder@linux-builder "):
                return builder
    raise ValueError("The Mac Linux VM builder is not configured")


def prepare(checkout, destination, build=True):
    """Only clone committed source; no caller worktree or live state is modified."""
    origin = run(["git", "remote", "get-url", "origin"], checkout)
    run(
        [
            "git",
            "clone",
            "--single-branch",
            "--branch",
            "main",
            origin,
            str(destination),
        ],
        checkout,
    )
    before = versions(destination)
    old_lock = json.loads((destination / "nix/flake.lock").read_text())
    run(["nix", "flake", "update", *INPUTS], destination / "nix")
    new_lock = json.loads((destination / "nix/flake.lock").read_text())
    validate_input_scope(old_lock, new_lock)
    after = versions(destination)
    installed = live_versions()
    changed = changed_versions(installed, after)
    files = run(["git", "diff", "--name-only"], destination).splitlines()
    if files not in ([], ["nix/flake.lock"]):
        raise ValueError("Candidate changed files outside the permitted lockfile")
    if not changed:
        return {"outcome": "no-change", "versions": installed}
    releases = {
        app: official_release(app, after[f"m1-{app}"])
        for app in ("t3", "openclaw")
        if app in changed_apps(changed)
    }
    result = {
        "outcome": "prepared",
        "before": before,
        "installed": installed,
        "after": after,
        "changed": changed,
        "releases": releases,
        "source": run(["git", "rev-parse", "HEAD"], destination),
        "lock": new_lock,
    }
    if build:
        result["builds"] = build_candidates(destination, changed)
    return result


def build_candidates(destination, changed):
    if shutil.disk_usage(destination).free < 10 * 1024**3:
        raise ValueError("Insufficient M1 headroom for app candidate builds")
    run(["just", "check"], destination, timeout=3600)
    builds = {}
    for target in changed:
        args = [
            "nix",
            "build",
            "--out-link",
            str(destination.parent / f"{target}-runtime"),
            "--print-out-paths",
            f"./nix#{ATTRS[target]}",
        ]
        if target.startswith("obelisk"):
            # Never execute a NixOS build on Obelisk. The Mac's Linux VM is the builder.
            args += ["--max-jobs", "0", "--builders", linux_builder()]
        builds[target] = run(args, destination, timeout=7200)
        if not re.fullmatch(r"/nix/store/[a-z0-9]{32}-[^\s]+", builds[target]):
            raise ValueError("Unexpected build output")
    return builds


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--prepare", action="store_true")
    mode.add_argument("--scheduled", action="store_true")
    mode.add_argument("--verify", action="store_true")
    mode.add_argument("--initialize", action="store_true")
    parser.add_argument(
        "--repo", type=Path, default=Path(__file__).resolve().parents[1]
    )
    parser.add_argument(
        "--task",
        type=Path,
        default=Path(__file__).with_name("nightly-app-update-task.md"),
    )
    parser.add_argument("--state-dir", type=Path, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    args.state_dir.mkdir(parents=True, exist_ok=True)
    if args.verify:
        state = args.state_dir / "latest.json"
        receipt = (
            json.loads(state.read_text())
            if state.exists()
            else {"outcome": "not-initialized"}
        )
        now = dt.datetime.now(ZONE)
        night = dt.date.fromisoformat(receipt.get("night", due_day(now, None)))
        next_night = dt.datetime.combine(night + dt.timedelta(days=1), dt.time(2), ZONE)
        print(
            json.dumps(
                {
                    "state": receipt,
                    "paused": (args.state_dir / "paused").exists(),
                    "timezone": "Europe/Stockholm",
                    "next_night": next_night.isoformat(),
                    "dispatch_resolution_seconds": 60,
                },
                indent=2,
            )
        )
        return
    with (args.state_dir / "lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        if args.initialize:
            if not (args.state_dir / "latest.json").exists():
                persist(
                    args.state_dir,
                    {
                        "outcome": "initialized",
                        "night": due_day(dt.datetime.now(dt.UTC), None),
                    },
                )
            return
        if args.scheduled:
            scheduled(args.repo, args.state_dir, args.task)
            return
        with tempfile.TemporaryDirectory(prefix="nightly-app-update-") as directory:
            succeeded = prepare_recorded(
                args.repo,
                Path(directory) / "candidate",
                args.state_dir,
            )
        if not succeeded:
            raise SystemExit(1)


if __name__ == "__main__":
    main()
