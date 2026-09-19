"""Exercise the walkthrough in a disposable checkout with a simulated Mac/Nix.

No installer, Home Manager activation, or host configuration is changed.
"""

# unittest creates these per-test fixtures in setUp, not __init__.
# pyright: reportUninitializedInstanceVariable=false

import json
import os
import pathlib
import pty
import shutil
import subprocess
import tempfile
import unittest
from typing import final

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "bin/bootstrap-mac"


@final
class BootstrapMacTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = pathlib.Path(self.temp.name).resolve()
        self.repo = self.home / "dotfiles"
        (self.repo / "bin").mkdir(parents=True)
        (self.repo / "nix/hosts").mkdir(parents=True)
        shutil.copy(SCRIPT, self.repo / "bin/bootstrap-mac")
        self.flake = self.repo / "nix/flake.nix"
        self.flake.write_text("{\n      homeConfigurations = {\n      };\n}\n")
        (self.home / "nix-bin").mkdir()
        self.nix = self.home / "nix-bin/nix"
        self.nix.write_text(
            """#!/bin/bash
set -eu
case "$1" in
  --version) echo 'Determinate Nix test' ;;
  store) echo 'Store URL: daemon' ;;
  eval)
    case "$*" in
      *home.username*) echo "${CONFIG_USER:-tester}" ;;
      *home.homeDirectory*) echo "$HOME" ;;
      *specialArgs.dotfiles*) echo "$HOME/dotfiles" ;;
      *activationPackage*) echo /nix/store/test-activation.drv ;;
      *) if [ "${TARGET_EXISTS:-1}" = 1 ]; then echo test-mac; fi ;;
    esac ;;
  run)
    [ "$(command -v nix)" = "$HOME/nix-bin/nix" ] || exit 90
    [ -d "${XDG_STATE_HOME:-$HOME/.local/state}/nix/profiles" ] || exit 91
    echo switch >> "$HOME/switches"
    if [ "${FAIL_SWITCH_ONCE:-0}" = 1 ] && [ ! -e "$HOME/failed" ]; then
      touch "$HOME/failed"
      exit 1
    fi ;;
  *) exit 99 ;;
esac
"""
        )
        self.nix.chmod(0o755)

    def run_walkthrough(self, answers: str, **extra_env: str) -> tuple[int, str]:
        # A PTY supplies the interactive stdin required by the real entry point.
        master, slave = pty.openpty()
        shell = """
source "$HOME/dotfiles/bin/bootstrap-mac"
uname() { if [ "$1" = -s ]; then echo Darwin; else echo arm64; fi; }
id() { if [ "$1" = -u ]; then echo 501; else echo tester; fi; }
hostname() { echo test-mac.local; }
xcode-select() { return 0; }
git() { return 0; }
find_nix() { nix_bin="$HOME/nix-bin/nix"; return 0; }
main
"""
        proc = subprocess.Popen(
            ["/bin/bash", "-c", shell],
            stdin=slave,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            env={
                **os.environ,
                "HOME": str(self.home),
                "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                "XDG_STATE_HOME": str(self.home / ".local/state"),
                **extra_env,
            },
            text=True,
        )
        os.close(slave)
        try:
            os.write(master, answers.encode())
            output, _ = proc.communicate(timeout=15)
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait()
            os.close(master)
        return proc.returncode, output

    def test_existing_target_can_stop_before_switch_without_changes(self):
        original = self.flake.read_text()
        code, output = self.run_walkthrough("\n\nn\n")
        self.assertEqual(code, 0, output)
        self.assertIn("Stopped before switching", output)
        self.assertEqual(self.flake.read_text(), original)
        self.assertFalse((self.home / "switches").exists())

    def test_creates_target_and_preserves_literal_git_identity(self):
        name = 'A "quoted" \\ ${name}'
        code, output = self.run_walkthrough(
            f"y\n{name}\ntest@example.com\n\n\nn\n", TARGET_EXISTS="0"
        )
        self.assertEqual(code, 0, output)
        target = self.repo / "nix/hosts/test-mac/default.nix"
        parsed = subprocess.check_output(
            ["nix", "eval", "--json", "--file", str(target)], text=True
        )
        config = json.loads(parsed)
        self.assertEqual(config["gitIdentity"]["name"], name)
        self.assertEqual(config["username"], "tester")
        self.assertEqual(config["dotfiles"], str(self.repo))
        self.assertEqual(self.flake.read_text().count('"test-mac" ='), 1)
        self.assertFalse((self.home / "switches").exists())

    def test_mismatched_user_cannot_reach_switch(self):
        code, output = self.run_walkthrough("\n\nq\n", CONFIG_USER="someone-else")
        self.assertEqual(code, 0, output)
        self.assertIn("Target settings do not match", output)
        self.assertFalse((self.home / "switches").exists())

    def test_existing_host_file_is_never_overwritten(self):
        target = self.repo / "nix/hosts/test-mac/default.nix"
        target.parent.mkdir()
        target.write_text("my existing configuration\n")
        code, output = self.run_walkthrough("y\n", TARGET_EXISTS="0")
        self.assertNotEqual(code, 0, output)
        self.assertIn("already exists", output)
        self.assertEqual(target.read_text(), "my existing configuration\n")

    def test_failed_switch_can_be_retried(self):
        code, output = self.run_walkthrough("\n\ny\n\nn\n", FAIL_SWITCH_ONCE="1")
        self.assertEqual(code, 0, output)
        self.assertIn("The switch failed", output)
        self.assertIn("Home Manager switch completed", output)
        self.assertEqual((self.home / "switches").read_text(), "switch\nswitch\n")

    def test_first_switch_initializes_custom_state_directory(self):
        state_dir = self.home / "custom-state"
        code, output = self.run_walkthrough("\n\ny\nn\n", XDG_STATE_HOME=str(state_dir))
        self.assertEqual(code, 0, output)
        self.assertTrue((state_dir / "nix/profiles").is_dir())
        self.assertIn("Home Manager switch completed", output)


if __name__ == "__main__":
    unittest.main()
