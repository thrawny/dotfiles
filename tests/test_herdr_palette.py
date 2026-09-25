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
    assert [(e.label, e.note) for e in entries] == [
        ("#2", "fix b · widgets"),
        ("#1", "fix a · widgets"),
        ("ABC-1", "fix a · widgets"),
    ]
    assert entries[2].target == "https://jira.example.com/browse/ABC-1"


def test_actions_leave_out_the_palette_itself(palette: ModuleType) -> None:
    actions = [
        {
            "plugin_id": "thrawny.palette",
            "action_id": "open",
            "title": "Command palette",
        },
        {"plugin_id": "x.picker", "action_id": "open", "title": "Pick a project"},
    ]
    [entry] = palette.action_entries(actions)
    assert (entry.label, entry.kind, entry.target) == (
        "Pick a project",
        "action",
        "x.picker open",
    )


@pytest.mark.parametrize("strip_ansi", [False, True])
def test_pick_reads_the_hidden_fields_of_the_chosen_row(
    palette: ModuleType, strip_ansi: bool
) -> None:
    entries = palette.link_entries({"w1:p1": saved_pane("#1", "ABC-1")}, SNAPSHOT, None)
    line = entries[1].line()
    if strip_ansi:
        line = line.replace(palette.DIM, "").replace(palette.RESET, "")
    done = subprocess.CompletedProcess(["fzf"], 0, stdout=line + "\n")
    with patch.object(palette.subprocess, "run", return_value=done):
        assert palette.pick(entries) == entries[1]


def test_pick_returns_none_when_fzf_is_cancelled(palette: ModuleType) -> None:
    done = subprocess.CompletedProcess(["fzf"], 130, stdout="")
    with patch.object(palette.subprocess, "run", return_value=done):
        assert palette.pick([]) is None


def test_invoke_closes_the_popup_before_running_the_action(
    palette: ModuleType,
) -> None:
    calls: list[str] = []

    def close_popup() -> None:
        calls.append("close")

    def herdr_json(*_args: str) -> dict[str, Any]:
        calls.append("invoke")
        return {"result": {}}

    with (
        patch.object(palette, "close_popup", side_effect=close_popup),
        patch.object(palette, "herdr_json", side_effect=herdr_json),
        patch.object(palette, "notify") as notify,
    ):
        assert palette.invoke("x.picker", "open") == 0
    assert calls == ["close", "invoke"]
    notify.assert_not_called()


def test_invoke_reports_errors(palette: ModuleType) -> None:
    missing = {"error": {"code": "plugin_not_found", "message": "plugin not found"}}
    with (
        patch.object(palette, "close_popup"),
        patch.object(palette, "herdr_json", return_value=missing),
        patch.object(palette, "notify") as notify,
    ):
        assert palette.invoke("x.picker", "open") == 1
    notify.assert_called_once()
