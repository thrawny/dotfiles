"""Ranking, tie-breaking, and queue walking for the Herdr next-agent jump."""

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
        "HERDR_PLUGIN_STATE_DIR": str(tmp_path / "state"),
    }
    env.pop("HERDR_PANE_ID", None)

    def run():
        return subprocess.run(
            [str(SCRIPT)], env=env, capture_output=True, text=True, check=False
        )

    return run, env, log


def seen(env: dict[str, str]) -> dict[str, int]:
    return json.loads((Path(env["HERDR_PLUGIN_STATE_DIR"]) / "seen.json").read_text())


def mark_seen(env: dict[str, str], **panes: int) -> None:
    state = Path(env["HERDR_PLUGIN_STATE_DIR"])
    state.mkdir(parents=True, exist_ok=True)
    (state / "seen.json").write_text(
        json.dumps({p.replace("_", ":"): seq for p, seq in panes.items()})
    )


def test_ranks_blocked_over_idle(jumper: Jumper):
    run, env, log = jumper
    env["AGENTS"] = agents(
        agent("w1:p1", "idle", 1),
        agent("w2:p1", "idle", 2),
        agent("w3:p1", "blocked", 3),
    )
    assert run().returncode == 0
    assert log.read_text().splitlines() == [
        "workspace focus w3",
        "tab focus w3:t1",
        "agent focus w3:p1",
    ]


def test_longest_quiet_wins_its_tier(jumper: Jumper):
    run, env, log = jumper
    env["AGENTS"] = agents(
        agent("w1:p1", "blocked", 90),
        agent("w2:p1", "blocked", 12),
    )
    assert run().returncode == 0
    assert log.read_text().splitlines() == [
        "workspace focus w2",
        "tab focus w2:t1",
        "agent focus w2:p1",
    ]


def test_working_agents_are_never_targets(jumper: Jumper):
    run, env, log = jumper
    env["AGENTS"] = agents(
        agent("w1:p1", "working", 1),
        agent("w2:p1", "unknown", 2),
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
    assert log.read_text().splitlines() == [
        "workspace focus w2",
        "tab focus w2:t1",
        "agent focus w2:p1",
    ]


def test_queue_wraps_at_the_end(jumper: Jumper):
    run, env, log = jumper
    env["AGENTS"] = agents(
        agent("w1:p1", "blocked", 1),
        agent("w2:p1", "idle", 2),
    )
    env["HERDR_PANE_ID"] = "w2:p1"
    assert run().returncode == 0
    assert log.read_text().splitlines() == [
        "workspace focus w1",
        "tab focus w1:t1",
        "agent focus w1:p1",
    ]


def test_falls_back_to_the_focused_agent_as_pivot(jumper: Jumper):
    run, env, log = jumper
    env["AGENTS"] = agents(
        agent("w1:p1", "blocked", 1, focused=True),
        agent("w2:p1", "blocked", 2),
    )
    assert run().returncode == 0
    assert log.read_text().splitlines() == [
        "workspace focus w2",
        "tab focus w2:t1",
        "agent focus w2:p1",
    ]


def test_unranked_pane_lands_on_the_top_of_the_queue(jumper: Jumper):
    run, env, log = jumper
    env["AGENTS"] = agents(
        agent("w1:p1", "idle", 5),
        agent("w2:p1", "blocked", 9),
    )
    env["HERDR_PANE_ID"] = "w9:pZ"
    assert run().returncode == 0
    assert log.read_text().splitlines() == [
        "workspace focus w2",
        "tab focus w2:t1",
        "agent focus w2:p1",
    ]


def test_finished_since_last_seen_outranks_merely_quiet(jumper: Jumper):
    run, env, log = jumper
    env["AGENTS"] = agents(
        agent("w1:p1", "idle", 10),
        agent("w2:p1", "idle", 40),
    )
    # w1:p1 has not moved since we looked; w2:p1 has finished something since.
    mark_seen(env, w1_p1=10, w2_p1=7)
    assert run().returncode == 0
    assert log.read_text().splitlines() == [
        "workspace focus w2",
        "tab focus w2:t1",
        "agent focus w2:p1",
    ]


def test_visiting_an_agent_clears_its_unseen_status(jumper: Jumper):
    run, env, log = jumper
    env["AGENTS"] = agents(
        agent("w1:p1", "idle", 10),
        agent("w2:p1", "idle", 40),
    )
    mark_seen(env, w1_p1=10, w2_p1=7)
    assert run().returncode == 0
    assert seen(env)["w2:p1"] == 40

    # Second press: nothing is unseen any more, so the quietest tier decides and
    # the pivot advances off w2:p1.
    log.unlink()
    env["HERDR_PANE_ID"] = "w2:p1"
    assert run().returncode == 0
    assert log.read_text().splitlines() == [
        "workspace focus w1",
        "tab focus w1:t1",
        "agent focus w1:p1",
    ]


def test_never_visited_agents_count_as_unseen(jumper: Jumper):
    run, env, log = jumper
    env["AGENTS"] = agents(
        agent("w1:p1", "idle", 90),
        agent("w2:p1", "idle", 95),
    )
    mark_seen(env, w1_p1=90)
    assert run().returncode == 0
    assert log.read_text().splitlines()[-1] == "agent focus w2:p1"


def test_forgets_panes_that_no_longer_exist(jumper: Jumper):
    run, env, _ = jumper
    env["AGENTS"] = agents(agent("w1:p1", "idle", 3))
    mark_seen(env, w9_pZ=1)
    assert run().returncode == 0
    assert seen(env) == {"w1:p1": 3}


def test_survives_a_corrupt_state_file(jumper: Jumper):
    run, env, log = jumper
    env["AGENTS"] = agents(agent("w1:p1", "blocked", 3))
    state = Path(env["HERDR_PLUGIN_STATE_DIR"])
    state.mkdir(parents=True, exist_ok=True)
    (state / "seen.json").write_text("not json at all")
    assert run().returncode == 0
    assert log.read_text().splitlines()[-1] == "agent focus w1:p1"
