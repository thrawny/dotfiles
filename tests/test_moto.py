"""Task records, wake rules, reports and cleanup checks. No live Herdr or GitHub."""

import argparse
import importlib.util
import json
import os
import subprocess
from datetime import UTC, datetime
from importlib.machinery import SourceFileLoader
from pathlib import Path
from types import ModuleType
from typing import Any
from unittest.mock import MagicMock, patch

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
    setattr(module, "pr_updated", no_pr_update)
    return module


def no_pr_update(_url: str) -> None:
    return None


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
    grace = moto.PANE_GONE_GRACE
    assert moto.check(tasks, {}, 10) == []
    assert moto.check(tasks, {}, 10 + grace) == ["abc-1: pane closed"]
    assert moto.check(tasks, {}, 20 + grace) == []
    assert tasks["abc-1"]["closed_at"] == 10


def test_held_task_s_closed_pane_wakes_once_and_nothing_else(moto: ModuleType):
    report = {"kind": "question", "text": "Which base?", "at": 100.0}
    grace = moto.PANE_GONE_GRACE
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task(held=True, report=report)
        assert moto.check(tasks, live("done", 2), 200) == []
        assert moto.check(tasks, {}, 300) == []
        assert moto.check(tasks, {}, 300 + grace) == ["abc-1: pane closed"]
        assert moto.check(tasks, {}, 400 + grace) == []
    assert moto.read_tasks()["abc-1"]["closed_at"] == 300
    assert events(moto)[-1] | {"ts": 0} == {
        "v": 1,
        "ts": 0,
        "event": "pane_closed",
        "agent": "abc-1",
        "pane_id": "w1:p1",
        "at": 300,
    }


def test_pane_back_within_the_grace_period_is_not_news(moto: ModuleType):
    tasks = {"abc-1": task(held=True), "abc-2": task(pane_id="w2:p1")}
    grace = moto.PANE_GONE_GRACE
    assert moto.check(tasks, {}, 0) == []
    both = live("done", 2) | live("working", 1, "w2:p1")
    assert moto.check(tasks, both, grace - 1) == []
    assert moto.check(tasks, {}, grace) == []
    assert "closed_at" not in tasks["abc-1"]


def test_closed_mark_clears_when_the_pane_comes_back(moto: ModuleType):
    tasks = {"abc-1": task(held=True)}
    grace = moto.PANE_GONE_GRACE
    moto.check(tasks, {}, 0)
    assert moto.check(tasks, {}, grace) == ["abc-1: pane closed"]
    assert moto.check(tasks, live("idle", 2), grace + 1) == []
    assert "closed_at" not in tasks["abc-1"]
    moto.check(tasks, {}, grace + 2)
    assert moto.check(tasks, {}, 2 * grace + 2) == ["abc-1: pane closed"]


def test_closed_pane_of_a_snooze_is_not_news(moto: ModuleType):
    tasks = {"abc-2": task(pane_id="w2:p1", snoozed=SNOOZE)}
    moto.check(tasks, {}, 0)
    assert moto.check(tasks, {}, moto.PANE_GONE_GRACE) == []


def test_closed_pane_of_a_child_task_is_news_once(moto: ModuleType):
    tasks = {"abc-1": task(parent="abc-9")}
    grace = moto.PANE_GONE_GRACE
    assert moto.check(tasks, {}, 100) == []
    closed = ["abc-1 (child of abc-9): pane closed"]
    assert moto.check(tasks, {}, 100 + grace) == closed
    assert moto.check(tasks, {}, 200 + grace) == []


@pytest.mark.parametrize("kind", ["wrap", "snooze", "handback"])
def test_child_wrap_snooze_and_handback_reach_the_driver_once(
    moto: ModuleType, capsys: pytest.CaptureFixture[str], kind: str
):
    with moto.tasks_for_update() as tasks:
        tasks["abc-2"] = task(pane_id="w2:p1", agent="abc-2", parent="abc-1")
    args = argparse.Namespace(kind=kind, text=["All", "set"], agent=None)
    with patch.dict("os.environ", {"HERDR_PANE_ID": "w2:p1"}):
        assert moto.cmd_report(args) == 0
    out = capsys.readouterr().out
    assert f"Reported {kind} to the driver" in out
    assert "not watching" not in out
    tasks = moto.read_tasks()
    now = moto.time.time()
    news = [f"abc-2 {kind} (child of abc-1): All set"]
    assert moto.check(tasks, live("working", 2, "w2:p1"), now) == news
    assert moto.check(tasks, live("done", 3, "w2:p1"), now) == []


@pytest.mark.parametrize("kind", ["done", "question", "blocked"])
def test_child_done_question_and_blocked_stay_with_the_parent(
    moto: ModuleType, capsys: pytest.CaptureFixture[str], kind: str
):
    with moto.tasks_for_update() as tasks:
        tasks["abc-2"] = task(pane_id="w2:p1", agent="abc-2", parent="abc-1")
    args = argparse.Namespace(kind=kind, text=["x"], agent=None)
    with patch.dict("os.environ", {"HERDR_PANE_ID": "w2:p1"}):
        assert moto.cmd_report(args) == 0
    assert "the driver is not watching you" in capsys.readouterr().out
    tasks = moto.read_tasks()
    now = moto.time.time()
    assert moto.check(tasks, live("done", 2, "w2:p1"), now) == []
    assert moto.check(tasks, live("blocked", 3, "w2:p1"), now) == []


def test_held_child_handing_back_reaches_the_driver(moto: ModuleType):
    with moto.tasks_for_update() as tasks:
        tasks["abc-2"] = task(pane_id="w2:p1", agent="abc-2", parent="abc-1", held=True)
    args = argparse.Namespace(kind="handback", text=["Over", "to", "you"], agent=None)
    with patch.dict("os.environ", {"HERDR_PANE_ID": "w2:p1"}):
        assert moto.cmd_report(args) == 0
    tasks = moto.read_tasks()
    assert moto.check(tasks, live("done", 2, "w2:p1"), moto.time.time()) == [
        "abc-2 handback (child of abc-1): Over to you"
    ]


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


@pytest.mark.parametrize("kind", ["handback", "snooze"])
def test_handback_and_snooze_end_the_hold_and_wake_the_driver(
    moto: ModuleType, capsys: pytest.CaptureFixture[str], kind: str
):
    old = {"kind": "question", "text": "Which base?", "at": 100.0}
    seen = {"status": "working", "seq": 1, "pending": {"since": 90.0}}
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task(held=True, report=old, seen=seen)
    args = argparse.Namespace(kind=kind, text=["Ship", "it"], agent=None)
    with patch.dict("os.environ", {"HERDR_PANE_ID": "w1:p1"}):
        assert moto.cmd_report(args) == 0
    assert "moto watch covers this task again" in capsys.readouterr().out
    tasks = moto.read_tasks()
    assert tasks["abc-1"]["held"] is False
    now = moto.time.time()
    assert moto.check(tasks, live("done", 5), now) == [f"abc-1 {kind}: Ship it"]
    assert [(e["event"], e.get("by")) for e in events(moto)][-2:] == [
        ("resume", kind),
        ("report", None),
    ]


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


