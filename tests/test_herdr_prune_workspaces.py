import importlib.util
from importlib.machinery import SourceFileLoader
from pathlib import Path
from types import ModuleType
from typing import Any

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "bin/herdr-prune-workspaces"


@pytest.fixture(scope="module")
def prune() -> ModuleType:
    loader = SourceFileLoader("herdr_prune_workspaces", str(SCRIPT))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def shell(pid: int) -> dict[str, Any]:
    return {
        "shell_pid": pid,
        "foreground_process_group_id": pid,
        "foreground_processes": [{"name": "zsh", "pid": pid}],
    }


def running(pid: int, name: str) -> dict[str, Any]:
    return {
        "shell_pid": pid,
        "foreground_process_group_id": pid + 1,
        "foreground_processes": [{"name": name, "pid": pid + 1}],
    }


def test_only_unfocused_workspaces_of_idle_shells_close(prune: ModuleType):
    workspaces = [
        {"workspace_id": "idle", "label": "idle"},
        {"workspace_id": "split", "label": "split"},
        {"workspace_id": "agent", "label": "agent"},
        {"workspace_id": "editor", "label": "editor"},
        {"workspace_id": "focused", "label": "focused", "focused": True},
        {"workspace_id": "bg", "label": "background"},
    ]
    panes = [
        {"workspace_id": "idle", "pane_id": "idle:1", "cwd": "/a"},
        {"workspace_id": "split", "pane_id": "split:1", "cwd": "/b"},
        {"workspace_id": "split", "pane_id": "split:2", "cwd": "/b"},
        {"workspace_id": "agent", "pane_id": "agent:1", "agent": "claude"},
        {"workspace_id": "editor", "pane_id": "editor:1"},
        {"workspace_id": "editor", "pane_id": "editor:2"},
        {"workspace_id": "focused", "pane_id": "focused:1"},
        {"workspace_id": "bg", "pane_id": "bg:1"},
    ]
    processes = {
        "idle:1": shell(10),
        "split:1": shell(20),
        "split:2": shell(30),
        # An agent pane's shell may look idle while the agent is between turns.
        "agent:1": shell(40),
        "editor:1": shell(50),
        "editor:2": running(60, "nvim"),
        "focused:1": shell(70),
        "bg:1": shell(80),
    }
    found = prune.empty_workspaces(workspaces, panes, processes.__getitem__)
    assert [(w["workspace_id"], cwd) for w, cwd in found] == [
        ("idle", "/a"),
        ("split", "/b"),
    ]


def test_a_pane_with_unknown_processes_is_not_idle(prune: ModuleType):
    assert not prune.idle_shell({}, {"shell_pid": 10})
