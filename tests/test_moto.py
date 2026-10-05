"""Task records, wake rules, reports and cleanup checks. No live Herdr or GitHub."""

import argparse
import importlib.util
import json
import os
import signal
import subprocess
import sys
import time
from datetime import UTC, datetime
from importlib.machinery import SourceFileLoader
from pathlib import Path
from types import ModuleType
from typing import Any
from unittest.mock import patch

import pytest

ROOT = Path(__file__).resolve().parents[1]


def load_moto() -> ModuleType:
    loader = SourceFileLoader("moto", str(ROOT / "bin/moto"))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


@pytest.fixture
def moto() -> ModuleType:
    module = load_moto()
    # Unit tests never read a real pane or transcript.
    footer_says(module, None)
    turn_in(module, None, None)
    return module


def footer_says(moto: ModuleType, work: str | None) -> None:
    def background_work(_pane_id: str) -> str | None:
        return work

    setattr(moto, "background_work", background_work)


def turn_in(moto: ModuleType, turn: str | None, prompt: str | None) -> None:
    def last_turn(_task: Any, _agent: Any) -> tuple[str | None, str | None]:
        return turn, prompt

    setattr(moto, "last_turn", last_turn)


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


def test_turn_end_wakes_once(moto: ModuleType):
    tasks = {"abc-1": task()}
    assert moto.check(tasks, live("working", 1), 0) == []
    assert moto.check(tasks, live("done", 2), 0) == [
        "abc-1: turn ended without a report"
    ]
    assert moto.check(tasks, live("done", 2), 0) == []


def test_looking_at_a_done_worker_is_not_news(moto: ModuleType):
    tasks = {"abc-1": task(seen={"status": "done", "seq": 2})}
    assert moto.check(tasks, live("idle", 3), 0) == []


def test_watched_turn_that_ends_idle_wakes(moto: ModuleType):
    tasks = {"abc-1": task()}
    assert moto.check(tasks, live("idle", 2), 0) == [
        "abc-1: turn ended without a report"
    ]


def test_turn_that_ended_while_nobody_watched_wakes(moto: ModuleType):
    # Answered in its tab, then finished, all between two watches.
    tasks = {"abc-1": task(seen={"status": "done", "seq": 2})}
    assert moto.check(tasks, live("done", 4), 0) == [
        "abc-1: turn ended without a report"
    ]


def test_report_waits_for_the_turn_to_end(moto: ModuleType):
    report = {"kind": "question", "text": "Which base?", "at": 100.0}
    tasks = {"abc-1": task(report=report)}
    assert moto.check(tasks, live("working", 1), 105) == []
    assert moto.check(tasks, live("done", 2), 106) == ["abc-1 question: Which base?"]
    assert moto.check(tasks, live("done", 2), 107) == []


def test_report_from_a_turn_that_runs_on_wakes_after_settling(moto: ModuleType):
    report = {"kind": "blocked", "text": "no creds", "at": 100.0}
    tasks = {"abc-1": task(report=report)}
    settled = 100 + moto.REPORT_SETTLE_SECONDS
    assert moto.check(tasks, live("working", 1), settled) == ["abc-1 blocked: no creds"]


def test_prompt_and_closed_pane_wake(moto: ModuleType):
    tasks = {"abc-1": task()}
    assert moto.check(tasks, live("blocked", 2), 0) == [
        "abc-1 blocked: waiting at an approval or question prompt"
    ]
    assert moto.check(tasks, {}, 0) == ["abc-1: pane closed"]
    assert moto.check(tasks, {}, 0) == []


def test_unknown_state_is_skipped(moto: ModuleType):
    tasks = {"abc-1": task()}
    assert moto.check(tasks, live("unknown", 2), 0) == []
    assert tasks["abc-1"]["seen"] == {"status": "working"}


def test_report_finds_its_task_by_pane_and_keeps_the_pr(moto: ModuleType):
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task()
    args = argparse.Namespace(
        kind="done", text=["PR", "https://github.com/o/r/pull/7", "ready"], agent=None
    )
    with patch.dict("os.environ", {"HERDR_PANE_ID": "w1:p1"}):
        assert moto.cmd_report(args) == 0
    saved = moto.read_tasks()["abc-1"]
    assert saved["report"]["kind"] == "done"
    assert saved["pr"] == "https://github.com/o/r/pull/7"


def test_report_from_an_untracked_pane_tells_the_worker_to_ask_directly(
    moto: ModuleType, capsys: pytest.CaptureFixture[str]
):
    args = argparse.Namespace(kind="done", text=["x"], agent=None)
    with patch.dict("os.environ", {"HERDR_PANE_ID": "w9:p9"}):
        assert moto.cmd_report(args) == 0
    assert "Tell the user directly" in capsys.readouterr().out
    assert moto.read_tasks() == {}


