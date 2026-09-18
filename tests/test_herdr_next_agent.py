"""Attention ranking, tie-breaking, and queue walking for the Herdr agent jump."""

import json
import os
import subprocess
from collections.abc import Callable
from pathlib import Path

import pytest

Jumper = tuple[Callable[..., subprocess.CompletedProcess[str]], dict[str, str], Path]

SCRIPT = Path(__file__).resolve().parents[1] / "bin/herdr-next-agent"


def agent(pane_id: str, status: str, seq: int, focused: bool = False) -> dict:
    workspace, _, pane = pane_id.partition(":")
    return {
        "pane_id": pane_id,
        "workspace_id": workspace,
        "tab_id": f"{workspace}:t{pane.lstrip('p')}",
        "agent_status": status,
        "state_change_seq": seq,
        "focused": focused,
    }


def agents(*entries: dict) -> str:
    return json.dumps({"result": {"agents": list(entries)}})


@pytest.fixture
def jumper(tmp_path: Path) -> Jumper:
    tools = tmp_path / "tools"
    tools.mkdir()
    log = tmp_path / "calls"

    herdr = tools / "herdr"
    herdr.write_text(
        "#!/usr/bin/env bash\n"
        'case "$1 $2" in\n'
        '"agent list") printf "%s" "$AGENTS" ;;\n'
        '*) printf "%s\\n" "$*" >> "$LOG" ;;\n'
        "esac\n"
    )
    herdr.chmod(0o755)

    env = {
        **os.environ,
        "PATH": f"{tools}:{os.environ['PATH']}",
        "HERDR_BIN_PATH": str(herdr),
        "LOG": str(log),
        "AGENTS": agents(),
    }
    env.pop("HERDR_PANE_ID", None)

    def run():
        return subprocess.run(
            [str(SCRIPT)], env=env, capture_output=True, text=True, check=False
        )

    return run, env, log


def test_blocked_outranks_finished(jumper: Jumper):
    run, env, log = jumper
    env["AGENTS"] = agents(
        agent("w1:p1", "done", 1),
        agent("w2:p1", "blocked", 2),
    )
    assert run().returncode == 0
    assert log.read_text().splitlines() == [
        "workspace focus w2",
        "tab focus w2:t1",
        "agent focus w2:p1",
    ]


def test_longest_waiting_wins_its_tier(jumper: Jumper):
    run, env, log = jumper
    env["AGENTS"] = agents(
        agent("w1:p1", "blocked", 90),
        agent("w2:p1", "blocked", 12),
    )
    assert run().returncode == 0
    assert log.read_text().splitlines()[-1] == "agent focus w2:p1"


def test_quiet_and_working_agents_are_never_targets(jumper: Jumper):
    run, env, log = jumper
    env["AGENTS"] = agents(
        agent("w1:p1", "idle", 1),
        agent("w2:p1", "working", 2),
        agent("w3:p1", "unknown", 3),
    )
    assert run().returncode == 0
    assert log.read_text().splitlines() == [
        "notification show Nothing needs you --sound none"
    ]


def test_invoking_pane_advances_the_queue(jumper: Jumper):
    run, env, log = jumper
    env["AGENTS"] = agents(
        agent("w1:p1", "blocked", 1),
        agent("w2:p1", "blocked", 2),
    )
    env["HERDR_PANE_ID"] = "w1:p1"
    assert run().returncode == 0
    assert log.read_text().splitlines()[-1] == "agent focus w2:p1"


def test_queue_wraps_at_the_end(jumper: Jumper):
    run, env, log = jumper
    env["AGENTS"] = agents(
        agent("w1:p1", "blocked", 1),
        agent("w2:p1", "done", 2),
    )
    env["HERDR_PANE_ID"] = "w2:p1"
    assert run().returncode == 0
    assert log.read_text().splitlines()[-1] == "agent focus w1:p1"


def test_falls_back_to_the_focused_agent_as_pivot(jumper: Jumper):
    run, env, log = jumper
    env["AGENTS"] = agents(
        agent("w1:p1", "blocked", 1, focused=True),
        agent("w2:p1", "blocked", 2),
    )
    assert run().returncode == 0
    assert log.read_text().splitlines()[-1] == "agent focus w2:p1"
