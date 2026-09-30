"""Task records, wake rules, reports and cleanup checks. No live Herdr or GitHub."""

import argparse
import importlib.util
import json
import subprocess
from importlib.machinery import SourceFileLoader
from pathlib import Path
from types import ModuleType
from typing import Any
from unittest.mock import patch

import pytest

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def orch() -> ModuleType:
    loader = SourceFileLoader("orch", str(ROOT / "bin/orch"))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


@pytest.fixture(autouse=True)
def state_home(tmp_path: Path):
    with patch.dict(
        "os.environ", {"XDG_STATE_HOME": str(tmp_path / "state")}, clear=True
    ):
        yield tmp_path / "state"


def task(pane_id: str = "w1:p1", **fields: Any) -> dict[str, Any]:
    return {
        "agent": "abc-1",
        "repo": "/code/widgets",
        "branch": "ABC-1-fix",
        "pane_id": pane_id,
        "tab_id": "w1:t1",
        "workspace_id": "w1",
        "cwd": "/code/widgets-ABC-1-fix",
        "report": None,
        "pr": None,
        "seen": {"status": "working"},
        **fields,
    }


def live(status: str, seq: int, pane_id: str = "w1:p1") -> dict[str, dict[str, Any]]:
    return {
        pane_id: {"pane_id": pane_id, "agent_status": status, "state_change_seq": seq}
    }


def test_turn_end_wakes_once(orch: ModuleType):
    tasks = {"abc-1": task()}
    assert orch.check(tasks, live("working", 1), 0) == []
    assert orch.check(tasks, live("done", 2), 0) == [
        "abc-1: turn ended without a report"
    ]
    assert orch.check(tasks, live("done", 2), 0) == []


def test_looking_at_a_done_worker_is_not_news(orch: ModuleType):
    tasks = {"abc-1": task(seen={"status": "done", "seq": 2})}
    assert orch.check(tasks, live("idle", 3), 0) == []


def test_watched_turn_that_ends_idle_wakes(orch: ModuleType):
    tasks = {"abc-1": task()}
    assert orch.check(tasks, live("idle", 2), 0) == [
        "abc-1: turn ended without a report"
    ]


def test_turn_that_ended_while_nobody_watched_wakes(orch: ModuleType):
    # Answered in its tab, then finished, all between two watches.
    tasks = {"abc-1": task(seen={"status": "done", "seq": 2})}
    assert orch.check(tasks, live("done", 4), 0) == [
        "abc-1: turn ended without a report"
    ]


def test_report_waits_for_the_turn_to_end(orch: ModuleType):
    report = {"kind": "question", "text": "Which base?", "at": 100.0}
    tasks = {"abc-1": task(report=report)}
    assert orch.check(tasks, live("working", 1), 105) == []
    assert orch.check(tasks, live("done", 2), 106) == ["abc-1 question: Which base?"]
    assert orch.check(tasks, live("done", 2), 107) == []


def test_report_from_a_turn_that_runs_on_wakes_after_settling(orch: ModuleType):
    report = {"kind": "blocked", "text": "no creds", "at": 100.0}
    tasks = {"abc-1": task(report=report)}
    settled = 100 + orch.REPORT_SETTLE_SECONDS
    assert orch.check(tasks, live("working", 1), settled) == ["abc-1 blocked: no creds"]


def test_prompt_and_closed_pane_wake(orch: ModuleType):
    tasks = {"abc-1": task()}
    assert orch.check(tasks, live("blocked", 2), 0) == [
        "abc-1 blocked: waiting at an approval or question prompt"
    ]
    assert orch.check(tasks, {}, 0) == ["abc-1: pane closed"]
    assert orch.check(tasks, {}, 0) == []


def test_unknown_state_is_skipped(orch: ModuleType):
    tasks = {"abc-1": task()}
    assert orch.check(tasks, live("unknown", 2), 0) == []
    assert tasks["abc-1"]["seen"] == {"status": "working"}