def close(
    moto: ModuleType,
    status: str,
    turns: list[float],
    force: bool = False,
    **fields: Any,
) -> tuple[MagicMock, MagicMock]:
    """Run moto close on a main-checkout task, which skips the unsaved-work check."""
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task(branch=None, started=500.0, **fields)
    with (
        patch.object(moto, "live_agents", return_value=live(status, 1)),
        patch.object(moto.time, "time", return_value=1015.0),
        patch.object(moto, "user_turns", return_value=turns) as user_turns,
        patch.object(moto, "herdr") as herdr,
    ):
        moto.cmd_close(argparse.Namespace(agent="abc-1", force=force))
    return herdr, user_turns


DONE = {"kind": "done", "text": "Fixed.", "at": 900.0}


@pytest.mark.parametrize("status", ["working", "blocked"])
def test_close_refuses_a_busy_worker(moto: ModuleType, status: str):
    with pytest.raises(moto.MotoError, match=f"^abc-1 is {status}; wait for it"):
        close(moto, status, [], report=DONE)
    assert "abc-1" in moto.read_tasks()


def test_close_refuses_a_worker_the_user_typed_to_since_its_report(
    moto: ModuleType,
):
    with pytest.raises(moto.MotoError) as error:
        close(moto, "idle", [950.0, 1000.0], report=DONE)
    assert str(error.value).startswith(
        "the user typed in abc-1's pane 2 times since its last report, last 15s ago;"
    )
    assert "abc-1" in moto.read_tasks()


def test_close_without_a_report_counts_the_user_s_prompts_since_the_start(
    moto: ModuleType,
):
    with pytest.raises(moto.MotoError, match="1 time since it started"):
        close(moto, "done", [1000.0])
    herdr, user_turns = close(moto, "done", [])
    user_turns.assert_called_once()
    assert user_turns.call_args.args[2] == 500.0
    herdr.assert_called_once_with("tab", "close", "w1:t1")


@pytest.mark.parametrize("kind", ["wrap", "snooze"])
def test_close_lets_a_worker_the_user_ended_finish_its_turn(
    moto: ModuleType, kind: str
):
    wrap = {**DONE, "kind": kind}
    herdr, _ = close(moto, "working", [], report=wrap)
    herdr.assert_called_once_with("tab", "close", "w1:t1")
    assert "abc-1" not in moto.read_tasks()
    # A prompt after the report still means the user changed their mind.
    with pytest.raises(moto.MotoError, match="since its last report"):
        close(moto, "working", [1000.0], report=wrap)


def test_close_counts_a_pane_closed_after_the_last_prompt_as_done(
    moto: ModuleType,
):
    herdr, _ = close(moto, "gone", [950.0, 1000.0], report=DONE, closed_at=1005.0)
    herdr.assert_called_once_with("tab", "close", "w1:t1")
    assert "abc-1" not in moto.read_tasks()
    # A prompt after the pane closed came from a session resumed elsewhere.
    with pytest.raises(moto.MotoError, match="2 times since its last report"):
        close(moto, "gone", [950.0, 1010.0], report=DONE, closed_at=1005.0)


def test_close_ignores_the_pane_of_a_snoozed_task(moto: ModuleType):
    herdr, _ = close(moto, "working", [], report=DONE, snoozed=SNOOZE)
    herdr.assert_called_once_with("tab", "close", "w1:t1")


def test_forced_close_skips_the_busy_checks(moto: ModuleType):
    herdr, user_turns = close(moto, "working", [1000.0], force=True, report=DONE)
    user_turns.assert_not_called()
    herdr.assert_called_once_with("tab", "close", "w1:t1")


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


@pytest.fixture
def worktree(pushed_clone: Path) -> Path:
    """A pushed linked worktree of pushed_clone, on ABC-7-fix."""
    path = pushed_clone.parent / "clone-ABC-7-fix"
    git(pushed_clone, "worktree", "add", "-q", "-b", "ABC-7-fix", str(path))
    git(path, "push", "-q", "-u", "origin", "ABC-7-fix")
    return path


