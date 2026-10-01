"""PR state wording, GraphQL batching, and token shaping. No live Herdr or GitHub."""

import importlib.util
import json
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path
from types import ModuleType
from typing import Any

import pytest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin/herdr-decorator"


@pytest.fixture(scope="module")
def decorator() -> ModuleType:
    loader = SourceFileLoader("herdr_decorator", str(SCRIPT))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    # dataclasses resolve annotations through sys.modules.
    sys.modules[loader.name] = module
    loader.exec_module(module)
    return module


def pr(
    state: str = "OPEN",
    draft: bool = False,
    review: str | None = None,
    checks: str | None = None,
) -> dict[str, Any]:
    rollup = {"state": checks} if checks else None
    return {
        "number": 412,
        "url": "https://github.com/o/r/pull/412",
        "state": state,
        "isDraft": draft,
        "reviewDecision": review,
        "commits": {"nodes": [{"commit": {"statusCheckRollup": rollup}}]},
    }


@pytest.mark.parametrize(
    ("fields", "expected"),
    [
        ({"state": "MERGED", "checks": "FAILURE"}, "merged"),
        ({"state": "CLOSED"}, "closed"),
        ({"draft": True, "checks": "FAILURE"}, "draft"),
        ({"review": "APPROVED", "checks": "FAILURE"}, "failing"),
        ({"review": "CHANGES_REQUESTED", "checks": "PENDING"}, "changes"),
        ({"review": "APPROVED", "checks": "PENDING"}, "checks"),
        ({"review": "APPROVED", "checks": "SUCCESS"}, "approved"),
        ({"review": "APPROVED"}, "approved"),
        ({"review": "REVIEW_REQUIRED", "checks": "SUCCESS"}, "review"),
    ],
)
def test_pr_state_reports_the_most_urgent_word(
    decorator: ModuleType, fields: dict[str, Any], expected: str
) -> None:
    assert decorator.pr_state(pr(**fields)) == expected


@pytest.mark.parametrize(
    ("fields", "expected"),
    [
        ({"review": "REVIEW_REQUIRED"}, "\uf407 #412"),
        ({"checks": "PENDING"}, "\uf407 #412 ◷"),
        ({"checks": "FAILURE"}, "\uf407 #412 \uf467"),
        ({"review": "CHANGES_REQUESTED"}, "\uf407 #412 ±"),
        ({"draft": True}, "\uf4dd #412"),
        ({"state": "MERGED"}, "\uf419 #412"),
        ({"state": "CLOSED"}, "\uf4dc #412"),
    ],
)
def test_pr_label_puts_state_in_the_icon_and_checks_in_the_mark(
    decorator: ModuleType, fields: dict[str, Any], expected: str
) -> None:
    assert decorator.pr_label(pr(**fields)) == expected


def test_query_groups_branches_by_repo_and_dedupes(decorator: ModuleType) -> None:
    a, b = ("acme", "widgets"), ("acme", "gadgets")
    query, aliases = decorator.build_query([(a, "x"), (b, "y"), (a, "x"), (a, 'q"z')])
    assert aliases == {"r0.b0": (a, "x"), "r0.b1": (a, 'q"z'), "r1.b0": (b, "y")}
    assert query.count("repository(") == 2
    assert 'headRefName: "q\\"z"' in query


def test_decorate_takes_jira_key_from_branch(decorator: ModuleType) -> None:
    pane = decorator.Pane("w1:p1", "/tmp", "claude", branch="feat/abc-12-fix")
    base = "https://jira.example.com/browse"
    tokens, links = decorator.decorate(pane, pr(review="APPROVED"), base)
    assert tokens == {"pr": "\uf407 #412 \uf42e", "jira": "ABC-12"}
    assert links["jira"] == f"{base}/ABC-12"


def test_decorate_without_a_jira_site_keeps_the_key_but_no_link(
    decorator: ModuleType,
) -> None:
    pane = decorator.Pane("w1:p1", "/tmp", "claude", branch="abc-12-fix")
    tokens, links = decorator.decorate(pane, None)
    assert tokens == {"jira": "ABC-12"}
    assert links == {}


def test_decorate_without_pr_or_key_is_empty(decorator: ModuleType) -> None:
    pane = decorator.Pane("w1:p1", "/tmp", "claude", branch="tidy-readme")
    assert decorator.decorate(pane, None) == ({}, {})


def test_remote_parsing_handles_ssh_and_https(decorator: ModuleType) -> None:
    for remote in (
        "git@github.com:acme/widgets.git",
        "https://github.com/acme/widgets",
    ):
        match = decorator.GITHUB_REMOTE.search(remote)
        assert match and match.groups() == ("acme", "widgets")


def test_locate_prefers_the_cwd_the_agent_reported(
    decorator: ModuleType, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "state"))
    repo = tmp_path / "widgets"
    repo.mkdir()
    reported = tmp_path / "state/herdr-decorator/agent-cwd/w1:p1"
    reported.parent.mkdir(parents=True)
    reported.write_text(str(repo))
    seen: list[str] = []

    def fake_git(cwd: str, *args: str) -> str:
        seen.append(cwd)
        return (
            "fix-lint" if args[0] == "rev-parse" else "git@github.com:acme/widgets.git"
        )

    monkeypatch.setattr(decorator, "git", fake_git)
    pane = decorator.Pane("w1:p1", str(tmp_path / "deleted-worktree"), "claude")
    decorator.locate(pane)
    assert seen[:2] == [str(repo), str(repo)]
    assert (pane.repo, pane.branch) == (("acme", "widgets"), "fix-lint")