def test_report_finds_its_task_by_pane_and_keeps_the_pr(orch: ModuleType):
    with orch.tasks_for_update() as tasks:
        tasks["abc-1"] = task()
    args = argparse.Namespace(
        kind="done", text=["PR", "https://github.com/o/r/pull/7", "ready"], agent=None
    )
    with patch.dict("os.environ", {"HERDR_PANE_ID": "w1:p1"}):
        assert orch.cmd_report(args) == 0
    saved = orch.read_tasks()["abc-1"]
    assert saved["report"]["kind"] == "done"
    assert saved["pr"] == "https://github.com/o/r/pull/7"


def test_report_from_a_pane_orch_did_not_start_fails(orch: ModuleType):
    args = argparse.Namespace(kind="done", text=["x"], agent=None)
    with patch.dict("os.environ", {"HERDR_PANE_ID": "w9:p9"}):
        with pytest.raises(orch.OrchError, match="not an orch task"):
            orch.cmd_report(args)


def test_failed_update_writes_nothing(orch: ModuleType, state_home: Path):
    with pytest.raises(orch.OrchError):
        with orch.tasks_for_update() as tasks:
            tasks["abc-1"] = task()
            raise orch.OrchError("boom")
    assert not (state_home / "orch/tasks.json").exists()


def test_spawn_adds_the_report_footer_and_records_the_task(orch: ModuleType):
    details = {
        "agent": "abc-1",
        "repo": "/code/widgets",
        "branch": "ABC-1-fix",
        "cwd": "/code/widgets-ABC-1-fix",
        "pane_id": "w1:p1",
        "tab_id": "w1:t1",
        "workspace_id": "w1",
    }
    args = argparse.Namespace(
        repo="widgets", worktree="ABC-1-fix", base=None, name=None
    )
    with (
        patch("sys.stdin.read", return_value="Fix it."),
        patch.object(orch, "run", return_value=json.dumps(details)) as run,
    ):
        assert orch.cmd_spawn(args) == 0
    command = run.call_args.args[0]
    assert command == [
        "spawn-session",
        "--json",
        "--repo",
        "widgets",
        "--worktree",
        "ABC-1-fix",
    ]
    assert run.call_args.kwargs["stdin"].startswith(
        "Fix it.\n\norch started this session"
    )
    assert orch.read_tasks()["abc-1"]["seen"] == {"status": "working"}


def git(cwd: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(cwd), *args], check=True, capture_output=True)


@pytest.fixture
def pushed_clone(tmp_path: Path) -> Path:
    remote, clone = tmp_path / "remote.git", tmp_path / "clone"
    subprocess.run(["git", "init", "-q", "--bare", str(remote)], check=True)
    subprocess.run(
        ["git", "clone", "-q", str(remote), str(clone)], check=True, capture_output=True
    )
    git(
        clone,
        "-c",
        "user.name=t",
        "-c",
        "user.email=t@t",
        "commit",
        "-q",
        "--allow-empty",
        "-m",
        "one",
    )
    git(clone, "push", "-q", "origin", "HEAD")
    return clone


def test_pushed_clean_checkout_is_safe_to_remove(orch: ModuleType, pushed_clone: Path):
    assert orch.unsaved_work(str(pushed_clone)) is None


def test_uncommitted_changes_block_removal(orch: ModuleType, pushed_clone: Path):
    (pushed_clone / "new.txt").write_text("x")
    assert (
        orch.unsaved_work(str(pushed_clone)) == "the worktree has uncommitted changes"
    )


def test_unpushed_commits_block_removal_unless_merged(
    orch: ModuleType, pushed_clone: Path
):
    git(
        pushed_clone,
        "-c",
        "user.name=t",
        "-c",
        "user.email=t@t",
        "commit",
        "-q",
        "--allow-empty",
        "-m",
        "two",
    )
    head = subprocess.run(
        ["git", "-C", str(pushed_clone), "rev-parse", "HEAD"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
    real_run = orch.run

    def fake_gh(pr: dict[str, str]):
        def run(args: list[str], **kwargs: Any) -> str:
            return json.dumps(pr) if args[0] == "gh" else real_run(args, **kwargs)

        return run

    with patch.object(orch, "run", fake_gh({"state": "OPEN", "headRefOid": head})):
        assert (
            orch.unsaved_work(str(pushed_clone))
            == "1 commit is on no remote and in no merged PR"
        )
    with patch.object(orch, "run", fake_gh({"state": "MERGED", "headRefOid": head})):
        assert orch.unsaved_work(str(pushed_clone)) is None