@pytest.fixture
def claude_home(moto: ModuleType, tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(moto, "CLAUDE_HOME", tmp_path / "claude")


def report_from(
    moto: ModuleType,
    kind: str,
    cwd: Path,
    pane_id: str = "w4:p2",
    session: str | None = "s7",
    **fields: Any,
) -> MagicMock:
    """Run moto report in a Claude session the user started in cwd."""
    agent = claude_in(
        pane_id,
        "working",
        cwd=str(cwd),
        terminal_title_stripped="Widgets research notes",
        **fields,
    )
    env = {"HERDR_PANE_ID": pane_id} | (
        {"CLAUDE_CODE_SESSION_ID": session} if session else {}
    )
    args = argparse.Namespace(kind=kind, text=["All", "done."], agent=None)
    with (
        patch.dict("os.environ", env),
        patch.object(moto, "live_agents", return_value={pane_id: agent}),
        patch.object(moto, "herdr") as herdr,
    ):
        assert moto.cmd_report(args) == 0
    return herdr


def panes_in(*panes: tuple[str, Path]) -> Any:
    """A herdr stand-in whose pane list holds these (tab, cwd) panes."""
    listing = {"panes": [{"tab_id": tab, "cwd": str(cwd)} for tab, cwd in panes]}

    def herdr(*args: str, **_: Any) -> dict[str, Any]:
        return listing if args == ("pane", "list") else {}

    return MagicMock(side_effect=herdr)


def close_adopted(moto: ModuleType, name: str, herdr: MagicMock) -> None:
    with (
        patch.object(moto, "live_agents", return_value=live("idle", 1, "w4:p2")),
        patch.object(moto, "user_turns", return_value=[]),
        patch.object(moto, "herdr", herdr),
    ):
        moto.cmd_close(argparse.Namespace(agent=name, force=False))


def branch_exists(repo: Path, branch: str) -> bool:
    found = subprocess.run(
        ["git", "-C", str(repo), "show-ref", "--quiet", f"refs/heads/{branch}"]
    )
    return found.returncode == 0


@pytest.mark.usefixtures("claude_home")
def test_wrap_from_a_session_the_user_started_adopts_it(
    moto: ModuleType,
    pushed_clone: Path,
    worktree: Path,
    capsys: pytest.CaptureFixture[str],
):
    herdr = report_from(moto, "wrap", worktree)
    herdr.assert_called_once_with("agent", "rename", "w4:p2", "abc-7")
    out = capsys.readouterr().out
    assert "moto now tracks this session as abc-7" in out
    assert "Reported wrap to the driver." in out
    saved = moto.read_tasks()["abc-7"]
    assert (saved["repo"], saved["branch"], saved["cwd"]) == (
        str(pushed_clone),
        "ABC-7-fix",
        str(worktree),
    )
    assert (saved["tab_id"], saved["session"], saved["adopted"]) == (
        "w4:t1",
        "s7",
        True,
    )
    assert [e["event"] for e in events(moto)] == ["adopt", "report"]
    # The driver hears of the wrap like any worker's.
    now = moto.time.time()
    assert moto.check(moto.read_tasks(), live("done", 10, "w4:p2"), now) == [
        "abc-7 wrap: All done."
    ]


@pytest.mark.usefixtures("claude_home")
def test_handback_from_an_adopted_session_tells_it_how_to_report(
    moto: ModuleType, pushed_clone: Path, capsys: pytest.CaptureFixture[str]
):
    report_from(moto, "handback", pushed_clone)
    assert "moto report done|question|blocked" in capsys.readouterr().out
    assert moto.read_tasks()["widgets-research-notes"]["report"]["kind"] == "handback"


@pytest.mark.usefixtures("claude_home")
def test_only_a_user_s_own_session_ending_its_work_is_adopted(
    moto: ModuleType,
    pushed_clone: Path,
    capsys: pytest.CaptureFixture[str],
    monkeypatch: pytest.MonkeyPatch,
):
    untracked = [
        report_from(moto, "done", pushed_clone),
        report_from(moto, "question", pushed_clone),
        report_from(moto, "wrap", pushed_clone, session=None),
        report_from(moto, "wrap", pushed_clone, agent="codex"),
    ]
    moto.write_driver(pane_id="w4:p2")
    untracked.append(report_from(moto, "wrap", pushed_clone))
    moto.driver_path().unlink()
    monkeypatch.setattr(moto, "MOTO_HOME", pushed_clone)
    untracked.append(report_from(moto, "snooze", pushed_clone, pane_id="w4:p3"))
    for herdr in untracked:
        herdr.assert_not_called()
    assert capsys.readouterr().out.count("Tell the user directly") == len(untracked)
    assert moto.read_tasks() == {}


@pytest.mark.usefixtures("claude_home")
def test_a_session_a_task_owns_moves_its_task_instead_of_a_second_one(
    moto: ModuleType, pushed_clone: Path
):
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task(session="s7")
    report_from(moto, "wrap", pushed_clone)
    saved = moto.read_tasks()
    assert list(saved) == ["abc-1"]
    assert saved["abc-1"]["pane_id"] == "w4:p2"
    assert "adopted" not in saved["abc-1"]


def test_adopted_name_prefers_a_jira_key_and_stays_unique(moto: ModuleType):
    tasks: dict[str, Any] = {"abc-242": {}}
    agents = {"w1:p1": {"name": "widgets-and-gadgets"}}
    assert moto.adopted_name(tasks, agents, [None, "ABC-242-retry"]) == "abc-242-2"
    assert (
        moto.adopted_name(tasks, agents, [None, "Widgets and gadgets research"])
        == "widgets-and-gadgets-2"
    )
    assert moto.adopted_name({}, {}, ["", "42 things"]) == "session-42-things"


@pytest.mark.usefixtures("claude_home")
def test_closing_an_adopted_main_checkout_session_closes_only_its_tab(
    moto: ModuleType, pushed_clone: Path
):
    report_from(moto, "wrap", pushed_clone)
    assert moto.read_tasks()["widgets-research-notes"]["branch"] is None
    herdr = MagicMock()
    close_adopted(moto, "widgets-research-notes", herdr)
    herdr.assert_called_once_with("tab", "close", "w4:t1")
    assert pushed_clone.is_dir()
    assert moto.read_tasks() == {}


@pytest.mark.usefixtures("claude_home")
def test_closing_an_adopted_session_removes_a_worktree_of_its_own(
    moto: ModuleType, pushed_clone: Path, worktree: Path
):
    report_from(moto, "wrap", worktree)
    # Neovim beside it in its tab, and another session in the main checkout.
    herdr = panes_in(("w4:t1", worktree), ("w4:t1", worktree), ("w2:t1", pushed_clone))
    close_adopted(moto, "abc-7", herdr)
    herdr.assert_any_call("tab", "close", "w4:t1")
    assert not worktree.exists()
    assert not branch_exists(pushed_clone, "ABC-7-fix")


@pytest.mark.usefixtures("claude_home")
def test_closing_an_adopted_session_keeps_a_worktree_another_tab_uses(
    moto: ModuleType, pushed_clone: Path, worktree: Path
):
    report_from(moto, "wrap", worktree)
    (worktree / "web").mkdir()
    herdr = panes_in(("w4:t1", worktree), ("w4:t2", worktree / "web"))
    close_adopted(moto, "abc-7", herdr)
    assert [c.args for c in herdr.call_args_list] == [
        ("pane", "list"),
        ("tab", "close", "w4:t1"),
    ]
    assert worktree.is_dir()
    assert branch_exists(pushed_clone, "ABC-7-fix")


@pytest.mark.parametrize("shared", [True, False])
@pytest.mark.usefixtures("claude_home")
def test_snoozing_an_adopted_session_removes_only_a_worktree_of_its_own(
    moto: ModuleType, pushed_clone: Path, worktree: Path, shared: bool
):
    report_from(moto, "snooze", worktree)
    session_file(moto.session_dir(str(worktree)), "s7", mtime=100)
    others = [("w4:t2", worktree)] if shared else []
    herdr = panes_in(("w4:t1", worktree), *others)
    with (
        patch.object(moto, "live_agents", return_value=live("idle", 1, "w4:p2")),
        patch.object(moto, "herdr", herdr),
    ):
        moto.cmd_snooze(argparse.Namespace(agent="abc-7", reason=["review"]))
    herdr.assert_any_call("tab", "close", "w4:t1")
    snooze = moto.read_tasks()["abc-7"]["snoozed"]
    assert (snooze["worktree"], snooze["branch"]) == (not shared, "ABC-7-fix")
    assert worktree.is_dir() == shared
    assert branch_exists(pushed_clone, "ABC-7-fix")
    if not shared:
        return
    # Wake reopens the worktree it shared, not the main checkout.
    details = {
        "cwd": str(worktree),
        "pane_id": "w5:p1",
        "tab_id": "w5:t1",
        "workspace_id": "w5",
    }
    with (
        patch.object(moto, "run", return_value=json.dumps(details)) as run,
        patch.object(moto, "live_agents", return_value=live("idle", 3, "w5:p1")),
    ):
        moto.cmd_wake(argparse.Namespace(agent="abc-7", text=[]))
    assert run.call_args.args[0][:6] == [
        "spawn-session",
        "--json",
        "--repo",
        str(worktree),
        "--name",
        "abc-7",
    ]
    assert "--worktree" not in run.call_args.args[0]


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
    # The question goes; where the driver is stays, for a scheduled job to find.
    assert json.loads(path.read_text()) == {"pane_id": "w1:p9"}


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


def test_spawn_passes_the_model_on_and_wake_keeps_it(
    moto: ModuleType, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
):
    monkeypatch.setattr(moto, "CLAUDE_HOME", tmp_path / "claude")
    cwd = str(tmp_path / "widgets")
    os.mkdir(cwd)
    details = {
        "agent": "abc-1",
        "repo": cwd,
        "cwd": cwd,
        "pane_id": "w1:p1",
        "tab_id": "w1:t1",
        "workspace_id": "w1",
    }
    args = argparse.Namespace(
        repo="widgets", title="ABC-1 fix", model="sonnet", effort="low"
    )
    with (
        patch("sys.stdin.read", return_value="Fix it."),
        patch.object(moto, "run", return_value=json.dumps(details)) as run,
    ):
        assert moto.cmd_spawn(args) == 0
    assert run.call_args.args[0][-4:] == ["--model", "sonnet", "--effort", "low"]
    saved = moto.read_tasks()["abc-1"]
    assert (saved["model"], saved["effort"]) == ("sonnet", "low")

    session_file(moto.session_dir(cwd), "s1", "ABC-1 fix", mtime=100)
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"]["snoozed"] = {**SNOOZE, "cwd": cwd, "worktree": False}
    with (
        patch.object(moto, "run", return_value=json.dumps(details)) as run,
        patch.object(moto, "live_agents", return_value=live("working", 3, "w1:p1")),
    ):
        assert moto.cmd_wake(argparse.Namespace(agent="abc-1", text=[])) == 0
    assert run.call_args.args[0][-6:] == [
        "--resume",
        "s1",
        "--model",
        "sonnet",
        "--effort",
        "low",
    ]


def test_wake_refuses_a_session_missing_from_its_folder(
    moto: ModuleType, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
):
    monkeypatch.setattr(moto, "CLAUDE_HOME", tmp_path / "claude")
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task(snoozed=SNOOZE)
    with pytest.raises(moto.MotoError, match="Session s1 is not in"):
        moto.cmd_wake(argparse.Namespace(agent="abc-1", text=[]))


def claude_in(pane_id: str, status: str = "idle", **fields: Any) -> dict[str, Any]:
    workspace = pane_id.split(":")[0]
    return {
        "pane_id": pane_id,
        "agent": "claude",
        "agent_status": status,
        "state_change_seq": 9,
        "workspace_id": workspace,
        "tab_id": f"{workspace}:t1",
        **fields,
    }


def test_attach_moves_a_task_to_its_resumed_pane(moto: ModuleType):
    report = {"kind": "done", "text": "PR ready", "at": 100.0}
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task(
            held=True, report=report, seen={"status": "gone"}, closed_at=50.0
        )
    # The closed pane's process lingers in Herdr under the task's name.
    live = {
        "w1:p1": claude_in("w1:p1", name="abc-1"),
        "w1:p7": claude_in("w1:p7", "done"),
    }
    turn_in(moto, "t9", "what next?")
    with (
        patch.object(moto, "live_agents", return_value=live),
        patch.object(moto, "herdr") as herdr,
    ):
        assert (
            moto.cmd_attach(argparse.Namespace(agent="abc-1", pane="w1:p7", hook=False))
            == 0
        )
    assert [c.args for c in herdr.call_args_list] == [
        ("agent", "rename", "w1:p1", "--clear"),
        ("agent", "rename", "w1:p7", "abc-1"),
    ]
    saved = moto.read_tasks()["abc-1"]
    assert (saved["pane_id"], saved["tab_id"], saved["held"]) == (
        "w1:p7",
        "w1:t1",
        True,
    )
    assert saved["seen"] == {
        "status": "done",
        "seq": 9,
        "report_at": 100.0,
        "turn": "t9",
    }
    assert "closed_at" not in saved
    assert events(moto)[-1] | {"ts": 0} == {
        "v": 1,
        "ts": 0,
        "event": "attach",
        "agent": "abc-1",
        "pane_id": "w1:p7",
        "previous": "w1:p1",
    }
    # Once resumed, the old turn and the done status are not news to the watch.
    saved["held"] = False
    assert moto.check({"abc-1": saved}, {"w1:p7": live["w1:p7"]}, 1000) == []


def test_attach_refuses_a_pane_without_claude_or_owned_by_another_task(
    moto: ModuleType,
):
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task()
        tasks["abc-2"] = task(pane_id="w2:p1")
    live = {"w2:p1": claude_in("w2:p1"), "w3:p1": claude_in("w3:p1", agent="codex")}
    with (
        patch.object(moto, "live_agents", return_value=live),
        patch.object(moto, "herdr", side_effect=AssertionError("no rename")),
    ):
        for pane, error in (
            ("w2:p1", "belongs to abc-2"),
            ("w3:p1", "No live Claude agent"),
            ("w4:p1", "No live Claude agent"),
        ):
            args = argparse.Namespace(agent="abc-1", pane=pane, hook=False)
            with pytest.raises(moto.MotoError, match=error):
                moto.cmd_attach(args)
    assert moto.read_tasks()["abc-1"]["pane_id"] == "w1:p1"


def attach_hook(moto: ModuleType, pane_id: str | None, session: str) -> int:
    env = {"HERDR_PANE_ID": pane_id} if pane_id else {}
    stdin = json.dumps({"session_id": session, "source": "resume"})
    with (
        patch.dict("os.environ", env),
        patch("sys.stdin.read", return_value=stdin),
    ):
        return moto.cmd_attach(argparse.Namespace(agent=None, pane=None, hook=True))


def test_session_start_hook_records_the_session_and_follows_it_to_a_new_pane(
    moto: ModuleType, capsys: pytest.CaptureFixture[str]
):
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task()
    with patch.object(moto, "live_agents", side_effect=AssertionError("no poll")):
        assert attach_hook(moto, "w1:p1", "s1") == 0
    assert moto.read_tasks()["abc-1"]["session"] == "s1"
    with (
        patch.object(moto, "live_agents", return_value={"w1:p7": claude_in("w1:p7")}),
        patch.object(moto, "herdr") as herdr,
    ):
        assert attach_hook(moto, "w1:p7", "s1") == 0
    herdr.assert_called_once_with("agent", "rename", "w1:p7", "abc-1")
    assert moto.read_tasks()["abc-1"]["pane_id"] == "w1:p7"
    assert capsys.readouterr().out == ""


def test_session_start_hook_ignores_other_sessions_and_never_fails(
    moto: ModuleType, capsys: pytest.CaptureFixture[str]
):
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task(session="s1")
        tasks["abc-2"] = task(pane_id="w2:p1", session="s2", snoozed=SNOOZE)
    before = moto.read_tasks()
    with patch.object(moto, "live_agents", side_effect=AssertionError("no poll")):
        assert attach_hook(moto, "w9:p1", "s3") == 0  # the driver, say
        assert attach_hook(moto, None, "s1") == 0  # outside Herdr
        assert attach_hook(moto, "w9:p1", "s2") == 0  # wake handles a snoozed task
    with patch.object(moto, "live_agents", side_effect=moto.MotoError("no Herdr")):
        assert attach_hook(moto, "w9:p1", "s1") == 0
    assert moto.read_tasks() == before
    assert capsys.readouterr().out == ""


def test_report_records_the_worker_s_session(moto: ModuleType):
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task()
    args = argparse.Namespace(kind="done", text=["ok"], agent=None)
    env = {"HERDR_PANE_ID": "w1:p1", "CLAUDE_CODE_SESSION_ID": "s1"}
    with patch.dict("os.environ", env):
        assert moto.cmd_report(args) == 0
    assert moto.read_tasks()["abc-1"]["session"] == "s1"


def moto_main(moto: ModuleType, *argv: str) -> int:
    with patch("sys.argv", ["moto", *argv]):
        return moto.main()


def test_a_fork_runs_no_task_commands(
    moto: ModuleType, capsys: pytest.CaptureFixture[str]
):
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task(session="s1")
    before = moto.read_tasks()
    # A fork of abc-1, in a pane of its own.
    env = {"MOTO_FORK": "1", "HERDR_PANE_ID": "w1:p7", "CLAUDE_CODE_SESSION_ID": "s9"}
    with (
        patch.dict("os.environ", env),
        patch.object(moto, "herdr", side_effect=AssertionError("no Herdr")),
    ):
        for argv in (
            ["report", "done", "PR ready"],
            ["report", "done", "PR ready", "--agent", "abc-1"],
            ["report", "wrap", "all done"],
            ["tell", "abc-1", "go on"],
            ["watch"],
            ["ask", "which one?"],
            ["attach", "abc-1"],
            ["hold", "abc-1"],
        ):
            assert moto_main(moto, *argv) == 1
            err = capsys.readouterr().err
            assert f"cannot run moto {argv[0]}" in err
            assert "Answer the user in this pane" in err
        with patch.object(moto, "live_agents", return_value={}):
            assert moto_main(moto, "list") == 0
    assert "abc-1" in capsys.readouterr().out
    assert moto.read_tasks() == before
    assert moto.read_events() == []
    assert not (moto.state_dir() / "driver.json").exists()
    assert not (moto.state_dir() / "watch.lock").exists()


def test_session_start_hook_skips_a_fork(moto: ModuleType):
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task(session="s1")
    before = moto.read_tasks()
    with (
        patch.dict("os.environ", {"MOTO_FORK": "1"}),
        patch.object(moto, "live_agents", side_effect=AssertionError("no poll")),
    ):
        # Claude gives a fork its own session id, but even the worker's must not
        # move the task, nor a fork in the task's own pane replace its session.
        assert attach_hook(moto, "w1:p7", "s1") == 0
        assert attach_hook(moto, "w1:p1", "s9") == 0
    assert moto.read_tasks() == before


def test_transcript_is_the_recorded_session_not_a_fork_with_its_name(
    moto: ModuleType, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
):
    monkeypatch.setattr(moto, "CLAUDE_HOME", tmp_path / "claude")
    worker = task(title="ABC-1 fix")
    directory = moto.session_dir(worker["cwd"])
    session_file(directory, "s1", "ABC-1 fix", mtime=100)
    # A fork copies the worker's name into the same folder, and is newer.
    session_file(directory, "fork", "ABC-1 fix", mtime=200)
    assert moto.transcript(worker, None) == directory / "fork.jsonl"
    assert moto.transcript(worker | {"session": "s1"}, None) == directory / "s1.jsonl"
    # A recorded session with no transcript falls back to the name.
    assert moto.transcript(worker | {"session": "s0"}, None) == directory / "fork.jsonl"


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


def test_a_worker_hands_a_task_to_the_driver(
    moto: ModuleType, capsys: pytest.CaptureFixture[str]
):
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
        repo="widgets",
        worktree=None,
        base=None,
        name=None,
        title="t",
        resume=None,
        to_driver=True,
    )
    with (
        patch.dict("os.environ", {"HERDR_PANE_ID": "w1:p1"}),
        patch("sys.stdin.read", return_value="Build it."),
        patch.object(moto, "run", return_value=json.dumps(details)) as run,
    ):
        assert moto.cmd_spawn(args) == 0
    brief = run.call_args.kwargs["stdin"]
    assert brief.startswith("[driver] Build it.\n\nA driver session started you")
    assert "The driver watches abc-2" in capsys.readouterr().out
    tasks = moto.read_tasks()
    assert "parent" not in tasks["abc-2"]
    assert tasks["abc-2"]["requested_by"] == "abc-1"
    assert not moto.unwatched(tasks["abc-2"])
    spawned = [e for e in events(moto) if e["event"] == "spawn"]
    assert spawned[-1]["requested_by"] == "abc-1"
    with patch.dict("os.environ", {"HERDR_PANE_ID": "w1:p1"}):
        with pytest.raises(moto.MotoError, match="use moto report"):
            moto.message_sender(tasks, "abc-2", "hi")
    with patch.object(moto, "live_agents", return_value={}):
        assert moto.cmd_list(argparse.Namespace(json=False)) == 0
    assert "· requested by abc-1" in capsys.readouterr().out


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


