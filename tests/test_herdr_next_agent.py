"""Attention ranking, queue walking, and finished-agent tracking for the jump."""

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


def payload(pane_id: str) -> str:
    return json.dumps({"data": {"type": "pane_focused", "pane_id": pane_id}})


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
        "HERDR_PLUGIN_STATE_DIR": str(tmp_path / "state"),
    }
    for stale in ("HERDR_PANE_ID", "HERDR_PLUGIN_EVENT", "HERDR_PLUGIN_EVENT_JSON"):
        env.pop(stale, None)

    def run(*args: str):
        return subprocess.run(
            [str(SCRIPT), *args], env=env, capture_output=True, text=True, check=False
        )

    return run, env, log


def finished(env: dict[str, str]) -> dict[str, bool]:
    path = Path(env["HERDR_PLUGIN_STATE_DIR"]) / "finished.json"
    return json.loads(path.read_text()) if path.exists() else {}


def mark_finished(env: dict[str, str], *panes: str) -> None:
    state = Path(env["HERDR_PLUGIN_STATE_DIR"])
    state.mkdir(parents=True, exist_ok=True)
    (state / "finished.json").write_text(json.dumps({pane: True for pane in panes}))


def fire(
    run: Callable[..., subprocess.CompletedProcess[str]],
    env: dict[str, str],
    name: str,
    pane: str,
) -> None:
    env["HERDR_PLUGIN_EVENT"] = name
    env["HERDR_PLUGIN_EVENT_JSON"] = payload(pane)
    result = run("--event")
    assert result.returncode == 0, result.stderr


def test_blocked_outranks_finished(jumper: Jumper):
    run, env, log = jumper
    env["AGENTS"] = agents(
        agent("w1:p1", "idle", 1),
        agent("w2:p1", "blocked", 2),
    )
    mark_finished(env, "w1:p1")
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
        agent("w2:p1", "idle", 2),
    )
    mark_finished(env, "w2:p1")
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


def test_jumping_clears_the_target(jumper: Jumper):
    run, env, _ = jumper
    env["AGENTS"] = agents(agent("w1:p1", "idle", 1))
    mark_finished(env, "w1:p1")
    assert run().returncode == 0
    assert finished(env) == {}


def test_going_quiet_unwatched_counts_as_finished(jumper: Jumper):
    run, env, _ = jumper
    env["AGENTS"] = agents(agent("w1:p1", "idle", 5))
    fire(run, env, "pane.agent_status_changed", "w1:p1")
    assert finished(env) == {"w1:p1": True}


def test_going_quiet_while_watched_does_not_count(jumper: Jumper):
    run, env, _ = jumper
    env["AGENTS"] = agents(agent("w1:p1", "idle", 5, focused=True))
    fire(run, env, "pane.agent_status_changed", "w1:p1")
    assert finished(env) == {}


def test_picking_work_back_up_clears_finished(jumper: Jumper):
    run, env, _ = jumper
    env["AGENTS"] = agents(agent("w1:p1", "working", 6))
    mark_finished(env, "w1:p1")
    fire(run, env, "pane.agent_status_changed", "w1:p1")
    assert finished(env) == {}


def test_focusing_a_pane_clears_it_however_you_got_there(jumper: Jumper):
    run, env, _ = jumper
    env["AGENTS"] = agents(agent("w1:p1", "idle", 5), agent("w2:p1", "idle", 6))
    mark_finished(env, "w1:p1", "w2:p1")
    fire(run, env, "pane.focused", "w1:p1")
    assert finished(env) == {"w2:p1": True}


def test_events_without_a_pane_are_ignored(jumper: Jumper):
    run, env, _ = jumper
    env["HERDR_PLUGIN_EVENT"] = "pane.focused"
    env["HERDR_PLUGIN_EVENT_JSON"] = "{}"
    assert run("--event").returncode == 0
    assert finished(env) == {}


def test_survives_a_corrupt_state_file(jumper: Jumper):
    run, env, log = jumper
    env["AGENTS"] = agents(agent("w1:p1", "blocked", 3))
    state = Path(env["HERDR_PLUGIN_STATE_DIR"])
    state.mkdir(parents=True, exist_ok=True)
    (state / "finished.json").write_text("not json at all")
    assert run().returncode == 0
    assert log.read_text().splitlines()[-1] == "agent focus w1:p1"
