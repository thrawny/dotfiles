#!/usr/bin/env python3
"""Bounded read-only OpenClaw checks; emit only selected diagnostic metadata."""

import hashlib
import json
import os
import re
import shlex
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

# Use the running gateway's service environment, including EnvironmentFile
# overrides, keeping file-backed credentials out of arguments and receipts. The transient unit owns
# every diagnostic child and stops them all at its deadline, even after SSH loss.
BOOTSTRAP = """
import hashlib, json, re, shlex, subprocess, sys, uuid
from pathlib import Path
def fail(reason):
    print(json.dumps({'check':'gateway-identity',
        'result':{'outcome':'failed','error':reason}}), flush=True)
    raise SystemExit(1)
def prop(name):
    return subprocess.check_output(['systemctl','show','openclaw',
        '-p',name,'--value'],text=True).strip()
runtime = re.search(r'/nix/store/[^ ;}]+/bin/openclaw', prop('ExecStart'))[0]
pid = int(prop('MainPID'))
if pid <= 0 or prop('ActiveState') != 'active':
    fail('GatewayNotRunning')
proc = Path('/proc') / str(pid)
arguments = proc.joinpath('cmdline').read_bytes().decode().split('\\0')
package = str(Path(runtime).parent.parent) + '/'
if not any(value.startswith(package) for value in arguments[:2]):
    fail('LoadedRuntimeDiffersFromRunningGateway')
live_env = dict(value.split('=', 1) for value in
    proc.joinpath('environ').read_bytes().decode().split('\\0') if '=' in value)
environment = shlex.split(prop('Environment'))
keys = {value.split('=', 1)[0] for value in environment}
keys.update(re.findall(r'^([A-Za-z_][A-Za-z0-9_]*)=',
    Path('/srv/agents/openclaw/env').read_text(), re.M))
# The OpenClaw wrapper prepends its bundled Node directory to PATH.
keys.discard('PATH')
keys = sorted(keys)
digest = hashlib.sha256(json.dumps({key: live_env.get(key) for key in keys},
    sort_keys=True).encode()).hexdigest()
args = ['systemd-run','--quiet','--wait','--collect','--pipe',
    '--unit=openclaw-diagnostic-'+uuid.uuid4().hex,
    '--property=RuntimeMaxSec=480','--property=TimeoutStopSec=5',
    '--property=EnvironmentFile=/srv/agents/openclaw/env']
for name in ('User','Group','WorkingDirectory'):
    args.append('--property='+name+'='+prop(name))
for value in environment:
    args.append('--setenv='+value)
args += ['python3','-',runtime,json.dumps(keys),digest,str(pid)]
raise SystemExit(subprocess.run(args, input=sys.stdin.read(), text=True).returncode)
"""


def auth_summary(data):
    """Effective selection matters: an unselected healthy login proves nothing."""
    auth = data["auth"]
    providers = []
    for provider in auth["oauth"]["providers"]:
        selected = []
        for profile in provider["effectiveProfiles"]:
            selected.append(
                {
                    "identity": hashlib.sha256(
                        profile["profileId"].encode()
                    ).hexdigest()[:16],
                    "status": profile["status"],
                    "expires_at_ms": profile.get("expiresAt"),
                    "remaining_ms": profile.get("remainingMs"),
                }
            )
        providers.append({"provider": provider["provider"], "effective": selected})
    routes = [
        {
            key: route.get(key)
            for key in (
                "provider",
                "runtime",
                "status",
                "authStatus",
                "runtimeStatus",
                "runtimeReason",
            )
        }
        for route in auth["runtimeAuthRoutes"]
    ]
    return {
        "providers": providers,
        "routes": routes,
        "missing_provider_count": len(auth["missingProvidersInUse"]),
        "route_issue_count": len(auth["modelRouteIssues"]),
        "runtime_ready": bool(routes)
        and all(route["status"] == "usable" for route in routes),
        "selection_ready": bool(routes)
        and bool(providers)
        and not auth["missingProvidersInUse"]
        and not auth["modelRouteIssues"]
        and all(
            (route["authStatus"] or route["status"]) == "usable" for route in routes
        )
        and all(
            provider["effective"]
            and all(
                profile["status"] in {"ok", "static"}
                and (
                    profile["status"] == "static"
                    or isinstance(profile["remaining_ms"], (int, float))
                    and profile["remaining_ms"] > 0
                )
                for profile in provider["effective"]
            )
            for provider in providers
        ),
    }


def memory_summary(data):
    return [
        {
            "agent": item["agentId"],
            "provider": item["status"]["provider"],
            "requested_provider": item["status"]["requestedProvider"],
            "identity": item["status"]["custom"]["indexIdentity"]["status"],
            "dirty": item["status"]["dirty"],
            "fts_available": item["status"]["fts"]["available"],
            "files": item["status"]["files"],
            "chunks": item["status"]["chunks"],
        }
        for item in data
    ]


def doctor_summary(data):
    if type(data.get("schemaVersion")) is not int or data["schemaVersion"] != 1:
        raise ValueError("Unsupported Doctor schema")
    return {
        "schema_version": data["schemaVersion"],
        "ok": data["ok"],
        "checksRun": data["checksRun"],
        "checksSkipped": data["checksSkipped"],
        "findings": [
            {"check": item["checkId"], "severity": item["severity"]}
            for item in data["findings"]
        ],
        "warnings": [
            {"check": item["checkId"], "severity": item["severity"]}
            for item in data.get("warnings", [])
        ],
    }