def test_back_lists_a_wrap_as_finished_and_leaves_a_handback_to_the_driver(
    moto: ModuleType, capsys: pytest.CaptureFixture[str]
):
    with moto.tasks_for_update() as tasks:
        for n in (1, 2):
            tasks[f"abc-{n}"] = task(pane_id=f"w{n}:p1", agent=f"abc-{n}")
    afk(moto, "")
    report(moto, "abc-1", "wrap", "merged https://github.com/o/r/pull/8")
    report(moto, "abc-2", "handback", "ship it")
    capsys.readouterr()
    assert moto.cmd_back(argparse.Namespace()) == 0
    out = capsys.readouterr().out
    _, prs, _, _, finished = out.strip().split("\n\n")
    assert "abc-1: https://github.com/o/r/pull/8" in prs
    assert "abc-1 wrap: merged https://github.com/o/r/pull/8" in finished
    assert "ship it" not in out


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


def skill(folder: Path, name: str) -> Path:
    (folder / name).mkdir(parents=True)
    (folder / name / "SKILL.md").write_text(f"---\nname: {name}\n---\n")
    return folder / name


def test_link_prefers_the_epidemic_skill_and_leaves_other_links_alone(
    moto: ModuleType, tmp_path: Path, capsys: pytest.CaptureFixture[str]
):
    core, home, claude = tmp_path / "core", tmp_path / "moto", tmp_path / "claude"
    setattr(moto, "CORE_SKILLS", core)
    setattr(moto, "MOTO_HOME", home)
    setattr(moto, "CLAUDE_HOME", claude)
    skill(core, "moto-wrap")
    skill(core, "moto-brief")
    epidemic = skill(home / "skills", "moto-brief")
    skill(core, "not-moto")
    links = claude / "skills"
    links.mkdir(parents=True)
    (links / "moto-gone").symlink_to(core / "moto-gone")
    (links / "moto-store").symlink_to("/nix/store/abc-home-manager-files/moto-store")
    (links / "moto-mine").symlink_to(tmp_path)
    assert moto.cmd_link(argparse.Namespace()) == 0
    out = capsys.readouterr().out
    assert (links / "moto-wrap").readlink() == (core / "moto-wrap").resolve()
    assert (links / "moto-brief").readlink() == epidemic.resolve()
    assert "Removed moto-gone" in out
    assert not (links / "moto-gone").is_symlink()
    assert (links / "moto-store").is_symlink() and (links / "moto-mine").is_symlink()
    assert not (links / "not-moto").exists()
    assert moto.cmd_link(argparse.Namespace()) == 0
    assert capsys.readouterr().out == "All 2 moto skills were already linked.\n"
    # The Epidemic copy goes, so the generic one takes its place.
    (epidemic / "SKILL.md").unlink()
    epidemic.rmdir()
    assert moto.cmd_link(argparse.Namespace()) == 0
    assert (links / "moto-brief").readlink() == (core / "moto-brief").resolve()


