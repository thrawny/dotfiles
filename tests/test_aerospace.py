"""Portable checks for the agreed AeroSpace keymap and app policy.

These check configuration intent and shell syntax, not macOS window behavior.
"""

import shlex
import subprocess
import tomllib
import unittest
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "config/aerospace/aerospace.toml"


class AeroSpaceConfigTests(unittest.TestCase):
    config: dict[str, Any] = {}
    bindings: dict[str, str] = {}

    def setUp(self):
        with CONFIG.open("rb") as source:
            self.config = tomllib.load(source)
        self.bindings = self.config["mode"]["main"]["binding"]

    def test_preferences(self):
        self.assertEqual(self.config["config-version"], 2)
        for setting in ("start-at-login", "auto-reload-config"):
            self.assertIs(self.config[setting], True)
        self.assertIs(self.config["focus-follows-mouse"]["enabled"], True)
        self.assertEqual(
            self.config["on-focus-changed"], ["move-mouse window-lazy-center"]
        )
        self.assertEqual(
            self.config["on-focused-monitor-changed"],
            ["move-mouse monitor-lazy-center"],
        )
        self.assertEqual(self.config["default-root-container-layout"], "tiles")
        self.assertEqual(self.config["accordion-padding"], 0)
        self.assertEqual(
            self.config["gaps"],
            {
                "inner": {"horizontal": 0, "vertical": 0},
                "outer": {"left": 0, "right": 0, "top": 0, "bottom": 0},
            },
        )

    def test_workspace_policy(self):
        self.assertEqual(
            self.config["persistent-workspaces"], ["main", "web", "dotfiles"]
        )
        self.assertNotIn("workspace-to-monitor-force-assignment", self.config)
        self.assertNotIn("after-login-command", self.config)
        self.assertNotIn("after-startup-command", self.config)

    def test_core_keymap(self):
        expected = {
            "alt-enter": self.bindings["alt-enter"],  # Checked separately below.
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
        self.assertEqual(self.bindings, expected)

    def test_terminal_launch(self):
        binding = self.bindings["alt-enter"]
        self.assertTrue(binding.startswith("exec-and-forget "))
        script = binding.removeprefix("exec-and-forget ")
        result = subprocess.run(
            ["bash", "-n"], input=script, text=True, capture_output=True, check=False
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('if application "Ghostty" is running then', script)
        self.assertIn(
            'tell application "Ghostty" to activate window (new window)', script
        )
        self.assertIn('tell application "Ghostty" to activate', script)
        self.assertNotIn("System Events", script)  # No simulated keystrokes.

    def test_rescue_mode(self):
        self.assertEqual(set(self.config["mode"]), {"main", "service"})
        self.assertEqual(
            self.config["mode"]["service"]["binding"],
            {
                "esc": ["reload-config", "mode main"],
                "r": ["flatten-workspace-tree", "mode main"],
            },
        )

    def test_only_confirmed_app_rules(self):
        expected = {
            "com.tinyspeck.slackmacgap": "move-node-to-workspace main",
            "com.microsoft.teams2": "move-node-to-workspace main",
            "com.microsoft.Outlook": "move-node-to-workspace main",
            "com.apple.MobileSMS": "move-node-to-workspace main",
            "com.apple.finder": "layout floating",
            "com.apple.Preview": "layout floating",
        }
        rules = self.config["on-window-detected"]
        self.assertEqual(len(rules), len(expected))
        actual = {}
        for rule in rules:
            self.assertEqual(set(rule), {"if", "run"})
            condition = shlex.split(rule["if"])
            self.assertEqual(condition[:3], ["test", "%{app-bundle-id}", "="])
            self.assertEqual(len(condition), 4)
            actual[condition[3]] = rule["run"]
        # No browser routing, scratchpads, forced tiling or Wispr overlay movement.
        self.assertEqual(actual, expected)


if __name__ == "__main__":
    unittest.main()