def test_locate_ignores_a_reported_cwd_that_is_gone(
    decorator: ModuleType, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path / "state"))
    reported = tmp_path / "state/herdr-decorator/agent-cwd/w1:p1"
    reported.parent.mkdir(parents=True)
    reported.write_text(str(tmp_path / "gone"))
    assert decorator.reported_cwd("w1:p1") is None


def test_decorate_names_a_checkout_the_agent_moved_to(decorator: ModuleType) -> None:
    pane = decorator.Pane("w1:p1", "/tmp", "claude", moved="widgets \ue0a0 fix")
    tokens, _ = decorator.decorate(pane, None, workspace="acme")
    assert tokens == {"where": "→ widgets \ue0a0 fix"}


def test_decorate_names_the_workspace_when_the_agent_stayed(
    decorator: ModuleType,
) -> None:
    pane = decorator.Pane("w1:p1", "/tmp", "claude", branch="main")
    assert decorator.decorate(pane, None, workspace="acme") == ({"where": "acme"}, {})


def _git_repo(path: Path) -> Path:
    import subprocess

    path.mkdir()
    subprocess.run(["git", "init", "-q", "-b", "main", str(path)], check=True)
    subprocess.run(
        [
            "git",
            "-C",
            str(path),
            "-c",
            "user.name=t",
            "-c",
            "user.email=t@t",
            "commit",
            "-q",
            "--allow-empty",
            "-m",
            "init",
        ],
        check=True,
    )
    return path


def test_moved_to_is_empty_inside_the_starting_checkout(
    decorator: ModuleType, tmp_path: Path
) -> None:
    repo = _git_repo(tmp_path / "widgets")
    (repo / "src").mkdir()
    assert decorator.moved_to(str(repo / "src"), str(repo), "main") is None


def test_moved_to_names_another_repo(decorator: ModuleType, tmp_path: Path) -> None:
    start = _git_repo(tmp_path / "widgets")
    other = _git_repo(tmp_path / "gadgets")
    assert decorator.moved_to(str(other), str(start), "main") == "gadgets"


def test_moved_to_names_a_worktree_by_repo_and_branch(
    decorator: ModuleType, tmp_path: Path
) -> None:
    import subprocess

    repo = _git_repo(tmp_path / "widgets")
    tree = tmp_path / "trees/fix"
    subprocess.run(
        ["git", "-C", str(repo), "worktree", "add", "-q", "-b", "fix", str(tree)],
        check=True,
    )
    assert decorator.moved_to(str(tree), str(repo), "fix") == "widgets \ue0a0 fix"


def write_moto_tasks(state_home: Path, tasks: dict[str, Any]) -> None:
    path = state_home / "moto/tasks.json"
    path.parent.mkdir(parents=True)
    path.write_text(json.dumps({"tasks": tasks}))


def test_moto_reports_keep_only_what_waits_on_the_user(
    decorator: ModuleType, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path))
    question = {"kind": "question", "text": "Which base?", "at": 10.0}
    write_moto_tasks(
        tmp_path,
        {
            "a": {"pane_id": "w1:p1", "report": question},
            "b": {
                "pane_id": "w1:p2",
                "report": {"kind": "done", "text": "PR", "at": 1},
            },
            "c": {"pane_id": "w1:p3", "report": None},
        },
    )
    assert decorator.moto_reports() == {"w1:p1": question}


def test_moto_reports_without_a_task_file_is_empty(
    decorator: ModuleType, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path))
    assert decorator.moto_reports() == {}


def test_moto_note_shows_while_the_worker_waits(decorator: ModuleType) -> None:
    pane = decorator.Pane("w1:p1", "/code/widgets", "claude", status="done")
    report = {"kind": "blocked", "text": "x" * 80, "at": 10.0}
    note = decorator.moto_note(pane, report)
    assert note is not None and note.startswith("! x") and len(note) == 62
    tokens, _ = decorator.decorate(pane, None, note="? Which base?")
    assert tokens["moto"] == "? Which base?"


def test_moto_note_clears_once_the_worker_moves_on(decorator: ModuleType) -> None:
    report = {"kind": "question", "text": "Which base?", "at": 10.0}
    working = decorator.Pane("w1:p1", None, "claude", status="working")
    assert decorator.moto_note(working, report) is None
    answered = decorator.Pane(
        "w1:p1", None, "claude", status="done", working_since=20.0
    )
    assert decorator.moto_note(answered, report) is None


def test_the_driver_question_stays_while_the_driver_works(
    decorator: ModuleType, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    monkeypatch.setenv("XDG_STATE_HOME", str(tmp_path))
    write_moto_tasks(tmp_path, {})
    ask = {"pane_id": "w1:p9", "kind": "question", "text": "Merge #12?", "at": 10.0}
    (tmp_path / "moto/driver.json").write_text(json.dumps(ask))
    report = decorator.moto_reports()["w1:p9"]
    assert report["sticky"] is True
    busy = decorator.Pane("w1:p9", None, "claude", status="working", working_since=20.0)
    assert decorator.moto_note(busy, report) == "? Merge #12?"