def test_link_refuses_to_replace_what_it_did_not_make(
    moto: ModuleType, tmp_path: Path, capsys: pytest.CaptureFixture[str]
):
    setattr(moto, "CORE_SKILLS", tmp_path / "core")
    setattr(moto, "MOTO_HOME", tmp_path / "moto")
    setattr(moto, "CLAUDE_HOME", tmp_path / "claude")
    skill(tmp_path / "core", "moto-wrap")
    (tmp_path / "claude/skills/moto-wrap").mkdir(parents=True)
    assert moto.cmd_link(argparse.Namespace()) == 1
    assert "skipped" in capsys.readouterr().err
    assert not (tmp_path / "claude/skills/moto-wrap").is_symlink()


def iso(ts: float) -> str:
    return datetime.fromtimestamp(ts, UTC).isoformat()


def typed(at: float, text: str | list[dict[str, str]], **fields: Any) -> dict[str, Any]:
    message = {"content": text}
    return (
        {"type": "user", "promptSource": "typed", "timestamp": iso(at)}
        | {"message": message}
        | fields
    )


def test_user_turns_skip_tagged_prompts_and_those_before_the_report(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
):
    real = load_moto()
    monkeypatch.setattr(real, "CLAUDE_HOME", tmp_path / "claude")
    directory = real.session_dir("/code/widgets-ABC-1-fix")
    directory.mkdir(parents=True)
    entries = [
        {"type": "custom-title", "customTitle": "ABC-1 fix"},
        typed(100, "before the report"),
        typed(300, "[driver] carry on"),
        typed(400, '<pasted_content id="1">\n[abc-0] from my parent'),
        typed(500, "rebase it"),
        typed(600, "a subagent's prompt", isSidechain=True),
        {"type": "user", "promptSource": "system", "timestamp": iso(700)},
        typed(800, [{"type": "text", "text": "push it"}]),
    ]
    (directory / "s.jsonl").write_text("".join(json.dumps(e) + "\n" for e in entries))
    held = task(title="ABC-1 fix", parent="abc-0")
    assert real.user_turns(held, None, 200) == [500, 800]
    snoozed = task(snoozed={"session": "s", "cwd": "/code/widgets-ABC-1-fix"})
    assert real.user_turns(snoozed, None, 200) == [400, 500, 800]
    assert real.user_turns(task(title="other"), None, 200) == []


