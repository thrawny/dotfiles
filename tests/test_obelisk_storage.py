"""Disk admission decisions, with plain closure metadata and byte counts."""

import runpy
from pathlib import Path

import pytest

STORAGE = runpy.run_path(
    str(Path(__file__).resolve().parents[1] / "bin/obelisk-storage")
)
GIB = STORAGE["GIB"]


def test_incoming_data_must_leave_the_full_floor():
    fits = STORAGE["fits"]
    assert fits(20 * GIB, 5 * GIB)
    assert not fits(20 * GIB, 5 * GIB + 1)
    assert not fits(15 * GIB - 1, 0)
    with pytest.raises(ValueError):
        fits(20 * GIB, -1)


def test_deployment_budget_counts_only_missing_paths():
    closure = {"/nix/store/existing": {"narSize": 99}, "/nix/store/new": {"narSize": 7}}
    assert STORAGE["missing_size"](closure, {"/nix/store/new"}) == 7
    assert STORAGE["missing_size"](closure, set()) == 0


def test_unknown_incoming_paths_fail_closed():
    with pytest.raises(KeyError):
        STORAGE["missing_size"]({}, {"/nix/store/unknown"})
