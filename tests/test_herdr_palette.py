"""Palette rows and choice parsing. No live Herdr, fzf, or browser."""

import importlib.util
import subprocess
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path
from types import ModuleType
from typing import Any
from unittest.mock import patch

import pytest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "bin/herdr-palette"


@pytest.fixture(scope="module")
def palette() -> ModuleType:
    loader = SourceFileLoader("herdr_palette", str(SCRIPT))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    # dataclasses resolve annotations through sys.modules.
    sys.modules[loader.name] = module
    loader.exec_module(module)
    return module


def saved_pane(pr: str | None, jira: str | None) -> dict[str, Any]:
    tokens: dict[str, str] = {}
    links: dict[str, str] = {}
    if pr:
        tokens["pr"], links["pr"] = pr, f"https://github.com/acme/widgets/pull/{pr[1:]}"
    if jira:
        tokens["jira"], links["jira"] = jira, f"https://jira.example.com/browse/{jira}"
    return {"tokens": tokens, "links": links}


SNAPSHOT = {
    "workspaces": [{"workspace_id": "w1", "label": "widgets"}],
    "panes": [
        {"pane_id": "w1:p1", "workspace_id": "w1", "terminal_title_stripped": "fix a"},
        {"pane_id": "w1:p2", "workspace_id": "w1", "terminal_title_stripped": "fix b"},
    ],
}


def test_links_put_the_focused_pane_first_and_skip_closed_panes(
    palette: ModuleType,
) -> None:
    saved = {
        "w1:p1": saved_pane("#1", "ABC-1"),
        "w1:p2": saved_pane("#2", None),
        "w9:p9": saved_pane("#9", "ABC-9"),
    }
    entries = palette.link_entries(saved, SNAPSHOT, "w1:p2")
    assert [(e.tag, e.label, e.note) for e in entries] == [
        ("gh", "#2", "fix b · widgets"),
        ("gh", "#1", "fix a · widgets"),
        ("jira", "ABC-1", "fix a · widgets"),
    ]
    assert entries[2].target == "https://jira.example.com/browse/ABC-1"


@pytest.mark.parametrize("strip_ansi", [False, True])
def test_pick_reads_the_hidden_fields_of_the_chosen_row(
    palette: ModuleType, strip_ansi: bool
) -> None:
    entries = palette.link_entries({"w1:p1": saved_pane("#1", "ABC-1")}, SNAPSHOT, None)
    line = entries[1].line()
    if strip_ansi:
        for code in (palette.DIM, palette.BOLD, palette.RESET):
            line = line.replace(code, "")
    done = subprocess.CompletedProcess(["fzf"], 0, stdout=line + "\n")
    with patch.object(palette.subprocess, "run", return_value=done):
        assert palette.pick(entries) == entries[1]