def commit(cwd: Path, message: str, at: int, email: str = "t@t") -> None:
    dated = {"GIT_AUTHOR_DATE": f"@{at}", "GIT_COMMITTER_DATE": f"@{at}"}
    subprocess.run(
        ["git", "-C", str(cwd), "-c", "user.name=t", "-c", f"user.email={email}"]
        + ["commit", "-q", "--allow-empty", "-m", message],
        check=True,
        capture_output=True,
        env=os.environ | dated,
    )


def test_commits_since_counts_the_user_s_own_on_the_branch(
    moto: ModuleType, pushed_clone: Path
):
    git(pushed_clone, "config", "user.email", "t@t")
    git(pushed_clone, "checkout", "-q", "-b", "ABC-1-fix")
    # Git reads a number of nine digits or more as a Unix time.
    commit(pushed_clone, "before", 1_700_001_000)
    commit(pushed_clone, "mine", 1_700_003_000)
    commit(pushed_clone, "from main", 1_700_003_500, email="other@t")
    commit(pushed_clone, "mine again", 1_700_004_000)
    here = task(cwd=str(pushed_clone), repo=str(pushed_clone))
    assert moto.commits_since(here, 1_700_002_000) == 2
    git(pushed_clone, "checkout", "-q", "-")
    gone = task(
        cwd=str(pushed_clone / "gone"),
        repo=str(pushed_clone),
        snoozed={"branch": "ABC-1-fix"},
    )
    assert moto.commits_since(gone, 1_700_002_000) == 2
    assert moto.commits_since(task(), 1_700_002_000) is None


def test_pr_check_gives_up_when_github_is_slow(monkeypatch: pytest.MonkeyPatch):
    real = load_moto()

    def slow(args: list[str], **_: Any) -> str:
        raise subprocess.TimeoutExpired(args, real.PR_TIMEOUT)

    monkeypatch.setattr(real, "run", slow)
    assert real.pr_updated("https://github.com/acme/widgets/pull/1") is None
    monkeypatch.setattr(real, "run", MagicMock(return_value="2026-10-05T08:27:53Z\n"))
    assert real.pr_updated("https://github.com/acme/widgets/pull/1") == 1791188873.0