def test_report_from_a_held_task_tells_the_worker_to_ask_in_its_pane(
    moto: ModuleType, capsys: pytest.CaptureFixture[str]
):
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task(held=True)
    args = argparse.Namespace(kind="question", text=["Next", "URL?"], agent=None)
    with patch.dict("os.environ", {"HERDR_PANE_ID": "w1:p1"}):
        assert moto.cmd_report(args) == 0
    assert "ask the user directly in this pane" in capsys.readouterr().out
    assert moto.read_tasks()["abc-1"]["report"]["text"] == "Next URL?"


def test_held_task_never_wakes(moto: ModuleType):
    report = {"kind": "question", "text": "Which base?", "at": 100.0}
    tasks = {"abc-1": task(held=True, report=report)}
    assert moto.check(tasks, live("done", 2), 200) == []
    assert moto.check(tasks, {}, 200) == []


def test_resume_treats_what_happened_while_held_as_seen(moto: ModuleType):
    report = {"kind": "question", "text": "Which base?", "at": 100.0}
    tasks = {"abc-1": task(held=True, report=report)}
    moto.resume(tasks["abc-1"], live("done", 5))
    assert tasks["abc-1"]["held"] is False
    assert moto.check(tasks, live("done", 5), 200) == []
    assert moto.check(tasks, live("done", 7), 200) == [
        "abc-1: turn ended without a report"
    ]


def test_watch_with_only_held_tasks_exits(
    moto: ModuleType, capsys: pytest.CaptureFixture[str]
):
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task(held=True)
    with patch.object(moto, "live_agents", side_effect=AssertionError("no poll")):
        assert moto.cmd_watch(argparse.Namespace(max=5)) == 0
    assert "1 held by the user" in capsys.readouterr().out


def test_failed_update_writes_nothing(moto: ModuleType, state_home: Path):
    with pytest.raises(moto.MotoError):
        with moto.tasks_for_update() as tasks:
            tasks["abc-1"] = task()
            raise moto.MotoError("boom")
    assert not (state_home / "moto/tasks.json").exists()


def test_spawn_adds_the_report_footer_and_records_the_task(moto: ModuleType):
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
        repo="widgets",
        worktree="ABC-1-fix",
        base=None,
        name=None,
        title="ABC-1 fix",
        resume=None,
    )
    with (
        patch("sys.stdin.read", return_value="Fix it."),
        patch.object(moto, "run", return_value=json.dumps(details)) as run,
    ):
        assert moto.cmd_spawn(args) == 0
    command = run.call_args.args[0]
    assert command == [
        "spawn-session",
        "--json",
        "--repo",
        "widgets",
        "--worktree",
        "ABC-1-fix",
        "--title",
        "ABC-1 fix",
    ]
    assert run.call_args.kwargs["stdin"].startswith(
        "[driver] Fix it.\n\nA driver session started you"
    )
    assert moto.read_tasks()["abc-1"]["seen"] == {"status": "working"}


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


def test_pushed_clean_checkout_is_safe_to_remove(moto: ModuleType, pushed_clone: Path):
    assert moto.unsaved_work(str(pushed_clone)) is None


def test_uncommitted_changes_block_removal(moto: ModuleType, pushed_clone: Path):
    (pushed_clone / "new.txt").write_text("x")
    assert (
        moto.unsaved_work(str(pushed_clone)) == "the worktree has uncommitted changes"
    )


