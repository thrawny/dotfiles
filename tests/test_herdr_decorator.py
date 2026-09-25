"""PR state wording, GraphQL batching, and token shaping. No live Herdr or GitHub."""

import importlib.util
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
    tokens, links = decorator.decorate(pane, pr(review="APPROVED"))
    assert tokens == {"pr": "\uf407 #412 \uf42e", "jira": "ABC-12"}
    assert links["jira"].endswith("/browse/ABC-12")


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