def collect(runtime):
    started = time.monotonic()
    checks: dict[str, dict[str, Any]] = {}

    def check(name, args, summarize, executable=None):
        entry: dict[str, Any] = {}
        try:
            # No probe/index/fix flags. No auth refresh or model inference.
            result = subprocess.run(
                [executable or runtime, *args],
                capture_output=True,
                text=True,
                timeout=120 if name == "doctor" else 60,
                stdin=subprocess.DEVNULL,
            )
            entry = {"exit_code": result.returncode}
            entry.update(summarize(result.stdout))
            entry["outcome"] = "passed" if result.returncode == 0 else "findings"
            checks[name] = entry
        except (
            OSError,
            subprocess.SubprocessError,
            ValueError,
            KeyError,
            TypeError,
            IndexError,
        ) as error:
            entry.update({"outcome": "failed", "error": type(error).__name__})
            checks[name] = entry
        # Each completed check is streamed; the caller can retain partial evidence
        # if the overall unit deadline expires. No raw CLI output crosses SSH.
        print(json.dumps({"check": name, "result": checks[name]}), flush=True)

    check(
        "version",
        ["--version"],
        version_summary,
    )
    check(
        "config",
        ["config", "validate", "--json"],
        lambda text: {
            "valid": json.loads(text)["valid"],
            "warning_count": len(json.loads(text)["warnings"]),
        },
    )
    check(
        "doctor",
        ["doctor", "--lint", "--json"],
        lambda text: doctor_summary(json.loads(text)),
    )
    check("health", ["health", "--json"], lambda text: health_summary(json.loads(text)))
    check(
        "ui",
        [
            "-c",
            "import urllib.request; "
            "r=urllib.request.urlopen('http://127.0.0.1:18789/',timeout=10); "
            "print(r.status); r.close()",
        ],
        lambda text: {"http_code": int(text)},
        executable=sys.executable,
    )
    check(
        "nodes",
        ["nodes", "status", "--json"],
        lambda text: {
            "nodes": [
                {
                    "platform": item["platform"],
                    "version": item.get("version"),
                    "paired": item["paired"],
                    "connected": item["connected"],
                }
                for item in json.loads(text)["nodes"]
            ]
        },
    )
    agents = []

    def agent_summary(text):
        agents.extend(item["id"] for item in json.loads(text))
        if (
            not agents
            or len(agents) > 16
            or any(not re.fullmatch(r"[a-zA-Z0-9_-]+", agent) for agent in agents)
        ):
            raise ValueError("Unsupported agent inventory")
        return {"agents": agents}

    check("agents", ["agents", "list", "--json"], agent_summary)
    if checks["agents"]["outcome"] == "passed":
        for agent in agents:
            if time.monotonic() - started > 350:
                checks["auth-" + agent] = {"outcome": "failed", "error": "Deadline"}
                continue
            check(
                "auth-" + agent,
                ["models", "status", "--agent", agent, "--check", "--json"],
                lambda text: auth_summary(json.loads(text)),
            )
    check(
        "memory",
        ["memory", "status", "--json"],
        lambda text: {"agents": memory_summary(json.loads(text))},
    )
    memory_agents = checks["memory"].get("agents", [])
    checks["memory"]["ready"] = (
        bool(agents)
        and {item["agent"] for item in memory_agents} == set(agents)
        and all(
            item["identity"] == "valid" and not item["dirty"] and item["fts_available"]
            for item in memory_agents
        )
    )
    print(
        json.dumps(
            {
                "complete": True,
                "checks": checks,
                "runtime": runtime,
                "config_path": os.environ.get("OPENCLAW_CONFIG_PATH"),
                "duration_seconds": round(time.monotonic() - started, 1),
            }
        ),
        flush=True,
    )


def health_summary(data):
    return {
        "ok": data["ok"],
        "plugin_error_count": len(data["plugins"]["errors"]),
        "ready": data["ok"] is True
        and not data["plugins"]["errors"]
        and bool(data["channels"])
        and all(
            channel["configured"] is True
            and channel["running"] is True
            and channel["connected"] is True
            and channel["lastError"] is None
            for channel in data["channels"].values()
        ),
        "channels": {
            name: {
                "configured": channel["configured"],
                "running": channel["running"],
                "connected": channel["connected"],
                "has_error": channel["lastError"] is not None,
            }
            for name, channel in data["channels"].items()
        },
    }


def version_summary(text):
    match = re.search(r"\b\d+\.\d+\.\d+\b", text)
    if match is None:
        raise ValueError("Unknown installed version")
    return {"version": match[0]}


if __name__ == "__main__":
    if sys.argv[1:] == ["--remote"]:
        process = subprocess.run(
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                "-o",
                "ConnectTimeout=10",
                "-o",
                "ServerAliveInterval=15",
                "-o",
                "ServerAliveCountMax=2",
                "thrawny@obelisk",
                "sudo -n python3 -c " + shlex.quote(BOOTSTRAP),
            ],
            input=Path(__file__).read_text(),
            text=True,
            timeout=510,
        )
        raise SystemExit(process.returncode)
    keys = json.loads(sys.argv[2])
    digest = hashlib.sha256(
        json.dumps({key: os.environ.get(key) for key in keys}, sort_keys=True).encode()
    ).hexdigest()
    if digest != sys.argv[3] or not Path("/proc", sys.argv[4]).exists():
        print(
            json.dumps(
                {
                    "check": "gateway-identity",
                    "result": {
                        "outcome": "failed",
                        "error": "RunningGatewayEnvironmentChanged",
                    },
                }
            ),
            flush=True,
        )
        raise SystemExit(1)
    collect(sys.argv[1])
