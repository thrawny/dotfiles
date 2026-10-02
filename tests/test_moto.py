"""Task records, wake rules, reports and cleanup checks. No live Herdr or GitHub."""

import argparse
import importlib.util
import json
import os
import subprocess
from importlib.machinery import SourceFileLoader
from pathlib import Path
from types import ModuleType
from typing import Any
from unittest.mock import patch

import pytest

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def moto() -> ModuleType:
    loader = SourceFileLoader("moto", str(ROOT / "bin/moto"))
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
        assert moto.cmd_watch(argparse.Namespace(timeout=5)) == 0
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
        assert moto.cmd_watch(argparse.Namespace(timeout=5)) == 0
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
