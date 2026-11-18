"""prctl decides which existing reviews stand as an approval or changes request."""

import importlib.util
import sys
from datetime import UTC, datetime, timedelta
from importlib.machinery import SourceFileLoader
from pathlib import Path
from types import ModuleType

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "bin/prctl"


@pytest.fixture(scope="module")
def prctl() -> ModuleType:
    loader = SourceFileLoader("prctl", str(SCRIPT))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[loader.name] = module
    loader.exec_module(module)
    return module


def _review(
    prctl: ModuleType, key: str, author: str, state: str, minutes: int
) -> object:
    return prctl.Activity(
        key=key,
        kind="review",
        author=author,
        created_at=datetime(2026, 1, 1, tzinfo=UTC) + timedelta(minutes=minutes),
        state=state,
        body="",
        url="",
        location="",
    )


def test_latest_decision_per_reviewer_stands(prctl: ModuleType) -> None:
    items = [
        _review(prctl, "a1", "alice", "approved", 1),
        _review(prctl, "a2", "alice", "changes-requested", 2),
        _review(prctl, "b1", "Bob", "approved", 3),
        _review(prctl, "b2", "bob", "commented", 4),
        _review(prctl, "c1", "carol", "approved", 5),
        _review(prctl, "c2", "carol", "dismissed", 6),
        _review(prctl, "d1", "dave", "commented", 7),
    ]
    assert {item.key for item in prctl.review_decisions(items)} == {"a2", "b1"}