def list_output(
    moto: ModuleType,
    capsys: pytest.CaptureFixture[str],
    now: float,
    turns: list[float],
    commits: int | None,
    pr_at: float,
) -> str:
    capsys.readouterr()
    with (
        patch.object(moto, "live_agents", return_value=live("idle", 1)),
        patch.object(moto.time, "time", return_value=now),
        patch.object(moto, "user_turns", return_value=turns),
        patch.object(moto, "commits_since", return_value=commits),
        patch.object(moto, "pr_updated", return_value=pr_at),
    ):
        assert moto.cmd_list(argparse.Namespace(json=False)) == 0
    return capsys.readouterr().out


def test_list_shows_what_happened_in_a_held_task_since_its_report(
    moto: ModuleType, capsys: pytest.CaptureFixture[str]
):
    report = {"kind": "done", "text": "Fixed.", "at": 1000.0}
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task(held=True, report=report, pr="https://x/pull/1")
        tasks["abc-2"] = task(pane_id="w2:p1", report=report)
    out = list_output(moto, capsys, 7300, [2000.0, 7000.0], 3, 6000.0)
    held, watched = out.split("abc-2")
    assert (
        "  done (1h ago): Fixed.\n  since the report: 2 turns with the user, last 5m"
        + " ago · 3 commits · PR updated 21m ago\n"
    ) in held
    assert "since the" not in watched


def test_list_shows_a_pane_closed_by_hand(
    moto: ModuleType, capsys: pytest.CaptureFixture[str]
):
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task(held=True, closed_at=7000.0, pane_id="w9:p1")
        tasks["abc-2"] = task(pane_id="w8:p1")
    out = list_output(moto, capsys, 7300, [], None, 0.0)
    assert "abc-1 · widgets · ABC-1-fix · pane closed by hand 5m ago" in out
    assert "abc-2 · widgets · ABC-1-fix · gone\n" in out


def test_list_adds_nothing_when_nothing_happened_since_the_report(
    moto: ModuleType, capsys: pytest.CaptureFixture[str]
):
    report = {"kind": "done", "text": "Fixed.", "at": 1000.0}
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task(held=True, report=report, pr="https://x/pull/1")
    # The PR changed before the report.
    assert "since the" not in list_output(moto, capsys, 7300, [], None, 900.0)


def test_held_task_without_a_report_counts_from_the_hold(moto: ModuleType):
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task()
    moto.cmd_hold(argparse.Namespace(agent="abc-1"))
    held_at = events(moto)[-1]["ts"]
    held = moto.read_tasks()["abc-1"]
    with (
        patch.object(moto, "user_turns", return_value=[]) as turns,
        patch.object(moto, "commits_since", return_value=1),
    ):
        info = moto.since_report(held, None, None, moto.read_events())
    turns.assert_called_once_with(held, None, held_at)
    assert info["since"] == "hold"
    assert moto.activity_line(info, held_at) == "since the hold: 1 commit"
    assert (
        moto.since_report(task(agent="other"), None, None, moto.read_events()) is None
    )


# Scheduled jobs: schedules, gates and how a due job reaches the driver.


@pytest.fixture
def jobs_home(moto: ModuleType, tmp_path: Path) -> Path:
    home = tmp_path / "moto-home"
    (home / "jobs").mkdir(parents=True)
    setattr(moto, "MOTO_HOME", home)
    return home / "jobs"


def write_job(jobs_home: Path, name: str, body: str) -> None:
    (jobs_home / f"{name}.toml").write_text(body)


MONDAY_NOON = datetime(2026, 10, 5, 12, 0).timestamp()


def test_weekday_ranges_wrap(moto: ModuleType):
    assert moto.parse_days(["mon-fri"]) == {0, 1, 2, 3, 4}
    assert moto.parse_days(["sat,sun"]) == {5, 6}
    # A range reads forwards, so fri-mon is the weekend and its edges.
    assert moto.parse_days(["fri-mon"]) == {4, 5, 6, 0}
    assert moto.parse_days(None) == set(range(7))
    with pytest.raises(ValueError):
        moto.parse_days(["funday"])


def test_times_are_rejected_not_guessed(moto: ModuleType):
    assert moto.parse_times(["09:00", "14:30"]) == [(9, 0), (14, 30)]
    for bad in (["25:00"], ["9"], [], "09:00"):
        with pytest.raises(ValueError):
            moto.parse_times(bad)


def test_occurrence_skips_days_the_job_does_not_run(moto: ModuleType):
    job = {"at": ["09:00", "14:00"], "days": ["mon-fri"]}
    assert (
        moto.occurrence(job, MONDAY_NOON, ahead=False)
        == datetime(2026, 10, 5, 9, 0).timestamp()
    )
    assert (
        moto.occurrence(job, MONDAY_NOON, ahead=True)
        == datetime(2026, 10, 5, 14, 0).timestamp()
    )
    saturday = datetime(2026, 10, 10, 12, 0).timestamp()
    # Friday's last run behind it, Monday's first ahead of it.
    assert (
        moto.occurrence(job, saturday, ahead=False)
        == datetime(2026, 10, 9, 14, 0).timestamp()
    )
    assert (
        moto.occurrence(job, saturday, ahead=True)
        == datetime(2026, 10, 12, 9, 0).timestamp()
    )


def test_a_job_runs_once_per_occurrence(moto: ModuleType):
    job = {"at": ["09:00"], "days": ["mon-fri"]}
    nine = datetime(2026, 10, 5, 9, 0).timestamp()
    assert moto.due(job, {}, MONDAY_NOON) == (nine, None)
    assert moto.due(job, {"ran_at": nine}, MONDAY_NOON) == (None, None)


def test_stale_after_records_a_missed_run_instead(moto: ModuleType):
    job = {"at": ["09:00"], "days": ["mon-fri"], "stale_after": 60}
    when, missed = moto.due(job, {}, MONDAY_NOON)
    assert when and missed and "missed by" in missed
    # Without the window the same occurrence simply runs late.
    assert (
        moto.due({k: v for k, v in job.items() if k != "stale_after"}, {}, MONDAY_NOON)[
            1
        ]
        is None
    )


def test_gate_verdicts_follow_the_exit_code(moto: ModuleType):
    assert moto.run_gate({"gate": "echo two waiting"}) == ("run", "two waiting")
    assert moto.run_gate({"gate": "exit 75"}) == ("skip", "")
    verdict, detail = moto.run_gate({"gate": "echo boom >&2; exit 3"})
    assert verdict == "broken" and "exited 3" in detail and "boom" in detail
    # No gate at all means the job always runs.
    assert moto.run_gate({}) == ("run", "")


def test_a_quiet_gate_spends_nothing(moto: ModuleType, jobs_home: Path):
    write_job(
        jobs_home,
        "quiet",
        'at = ["09:00"]\ngate = "exit 75"\ndeliver = "driver"\nbrief = "Look."\n',
    )
    assert moto.tick(MONDAY_NOON) == ["quiet: nothing to do"]
    assert not moto.pending_notes()