def test_unpushed_commits_block_removal_unless_merged(
    moto: ModuleType, pushed_clone: Path
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
    real_run = moto.run

    def fake_gh(pr: dict[str, str]):
        def run(args: list[str], **kwargs: Any) -> str:
            return json.dumps(pr) if args[0] == "gh" else real_run(args, **kwargs)

        return run

    with patch.object(moto, "run", fake_gh({"state": "OPEN", "headRefOid": head})):
        assert (
            moto.unsaved_work(str(pushed_clone))
            == "1 commit is on no remote and in no merged PR"
        )
    with patch.object(moto, "run", fake_gh({"state": "MERGED", "headRefOid": head})):
        assert moto.unsaved_work(str(pushed_clone)) is None


def test_workspace_without_checkout_is_found_by_pane_cwd(moto: ModuleType):
    replies: dict[tuple[str, ...], dict[str, Any]] = {
        ("workspace", "list"): {
            "workspaces": [{"workspace_id": "w1", "label": "moto"}]
        },
        ("pane", "list"): {"panes": [{"workspace_id": "w1", "cwd": "/home/moto"}]},
    }

    def herdr(*args: str) -> dict[str, Any]:
        return replies[args]

    with patch.object(moto, "herdr", side_effect=herdr):
        assert moto.checkout_workspace("/home/moto") == "w1"
        assert moto.checkout_workspace("/elsewhere") is None


def test_ask_writes_and_clears_the_driver_question(
    moto: ModuleType, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("HERDR_PANE_ID", "w1:p9")
    path = moto.state_dir() / "driver.json"
    assert moto.cmd_ask(argparse.Namespace(text=["Merge", "#12?"], clear=False)) == 0
    ask = json.loads(path.read_text())
    assert (ask["pane_id"], ask["kind"], ask["text"]) == (
        "w1:p9",
        "question",
        "Merge #12?",
    )
    assert moto.cmd_ask(argparse.Namespace(text=[], clear=True)) == 0
    assert not path.exists()


def test_tell_marks_the_prompt_as_the_driver_s(moto: ModuleType):
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task()
    args = argparse.Namespace(agent="abc-1", text=["Ports", "are", "free."])
    with patch.object(moto, "herdr", return_value={}) as herdr:
        assert moto.cmd_tell(args) == 0
    herdr.assert_called_once_with(
        "agent", "prompt", "abc-1", "[driver] Ports are free."
    )
    with pytest.raises(moto.MotoError, match="No task named"):
        moto.cmd_tell(argparse.Namespace(agent="nope", text=["x"]))
    assert events(moto)[-1]["from"] == "driver"


def test_worker_tells_only_its_own_children_under_its_name(moto: ModuleType):
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task()
        tasks["abc-2"] = task(pane_id="w2:p1", agent="abc-2", parent="abc-1")
        tasks["abc-3"] = task(pane_id="w3:p1", agent="abc-3")
    with (
        patch.dict("os.environ", {"HERDR_PANE_ID": "w1:p1"}),
        patch.object(moto, "herdr", return_value={}) as herdr,
    ):
        assert moto.cmd_tell(argparse.Namespace(agent="abc-2", text=["Retry."])) == 0
        for agent in ("abc-3", "abc-1"):
            with pytest.raises(moto.MotoError, match="only the tasks it started"):
                moto.cmd_tell(argparse.Namespace(agent=agent, text=["x"]))
        with pytest.raises(moto.MotoError, match="To reach the driver"):
            moto.cmd_tell(argparse.Namespace(agent="driver", text=["x"]))
        with pytest.raises(moto.MotoError, match=r"tags yours \[abc-1\]"):
            moto.cmd_tell(argparse.Namespace(agent="abc-2", text=["[driver]", "x"]))
    with (
        patch.dict("os.environ", {"HERDR_PANE_ID": "w2:p1"}),
        pytest.raises(moto.MotoError, match="abc-1 started you and reads your pane"),
    ):
        moto.cmd_tell(argparse.Namespace(agent="abc-1", text=["x"]))
    herdr.assert_called_once_with("agent", "prompt", "abc-2", "[abc-1] Retry.")
    tell = events(moto)[-1]
    assert (tell["event"], tell["agent"], tell["from"]) == ("tell", "abc-2", "abc-1")


def session_file(directory: Path, session: str, *titles: str, mtime: float) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{session}.jsonl"
    lines = [json.dumps({"type": "user", "message": "hi"})]
    lines += [json.dumps({"type": "custom-title", "customTitle": t}) for t in titles]
    path.write_text("\n".join(lines) + "\n")
    os.utime(path, (mtime, mtime))


def test_session_is_the_newest_whose_last_title_matches(
    moto: ModuleType, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
):
    monkeypatch.setattr(moto, "CLAUDE_HOME", tmp_path / "claude")
    directory = moto.session_dir("/code/widgets.x/ABC-1")
    assert directory == tmp_path / "claude/projects/-code-widgets-x-ABC-1"
    session_file(directory, "old", "ABC-1 fix", mtime=100)
    session_file(directory, "new", "ABC-1 fix", mtime=200)
    session_file(directory, "renamed", "ABC-1 fix", "other", mtime=300)
    assert moto.find_session("/code/widgets.x/ABC-1", "ABC-1 fix") == "new"
    with pytest.raises(moto.MotoError, match="is named 'nope'"):
        moto.find_session("/code/widgets.x/ABC-1", "nope")
    with pytest.raises(moto.MotoError, match="No Claude sessions recorded"):
        moto.find_session("/code/elsewhere", "ABC-1 fix")


SNOOZE = {"session": "s1", "reason": "waiting on infra", "at": 100.0}


def test_snoozed_task_never_wakes_and_resume_refuses_it(moto: ModuleType):
    tasks = {"abc-1": task(snoozed=SNOOZE)}
    assert moto.check(tasks, {}, 200) == []
    with moto.tasks_for_update() as saved:
        saved.update(tasks)
    with (
        patch.object(moto, "live_agents", return_value={}),
        pytest.raises(moto.MotoError, match="moto wake"),
    ):
        moto.cmd_resume(argparse.Namespace(agent="abc-1"))


def test_watch_with_only_snoozed_tasks_exits(
    moto: ModuleType, capsys: pytest.CaptureFixture[str]
):
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task(snoozed=SNOOZE)
    with patch.object(moto, "live_agents", side_effect=AssertionError("no poll")):
        assert moto.cmd_watch(argparse.Namespace(max=5)) == 0
    assert "1 snoozed" in capsys.readouterr().out


def test_list_shows_snoozed_tasks_apart(
    moto: ModuleType, capsys: pytest.CaptureFixture[str]
):
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task()
        tasks["abc-2"] = task(pane_id="w2:p1", snoozed=SNOOZE)
    with (
        patch.object(moto, "live_agents", return_value=live("idle", 1)),
        patch.object(moto.time, "time", return_value=100.0 + 7200),
    ):
        assert moto.cmd_list(argparse.Namespace(json=False)) == 0
    out = capsys.readouterr().out
    awake, snoozed = out.split("Snoozed:")
    assert "abc-1" in awake and "abc-2" not in awake
    assert "abc-2 · widgets · ABC-1-fix · 2h\n  waiting on infra" in snoozed


def test_wake_resumes_the_session_at_the_same_worktree_path(
    moto: ModuleType, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
):
    monkeypatch.setattr(moto, "CLAUDE_HOME", tmp_path / "claude")
    cwd = "/code/widgets-ABC-1-fix"
    session_file(moto.session_dir(cwd), "s1", "ABC-1 fix", mtime=100)
    snooze = {**SNOOZE, "title": "ABC-1 fix", "cwd": cwd, "worktree": True}
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task(snoozed=snooze, held=True)
    details = {"cwd": cwd, "pane_id": "w5:p1", "tab_id": "w5:t1", "workspace_id": "w5"}
    args = argparse.Namespace(agent="abc-1", text=["Infra", "is", "done."])
    with (
        patch.object(moto, "run", return_value=json.dumps(details)) as run,
        patch.object(moto, "live_agents", return_value=live("working", 3, "w5:p1")),
    ):
        assert moto.cmd_wake(args) == 0
    assert run.call_args.args[0] == [
        "spawn-session",
        "--json",
        "--repo",
        "/code/widgets",
        "--name",
        "abc-1",
        "--worktree",
        "ABC-1-fix",
        "--path",
        cwd,
        "--title",
        "ABC-1 fix",
        "--resume",
        "s1",
    ]
    assert run.call_args.kwargs["stdin"] == "[driver] Infra is done.\n"
    saved = moto.read_tasks()["abc-1"]
    assert "snoozed" not in saved and saved["held"] is False
    assert (saved["pane_id"], saved["seen"]["status"]) == ("w5:p1", "working")


def test_wake_refuses_a_session_missing_from_its_folder(
    moto: ModuleType, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
):
    monkeypatch.setattr(moto, "CLAUDE_HOME", tmp_path / "claude")
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task(snoozed=SNOOZE)
    with pytest.raises(moto.MotoError, match="Session s1 is not in"):
        moto.cmd_wake(argparse.Namespace(agent="abc-1", text=[]))


def test_unpushed_branch_without_a_worktree_blocks_removal(
    moto: ModuleType, pushed_clone: Path
):
    git(pushed_clone, "branch", "parked")
    assert moto.unsaved_work(str(pushed_clone), "parked") is None
    git(pushed_clone, "switch", "-q", "parked")
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
    git(pushed_clone, "switch", "-q", "-")
    real_run = moto.run

    def run(args: list[str], **kwargs: Any) -> str:
        if args[0] == "gh":
            raise moto.MotoError("no PR")
        return real_run(args, **kwargs)

    with patch.object(moto, "run", run):
        assert (
            moto.unsaved_work(str(pushed_clone), "parked")
            == "1 commit is on no remote and in no merged PR"
        )


def events(moto: ModuleType) -> list[dict[str, Any]]:
    path = moto.state_dir() / "events.jsonl"
    return [json.loads(line) for line in path.read_text().splitlines()]


def test_first_write_snapshots_the_existing_tasks(moto: ModuleType):
    path = moto.state_dir() / "tasks.json"
    path.parent.mkdir(parents=True)
    path.write_text(json.dumps({"tasks": {"abc-1": task()}}))
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"]["held"] = True
        moto.record("hold", "abc-1")
    first, hold = events(moto)
    assert (first["v"], first["event"], first["agent"]) == (1, "snapshot", "abc-1")
    assert "held" not in first["task"]
    assert hold["event"] == "hold"
    with moto.tasks_for_update():
        moto.record("resume", "abc-1")
    assert [e["event"] for e in events(moto)] == ["snapshot", "hold", "resume"]


def test_failed_update_logs_nothing(moto: ModuleType):
    with pytest.raises(moto.MotoError):
        with moto.tasks_for_update():
            moto.record("hold", "abc-1")
            raise moto.MotoError("boom")
    with moto.tasks_for_update():
        pass
    assert not (moto.state_dir() / "events.jsonl").exists()


def test_report_logs_its_text_and_a_new_pr_once(moto: ModuleType):
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task()
    args = argparse.Namespace(
        kind="done", text=["PR", "https://github.com/o/r/pull/7"], agent="abc-1"
    )
    assert moto.cmd_report(args) == 0
    assert moto.cmd_report(args) == 0
    logged = [(e["event"], e.get("text") or e.get("pr")) for e in events(moto)]
    assert logged[1:] == [
        ("report", "PR https://github.com/o/r/pull/7"),
        ("pr", "https://github.com/o/r/pull/7"),
        ("report", "PR https://github.com/o/r/pull/7"),
    ]


def test_drop_keeps_the_whole_task_in_the_log(moto: ModuleType):
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task(pr="https://github.com/o/r/pull/7")
    assert moto.cmd_drop(argparse.Namespace(agent="abc-1")) == 0
    assert moto.read_tasks() == {}
    drop = events(moto)[-1]
    assert drop["event"] == "drop"
    assert drop["task"] == task(pr="https://github.com/o/r/pull/7")


def absorbed(moto: ModuleType) -> list[str]:
    return [e["reason"] for e in moto.pending_events if e["event"] == "absorb"]


def test_turn_answering_the_user_is_absorbed_and_logged(moto: ModuleType):
    tasks = {"abc-1": task()}
    turn_in(moto, "t1", "what does this do?")
    assert moto.check(tasks, live("done", 2), 0) == []
    assert absorbed(moto) == ["the user is talking to the worker"]
    assert "pending" not in tasks["abc-1"]["seen"]


def test_turn_answering_the_driver_without_a_report_wakes(moto: ModuleType):
    tasks = {"abc-1": task(told=50.0)}
    turn_in(moto, "t1", "[driver] fix it")
    assert moto.check(tasks, live("done", 2), 0) == [
        "abc-1: turn ended without a report"
    ]


def test_herdr_announcing_a_handled_turn_again_is_absorbed(moto: ModuleType):
    tasks = {"abc-1": task()}
    turn_in(moto, "t1", "[driver] fix it")
    assert moto.check(tasks, live("done", 2), 0) == [
        "abc-1: turn ended without a report"
    ]
    # Reading the pane bumped Herdr's state, but the transcript has no new turn.
    assert moto.check(tasks, live("done", 3), 100) == []
    assert moto.check(tasks, live("done", 3), 100 + moto.TURN_SETTLE_SECONDS) == []
    assert absorbed(moto) == ["Herdr announced a turn the watch already handled"]
    turn_in(moto, "t2", "[driver] fix it")
    assert moto.check(tasks, live("done", 4), 200) == [
        "abc-1: turn ended without a report"
    ]


def test_turn_end_after_a_report_to_the_driver_is_absorbed(moto: ModuleType):
    report = {"kind": "question", "text": "Which base?", "at": 100.0}
    tasks = {"abc-1": task(report=report, told=50.0)}
    turn_in(moto, "t1", "[driver] fix it")
    settled = 100 + moto.REPORT_SETTLE_SECONDS
    assert moto.check(tasks, live("working", 1), settled) == [
        "abc-1 question: Which base?"
    ]
    assert moto.check(tasks, live("done", 2), settled + 5) == []
    assert absorbed(moto) == ["it reported since the driver last wrote to it"]


def test_background_work_defers_the_turn_end_until_it_stops(moto: ModuleType):
    tasks = {"abc-1": task(told=0.0)}
    turn_in(moto, "t1", "[driver] fix it")
    footer_says(moto, "1 shell")
    assert moto.check(tasks, live("done", 2), 0) == []
    assert moto.check(tasks, live("done", 2), 60) == []
    assert absorbed(moto) == ["1 shell still running"]
    footer_says(moto, None)
    # The next turn may be about to start, so the watch waits a moment.
    assert moto.check(tasks, live("done", 2), 61) == []
    late = 60 + moto.TURN_SETTLE_SECONDS
    assert moto.check(tasks, live("done", 2), late) == [
        "abc-1: turn ended without a report"
    ]


def test_new_turn_after_background_work_is_judged_afresh(moto: ModuleType):
    tasks = {"abc-1": task(told=0.0)}
    turn_in(moto, "t1", "[driver] fix it")
    footer_says(moto, "1 shell")
    assert moto.check(tasks, live("done", 2), 0) == []
    assert moto.check(tasks, live("working", 3), 90) == []
    footer_says(moto, None)
    turn_in(moto, "t2", "[driver] fix it")
    assert moto.check(tasks, live("done", 4), 95) == [
        "abc-1: turn ended without a report"
    ]


def test_long_background_work_wakes_the_driver(moto: ModuleType):
    tasks = {"abc-1": task(told=0.0)}
    footer_says(moto, "1 shell")
    assert moto.check(tasks, live("done", 2), 0) == []
    assert moto.check(tasks, live("done", 2), moto.BUSY_LIMIT) == [
        "abc-1: turn ended without a report; 1 shell still running after 15m"
    ]


def screen_shows(screen: str) -> Any:
    def run(*_args: Any, **_kwargs: Any) -> str:
        return screen

    return run


def test_footer_counts_background_work(monkeypatch: pytest.MonkeyPatch):
    real = load_moto()
    footer = (
        "\n  Opus │ main\n  ⏵⏵ auto mode on · 1 shell · 2 monitors · ← for agents\n"
    )
    monkeypatch.setattr(real, "run", screen_shows(footer))
    assert real.background_work("w1:p1") == "1 shell and 2 monitors"
    monkeypatch.setattr(real, "run", screen_shows("  ⏵⏵ auto mode on · ← for agents"))
    assert real.background_work("w1:p1") is None


def test_transcript_gives_the_last_reply_and_prompt(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
):
    real = load_moto()
    monkeypatch.setattr(real, "CLAUDE_HOME", tmp_path / "claude")
    directory = real.session_dir("/code/widgets-ABC-1-fix")
    directory.mkdir(parents=True)
    entries = [
        {"type": "custom-title", "customTitle": "ABC-1 fix"},
        {"type": "user", "promptSource": "typed", "message": {"content": "hi"}},
        {
            "type": "user",
            "promptSource": "typed",
            "message": {"content": '\n<pasted_content id="1a">\n[driver] fix it'},
        },
        {"type": "assistant", "uuid": "a1"},
        {
            "type": "user",
            "promptSource": "system",
            "message": {"content": "<task-notification>"},
        },
        {"type": "assistant", "uuid": "a2"},
        {"type": "assistant", "uuid": "side", "isSidechain": True},
        {"type": "system", "subtype": "away_summary", "uuid": "s1"},
    ]
    (directory / "s.jsonl").write_text("".join(json.dumps(e) + "\n" for e in entries))
    assert real.last_turn(task(title="ABC-1 fix"), None) == ("a2", "[driver] fix it")
    assert real.last_turn(task(title="other"), None) == (None, None)


def test_task_a_worker_started_is_left_to_that_worker(moto: ModuleType):
    details = {
        "agent": "abc-2",
        "repo": "/code/widgets",
        "cwd": "/code/widgets",
        "pane_id": "w2:p1",
        "tab_id": "w2:t1",
        "workspace_id": "w2",
    }
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task()
    args = argparse.Namespace(
        repo="widgets", worktree=None, base=None, name=None, title="t", resume=None
    )
    with (
        patch.dict("os.environ", {"HERDR_PANE_ID": "w1:p1"}),
        patch("sys.stdin.read", return_value="Test it."),
        patch.object(moto, "run", return_value=json.dumps(details)) as run,
    ):
        assert moto.cmd_spawn(args) == 0
    brief = run.call_args.kwargs["stdin"]
    assert brief.startswith("[abc-1] Test it.\n\nAnother worker, abc-1, started you")
    assert "follow the user first, then the driver, then abc-1" in brief
    tasks = moto.read_tasks()
    assert tasks["abc-2"]["parent"] == "abc-1"
    assert moto.check({"abc-2": tasks["abc-2"]}, {}, 0) == []


def stop(moto: ModuleType, active: bool = False) -> dict[str, Any]:
    """What the hook prints, or {} when it lets the turn end silently."""
    return moto.stop_hook({"session_id": "s1", "stop_hook_active": active}) or {}


def test_stop_hook_ignores_a_driver_with_nothing_to_watch(moto: ModuleType):
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task(held=True)
    assert stop(moto) == {}


def no_sleep(_seconds: float) -> None:
    pass


def test_stop_hook_blocks_until_a_watch_runs_then_gives_up(
    moto: ModuleType, monkeypatch: pytest.MonkeyPatch
):
    monkeypatch.setattr(moto.time, "sleep", no_sleep)
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task()
    first = stop(moto)
    assert first["decision"] == "block"
    assert "no moto watch is running" in first["reason"]
    assert "run_in_background" in first["reason"]
    for _ in range(moto.STOP_BLOCK_BUDGET - 1):
        assert stop(moto, active=True)["decision"] == "block"
    gave_up = stop(moto, active=True)
    assert "decision" not in gave_up
    assert "nothing watches abc-1" in gave_up["systemMessage"]
    # A new prompt starts the count again.
    assert stop(moto)["decision"] == "block"


def test_stop_hook_lets_the_turn_end_while_a_watch_beats(moto: ModuleType):
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task()
    moto.beat_path().write_text(f"{os.getpid()}\n")
    with patch.object(moto, "run", return_value="python3 /bin/moto watch"):
        assert stop(moto) == {}


def test_stop_hook_names_a_watch_that_stopped_polling(moto: ModuleType):
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task()
    beat = moto.beat_path()
    beat.write_text(f"{os.getpid()}\n")
    old = moto.time.time() - moto.BEAT_STALE_SECONDS - 5
    os.utime(beat, (old, old))
    with patch.object(moto, "run", return_value="python3 /bin/moto watch"):
        reason = stop(moto)["reason"]
    assert f"kill {os.getpid()} first" in reason


def test_stop_hook_fails_open(moto: ModuleType, capsys: pytest.CaptureFixture[str]):
    with patch.object(moto, "stop_hook", side_effect=RuntimeError("boom")):
        with patch("sys.stdin.read", return_value="{}"):
            assert moto.cmd_stop_hook(argparse.Namespace()) == 0
    out = json.loads(capsys.readouterr().out)
    assert "decision" not in out and "boom" in out["systemMessage"]


def test_stop_hook_counts_a_watch_from_before_heartbeats(moto: ModuleType):
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task()
    with moto.single_watcher() as alone:
        assert alone
        assert stop(moto) == {}


def afk(moto: ModuleType, *words: str) -> None:
    assert moto.cmd_afk(argparse.Namespace(text=list(words))) == 0


def test_afk_keeps_the_note_word_for_word_and_logs_replacements(moto: ModuleType):
    afk(moto, "merge #194 if green; otherwise wait")
    first = moto.read_afk()
    afk(moto)  # no words while away changes nothing
    assert moto.read_afk() == first
    afk(moto, "just watch")
    assert moto.read_afk() == {"since": first["since"], "note": "just watch"}
    logged = [(e["note"], e["previous"]) for e in events(moto) if e["event"] == "afk"]
    assert logged == [
        ("merge #194 if green; otherwise wait", None),
        ("just watch", "merge #194 if green; otherwise wait"),
    ]


def test_afk_without_words_is_an_entry_without_instructions(
    moto: ModuleType, capsys: pytest.CaptureFixture[str]
):
    afk(moto)
    assert moto.read_afk()["note"] == ""
    assert "no instructions" in capsys.readouterr().out


def report(moto: ModuleType, agent: str, kind: str, text: str) -> None:
    moto.cmd_report(argparse.Namespace(kind=kind, text=[text], agent=agent))


def test_back_prints_what_happened_while_away(
    moto: ModuleType, capsys: pytest.CaptureFixture[str]
):
    with moto.tasks_for_update() as tasks:
        for n in (1, 2, 3):
            tasks[f"abc-{n}"] = task(pane_id=f"w{n}:p1", agent=f"abc-{n}")
    report(moto, "abc-1", "question", "before afk")
    afk(moto, "merge green PRs")
    report(moto, "abc-1", "done", "https://github.com/o/r/pull/7")
    report(moto, "abc-2", "question", "Which base?")
    report(moto, "abc-3", "blocked", "no creds")
    with patch.object(moto, "herdr"):
        moto.cmd_tell(argparse.Namespace(agent="abc-3", text=["use the vault"]))
    moto.cmd_log_action(
        argparse.Namespace(text=["per the note: merged #7"], agent="abc-1")
    )
    with moto.tasks_for_update():
        moto.record("close", "abc-9", force=False, task={})
    capsys.readouterr()
    assert moto.cmd_back(argparse.Namespace()) == 0
    out = capsys.readouterr().out
    assert moto.read_afk() is None
    head, prs, questions, actions, finished = out.strip().split("\n\n")
    assert head.startswith("Away ") and head.endswith("Note: merge green PRs")
    assert "abc-1: https://github.com/o/r/pull/7" in prs
    assert "abc-2 question: Which base?" in questions
    assert "no creds" not in questions  # the driver answered it
    assert "before afk" not in out
    assert "abc-1: per the note: merged #7" in actions
    assert "abc-1 done: https://github.com/o/r/pull/7" in finished
    assert "abc-9: closed" in finished
    assert [e["event"] for e in events(moto)][-1] == "back"


def test_back_refuses_when_not_away(moto: ModuleType):
    with pytest.raises(moto.MotoError, match="Not away"):
        moto.cmd_back(argparse.Namespace())


def test_list_shows_the_away_note(moto: ModuleType, capsys: pytest.CaptureFixture[str]):
    afk(moto, "back at 5")
    capsys.readouterr()
    with patch.object(moto, "live_agents", return_value={}):
        assert moto.cmd_list(argparse.Namespace(json=False)) == 0
    out = capsys.readouterr().out
    assert "The user is away since" in out and "Note: back at 5" in out


def watch_output(
    moto: ModuleType, capsys: pytest.CaptureFixture[str], status: str = "working"
) -> str:
    with patch.object(moto, "live_agents", return_value=live(status, 1)):
        assert moto.cmd_watch(argparse.Namespace(max=0)) == 0
    return capsys.readouterr().out


def test_watch_with_no_news_ends_before_claude_stops_it(
    moto: ModuleType, capsys: pytest.CaptureFixture[str]
):
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task()
    assert watch_output(moto, capsys) == "No news in 0s. Start moto watch again.\n"
    assert float(moto.ended_path().read_text()) <= moto.time.time()


def done(at: float = 100, **fields: Any) -> dict[str, Any]:
    report = {"kind": "done", "text": "PR ready", "at": at}
    return task(report=report, seen={"status": "done", "report_at": at}, **fields)


def test_watch_says_when_every_task_has_reported_done(
    moto: ModuleType, capsys: pytest.CaptureFixture[str]
):
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task(report={"kind": "done", "text": "PR ready", "at": 100})
    out = watch_output(moto, capsys, status="done")
    assert out == f"abc-1 done: PR ready\n{moto.QUIET}\n"
    assert watch_output(moto, capsys, status="done") == f"No news in 0s. {moto.QUIET}\n"


def test_stop_hook_needs_no_watch_for_settled_tasks(
    moto: ModuleType, monkeypatch: pytest.MonkeyPatch
):
    monkeypatch.setattr(moto.time, "sleep", no_sleep)
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = done()
        tasks["abc-2"] = done(agent="abc-2", pane_id="w1:p2", told=50)
    assert stop(moto) == {}
    # A message to a done worker makes its next turn the driver's business.
    with moto.tasks_for_update() as tasks:
        tasks["abc-2"]["told"] = 150
    assert "abc-2 needs watching" in stop(moto)["reason"]
    # So does a done report the driver has not seen yet.
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"]["seen"] = {"status": "working"}
        tasks["abc-2"]["told"] = 50
    assert "abc-1 needs watching" in stop(moto)["reason"]


def queue(operation: str, at: float, task_id: str = "b1") -> dict[str, Any]:
    """A queue line as Claude writes it to the driver's transcript."""
    stamp = datetime.fromtimestamp(at, UTC).isoformat().replace("+00:00", "Z")
    entry: dict[str, Any] = {
        "type": "queue-operation",
        "operation": operation,
        "timestamp": stamp,
    }
    if operation != "dequeue":
        entry["content"] = (
            f"<task-notification>\n<task-id>{task_id}</task-id>\n"
            + "<status>completed</status>\n</task-notification>"
        )
    return entry


def test_stop_hook_waits_for_the_watch_s_queued_notification(
    moto: ModuleType, monkeypatch: pytest.MonkeyPatch, tmp_path: Path
):
    monkeypatch.setattr(moto.time, "sleep", no_sleep)
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task()
    ended = moto.time.time() - 2
    moto.ended_path().write_text(f"{ended}\n")
    transcript = tmp_path / "driver.jsonl"

    def stop_with(*entries: dict[str, Any]) -> dict[str, Any]:
        lines = [json.dumps({"type": "assistant", "uuid": "a1"})]
        transcript.write_text("\n".join(lines + [json.dumps(e) for e in entries]))
        payload = {"session_id": "s1", "transcript_path": str(transcript)}
        return moto.stop_hook(payload) or {}

    # The watch ended during the turn's last reply: its notification starts the next turn.
    assert stop_with(queue("enqueue", ended + 0.5)) == {}
    # Delivered, as the next turn or mid-turn, and still no watch: block.
    delivered = stop_with(queue("enqueue", ended + 0.5), queue("dequeue", ended + 3))
    assert delivered["decision"] == "block"
    absorbed = stop_with(queue("enqueue", ended + 0.5), queue("remove", ended + 1))
    assert absorbed["decision"] == "block"
    # A queued notification from before the watch ended is about something else.
    assert stop_with(queue("enqueue", ended - 60))["decision"] == "block"
    # With no transcript to read, the hook asks for a watch as before.
    payload = {"session_id": "s1", "transcript_path": str(tmp_path / "missing")}
    assert (moto.stop_hook(payload) or {})["decision"] == "block"


def test_watch_stopped_by_claude_records_its_end(state_home: Path, tmp_path: Path):
    herdr = tmp_path / "herdr"
    herdr.write_text(
        "#!/bin/sh\necho '"
        + json.dumps({"result": {"agents": [live("working", 1)["w1:p1"]]}})
        + "'\n"
    )
    herdr.chmod(0o755)
    (state_home / "moto").mkdir(parents=True)
    (state_home / "moto/tasks.json").write_text(
        json.dumps({"tasks": {"abc-1": task()}})
    )
    env = {**os.environ, "HERDR_BIN_PATH": str(herdr), "PATH": "/usr/bin:/bin"}
    watch = subprocess.Popen([sys.executable, str(ROOT / "bin/moto"), "watch"], env=env)
    beat = state_home / "moto/watch.beat"
    for _ in range(100):
        if beat.exists():
            break
        time.sleep(0.05)
    watch.send_signal(signal.SIGTERM)
    assert watch.wait(5) == 128 + signal.SIGTERM
    assert (state_home / "moto/watch.ended").exists()
    assert not beat.exists()
