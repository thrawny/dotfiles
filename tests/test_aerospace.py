"""Check AeroSpace configuration intent and shell syntax, not macOS behavior."""

import shlex
import subprocess
import tomllib
from pathlib import Path
from typing import Any

import pytest

CONFIG = Path(__file__).resolve().parents[1] / "config/aerospace/aerospace.toml"


@pytest.fixture
def config() -> dict[str, Any]:
    with CONFIG.open("rb") as source:
        return tomllib.load(source)


@pytest.fixture
def bindings(config: dict[str, Any]) -> dict[str, str]:
    return config["mode"]["main"]["binding"]


def test_preferences(config: dict[str, Any]):
    assert config["config-version"] == 2
    for setting in ("start-at-login", "auto-reload-config"):
        assert config[setting] is True
    assert config["focus-follows-mouse"]["enabled"] is True
    assert config["on-focus-changed"] == ["move-mouse window-lazy-center"]
    assert config["on-focused-monitor-changed"] == ["move-mouse monitor-lazy-center"]
    assert config["default-root-container-layout"] == "tiles"
    assert config["accordion-padding"] == 0
    assert config["gaps"] == {
        "inner": {"horizontal": 0, "vertical": 0},
        "outer": {"left": 0, "right": 0, "top": 0, "bottom": 0},
    }


def test_workspace_policy(config: dict[str, Any]):
    assert config["persistent-workspaces"] == ["main", "web", "dotfiles"]
    for setting in (
        "workspace-to-monitor-force-assignment",
        "after-login-command",
        "after-startup-command",
    ):
        assert setting not in config


def test_core_keymap(bindings: dict[str, str]):
    expected = {
        "alt-enter": bindings["alt-enter"],  # Checked separately below.
        "alt-w": "close",
        "alt-f": "fullscreen",
        "alt-v": "layout floating tiling",
        "alt-m": "focus-back-and-forth",
        "alt-tab": "focus-back-and-forth",
        "alt-shift-m": "workspace-back-and-forth",
        "alt-minus": "resize width -50",
        "alt-equal": "resize width +50",
        "alt-shift-minus": "resize height -50",
        "alt-shift-equal": "resize height +50",
        "alt-b": "workspace web",
        "alt-shift-semicolon": "mode service",
    }
    for key, direction in zip("hjkl", ("left", "down", "up", "right")):
        expected[f"alt-{key}"] = f"focus {direction} --ignore-floating"
        expected[f"alt-shift-{key}"] = f"swap {direction}"
        expected[f"alt-ctrl-{key}"] = f"focus-monitor {direction}"
        expected[f"alt-shift-ctrl-{key}"] = (
            f"move-node-to-monitor --focus-follows-window {direction}"
        )
        expected[f"alt-cmd-{key}"] = f"move-workspace-to-monitor {direction}"
    workspaces = ["main", "web", "dotfiles", *map(str, range(4, 11))]
    for key, workspace in zip("1234567890", workspaces):
        expected[f"alt-{key}"] = f"workspace {workspace}"
        expected[f"alt-shift-{key}"] = (
            f"move-node-to-workspace --focus-follows-window {workspace}"
        )
    # Exact comparison also keeps deferred and obsolete bindings out.
    assert bindings == expected


def test_terminal_launch(bindings: dict[str, str]):
    binding = bindings["alt-enter"]
    assert binding.startswith("exec-and-forget ")
    script = binding.removeprefix("exec-and-forget ")
    result = subprocess.run(
        ["bash", "-n"], input=script, text=True, capture_output=True
    )
    assert result.returncode == 0, result.stderr
    assert 'if application "Ghostty" is running then' in script
    assert 'tell application "Ghostty" to activate window (new window)' in script
    assert 'tell application "Ghostty" to activate' in script
    assert "System Events" not in script  # No simulated keystrokes.


def test_rescue_mode(config: dict[str, Any]):
    assert set(config["mode"]) == {"main", "service"}
    assert config["mode"]["service"]["binding"] == {
        "esc": ["reload-config", "mode main"],
        "r": ["flatten-workspace-tree", "mode main"],
    }


def test_only_confirmed_app_rules(config: dict[str, Any]):
    expected = {
        "com.tinyspeck.slackmacgap": "move-node-to-workspace main",
        "com.microsoft.teams2": "move-node-to-workspace main",
        "com.microsoft.Outlook": "move-node-to-workspace main",
        "com.apple.MobileSMS": "move-node-to-workspace main",
        "com.apple.finder": "layout floating",
        "com.apple.Preview": "layout floating",
    }
    rules = config["on-window-detected"]
    assert len(rules) == len(expected)
    actual = {}
    for rule in rules:
        assert set(rule) == {"if", "run"}
        condition = shlex.split(rule["if"])
        assert condition[:3] == ["test", "%{app-bundle-id}", "="]
        assert len(condition) == 4
        actual[condition[3]] = rule["run"]
    # No browser routing, scratchpads, forced tiling or Wispr overlay movement.
    assert actual == expected