def test_a_busy_gate_leaves_the_driver_a_note(moto: ModuleType, jobs_home: Path):
    write_job(
        jobs_home,
        "queue",
        'at = ["09:00"]\ngate = "echo widgets#7"\ndeliver = "driver"\nbrief = "Look."\n',
    )
    assert moto.tick(MONDAY_NOON) == ["queue: left a note for the driver"]
    ((name, note),) = moto.pending_notes()
    assert name == "queue"
    assert note["text"].startswith(moto.JOB_TAG)
    assert "widgets#7" in note["text"] and "Look." in note["text"]


def test_a_newer_run_replaces_an_unread_note(moto: ModuleType, jobs_home: Path):
    write_job(
        jobs_home,
        "queue",
        'at = ["09:00", "14:00"]\ngate = "echo now"\ndeliver = "driver"\nbrief = "Look."\n',
    )
    moto.tick(MONDAY_NOON)
    moto.tick(datetime(2026, 10, 5, 14, 30).timestamp())
    assert len(moto.pending_notes()) == 1


def test_a_broken_gate_never_spawns_a_worker(moto: ModuleType, jobs_home: Path):
    write_job(
        jobs_home,
        "hunt",
        """
at = ["09:00"]
gate = "exit 3"
deliver = "worker"
repo = "widgets"
title = "bug hunt"
brief = "Hunt."
""",
    )
    spawned: list[Any] = []

    def never(*args: Any) -> dict[str, Any]:
        spawned.append(args)
        return {}

    setattr(moto, "start_worker", never)
    assert moto.tick(MONDAY_NOON) == ["hunt: broken gate, left a note for the driver"]
    assert not spawned
    ((_, note),) = moto.pending_notes()
    assert "check failed" in note["text"]


def test_a_broken_job_file_does_not_silence_the_others(
    moto: ModuleType, jobs_home: Path
):
    write_job(jobs_home, "bad", 'at = ["25:00"]\ndeliver = "driver"\nbrief = "x"\n')
    write_job(
        jobs_home,
        "good",
        'at = ["09:00"]\ngate = "exit 75"\ndeliver = "driver"\nbrief = "Look."\n',
    )
    lines = moto.tick(MONDAY_NOON)
    assert any("bad.toml" in line for line in lines)
    assert "good: nothing to do" in lines


def test_a_job_without_a_brief_follows_its_markdown_file(
    moto: ModuleType, jobs_home: Path
):
    write_job(
        jobs_home,
        "queue",
        'at = ["09:00"]\ngate = "echo widgets#7"\ndeliver = "driver"\n',
    )
    (jobs_home / "queue.md").write_text("Nag about the queue.\n")
    jobs, problems = moto.load_jobs()
    assert not problems
    assert jobs["queue"]["brief"] == "Follow jobs/queue.md."
    assert moto.job_rows(MONDAY_NOON)[0]["brief"] == "queue.md"
    moto.tick(MONDAY_NOON)
    ((_, note),) = moto.pending_notes()
    # The gate output still follows the brief.
    assert (
        "Follow jobs/queue.md.\n\nWhat the job's check found:\n\nwidgets#7"
        in note["text"]
    )


def test_an_explicit_brief_beats_the_markdown_file(moto: ModuleType, jobs_home: Path):
    write_job(
        jobs_home, "queue", 'at = ["09:00"]\ndeliver = "driver"\nbrief = "Look."\n'
    )
    (jobs_home / "queue.md").write_text("Nag about the queue.\n")
    jobs, _ = moto.load_jobs()
    assert jobs["queue"]["brief"] == "Look."
    assert moto.job_rows(MONDAY_NOON)[0]["brief"] == "inline"


def test_a_job_with_neither_brief_nor_markdown_is_unusable(
    moto: ModuleType, jobs_home: Path
):
    write_job(jobs_home, "queue", 'at = ["09:00"]\ndeliver = "driver"\n')
    jobs, problems = moto.load_jobs()
    assert not jobs
    assert problems == [
        "queue.toml: no brief, and no .md file of the same name beside it"
    ]


def test_unknown_fields_are_rejected(moto: ModuleType):
    job = {"at": ["09:00"], "deliver": "driver", "brief": "x", "evry": 5}
    assert "evry" in (moto.job_problem(job) or "")


def test_clearing_a_question_keeps_where_the_driver_is(moto: ModuleType):
    moto.write_driver(pane_id="w9:p1", session="abc")
    moto.write_driver(kind="question", text="Which base?", at=1.0)
    moto.cmd_ask(argparse.Namespace(text=[], clear=True))
    assert moto.read_driver() == {"pane_id": "w9:p1", "session": "abc"}


def test_watch_skips_snoozed_tasks(moto: ModuleType):
    with moto.tasks_for_update() as tasks:
        tasks["abc-2"] = task(pane_id="w1:p2", snoozed=SNOOZE)
    with patch.object(moto, "live_agents", side_effect=AssertionError("no poll")):
        assert moto.watch() == {"watching": 0, "lines": [], "notes": None}


def test_watch_checks_a_child_task_without_counting_it(moto: ModuleType):
    report = {"kind": "wrap", "text": "merged", "at": 1.0}
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task(parent="abc-9", report=report)
    with patch.object(moto, "live_agents", return_value=live("done", 2)):
        assert moto.watch() == {
            "watching": 0,
            "lines": ["abc-1 wrap (child of abc-9): merged"],
            "notes": None,
        }
        assert moto.watch()["lines"] == []


def test_watch_checks_a_held_task_s_pane_without_counting_it(moto: ModuleType):
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task(held=True, seen={"status": "done", "gone_since": 0.0})
    with patch.object(moto, "live_agents", return_value={}):
        assert moto.watch() == {
            "watching": 0,
            "lines": ["abc-1: pane closed"],
            "notes": None,
        }
    assert moto.read_tasks()["abc-1"]["closed_at"] == 0.0


def test_watch_reports_news_once(moto: ModuleType):
    with moto.tasks_for_update() as tasks:
        tasks["abc-1"] = task(report={"kind": "question", "text": "which?", "at": 1})
    with patch.object(moto, "live_agents", return_value=live("done", 1)):
        assert moto.watch()["lines"] == ["abc-1 question: which?"]
        assert moto.watch() == {"watching": 1, "lines": [], "notes": None}


def test_watch_hands_a_job_note_over_once(moto: ModuleType, jobs_home: Path):
    write_job(
        jobs_home,
        "queue",
        'at = ["09:00"]\ngate = "echo widgets#7"\ndeliver = "driver"\nbrief = "Look."\n',
    )
    assert moto.tick(MONDAY_NOON) == ["queue: left a note for the driver"]
    notes = moto.watch()["notes"]
    assert notes.startswith(moto.JOB_TAG) and "widgets#7" in notes
    assert moto.watch()["notes"] is None
