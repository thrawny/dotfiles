"""Run configured hooks against stubs, never the real agent-switch daemon."""

import json
import os
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
CONFIGS = [
    "config/claude/settings.example.json",
    "config/codex/hooks.agent-switch.json",
]


def tracking_hooks():
    for config in CONFIGS:
        data = json.loads((ROOT / config).read_text())
        for event, groups in data.get("hooks", {}).items():
            for group in groups:
                for hook in group["hooks"]:
                    if "agent-switch track" in hook.get("command", ""):
                        yield config, event, hook["command"]


@pytest.mark.parametrize("config,event,command", list(tracking_hooks()))
@pytest.mark.parametrize("herdr", [None, "0", "1"])
def test_herdr_suppresses_only_agent_switch(
    tmp_path: Path, config: str, event: str, command: str, herdr: str | None
) -> None:
    shell = shutil.which("sh")
    assert shell
    calls = tmp_path / "calls.json"
    agent = tmp_path / "agent-switch"
    agent.write_text(
        f"""#!{sys.executable}
import json, os, sys
from pathlib import Path
Path(os.environ['HOOK_CALLS']).write_text(json.dumps({{
    'args': sys.argv[1:], 'payload': json.load(sys.stdin)
}}))
"""
    )
    agent.chmod(0o755)
    # Preserve the test PATH rather than sourcing the user's login profile.
    shim = tmp_path / "sh"
    shim.write_text(f'#!{shell}\nexec {shlex.quote(shell)} -c "$2"\n')
    shim.chmod(0o755)
    jq = tmp_path / "jq"
    jq.write_text(
        f"""#!{sys.executable}
import json, sys
data = json.load(sys.stdin)
data['notification_type'] = 'permission_prompt'
json.dump(data, sys.stdout)
"""
    )
    jq.chmod(0o755)
    env = dict(
        os.environ, PATH=f"{tmp_path}:{os.environ['PATH']}", HOOK_CALLS=str(calls)
    )
    env.pop("HERDR_ENV", None)
    if herdr is not None:
        env["HERDR_ENV"] = herdr
    payload = {"session_id": "test-session", "cwd": "/work"}
    result = subprocess.run(
        [shell, "-c", command],
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        env=env,
        timeout=5,
    )
    assert result.returncode == 0, (config, event, result.stderr)
    if herdr == "1":
        assert not calls.exists()
    else:
        call = json.loads(calls.read_text())
        assert call["args"][0] == "track"
        assert call["payload"]["session_id"] == payload["session_id"]
        if event == "PermissionRequest":
            assert call["payload"]["notification_type"] == "permission_prompt"
