"""Test walkthrough decisions without installing software or touching the host home."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

BOOTSTRAP = Path(__file__).resolve().parents[1] / "bin/bootstrap-macos"

MOCKS = r"""
require_terminal() { :; }
check_platform() { :; }
xcode-select() { return 0; }
load_homebrew() { brew_ready=$TEST_BREW_READY; }
install_homebrew() { record install-homebrew; TEST_BREW_READY=1; }
record() { printf '%s\n' "$*" >> "$EVENT_LOG"; }
brew() { record "brew $*"; return 0; }
gh() { [[ $1 == auth && $2 == status ]] || record "gh $*"; }
claude() { record claude; }
codex() { record codex; }
pi() { record pi; }
nvim() { record nvim; }
open() { return 1; }
killall() { record "killall $*"; }
git() {
  if [[ $1 == clone ]]; then
    record clone
    command git clone --branch without-nix "$FIXTURE" "$HOME/dotfiles"
  else
    command git "$@"
  fi
}
"""


class WalkthroughTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.home = self.root / "home"
        self.home.mkdir()
        self.repo = self.home / "dotfiles"
        self.events = self.root / "events"
        self.fixture = self.root / "fixture"
        self.fixture.mkdir()
        self.environment = {
            **os.environ,
            "HOME": str(self.home),
            "BOOTSTRAP": str(BOOTSTRAP),
            "EVENT_LOG": str(self.events),
            "FIXTURE": str(self.fixture),
            "TEST_BREW_READY": "1",
            "TEST_CONFLICT": "0",
            "TEST_PACKAGE_EXIT": "0",
            "TEST_CHECK_EXIT": "0",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
        }
        self.git("init", "-q", "-b", "without-nix", str(self.fixture))
        scripts = {
            "setup-macos": """
if [[ ${1:-} != --force && $TEST_CONFLICT == 1 ]]; then
  printf 'skip unmanaged conflict: .zprofile\n'
fi
""",
            "install-macos-packages": 'exit "$TEST_PACKAGE_EXIT"\n',
            "check-macos": 'exit "$TEST_CHECK_EXIT"\n',
            "apply-macos-defaults": "",
        }
        (self.fixture / "bin").mkdir()
        for name, body in scripts.items():
            script = self.fixture / "bin" / name
            script.write_text(
                '#!/bin/bash\nset -eu\nprintf "%s %s\\n" "${0##*/}" "$*" >> "$EVENT_LOG"\n'
                + body
            )
            script.chmod(0o755)
        self.git("-C", str(self.fixture), "add", ".")
        self.git(
            "-C",
            str(self.fixture),
            "-c",
            "user.name=Test",
            "-c",
            "user.email=test@example.com",
            "commit",
            "-qm",
            "fixture",
        )
        self.git("clone", "-q", str(self.fixture), str(self.repo))

    def git(self, *args):
        return subprocess.check_output(
            ["git", *args], env=self.environment, stderr=subprocess.STDOUT
        )

    def run_script(self, answers=(), invocation="main", mocks=MOCKS, updates=None):
        return subprocess.run(
            ["/bin/bash", "-c", 'source "$BOOTSTRAP"\n' + mocks + "\n" + invocation],
            env={**self.environment, **(updates or {})},
            input="".join(answer + "\n" for answer in answers),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=10,
        )

    def recorded(self):
        return self.events.read_text().splitlines() if self.events.exists() else []

    def remaining_answers(self):
        # Identity, three agents, Neovim, preference review, preference apply.
        return ["n"] * 7

    def test_existing_homebrew_and_checkout_then_repeat(self):
        local_edit = self.repo / "keep-me"
        local_edit.write_text("uncommitted")
        for _ in range(2):
            result = self.run_script(["y", "y", *self.remaining_answers()])
            self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(local_edit.read_text(), "uncommitted")
        self.assertNotIn("clone", self.recorded())
        self.assertNotIn("install-homebrew", self.recorded())
        self.assertEqual(self.recorded().count("install-macos-packages "), 2)
        self.assertIn("brew bundle check --file Brewfile", self.recorded())
        self.assertNotIn("apply-macos-defaults ", self.recorded())

    def test_missing_homebrew_can_be_installed(self):
        result = self.run_script(
            ["y", "y", "y", *self.remaining_answers()],
            updates={"TEST_BREW_READY": "0"},
        )
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("install-homebrew", self.recorded())
        self.assertIn("install-macos-packages ", self.recorded())

    def test_missing_homebrew_can_be_deferred_while_linking(self):
        result = self.run_script(
            ["n", "y", *self.remaining_answers()],
            updates={"TEST_BREW_READY": "0"},
        )
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("setup-macos ", self.recorded())
        self.assertNotIn("install-macos-packages ", self.recorded())
        self.assertNotIn("install-homebrew", self.recorded())
        self.assertIn("finished with deferred steps", result.stdout)

    def test_conflicts_require_explicit_backup_choice(self):
        result = self.run_script(
            ["y", "n", *self.remaining_answers()], updates={"TEST_CONFLICT": "1"}
        )
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("setup-macos --force", self.recorded())
        self.assertNotIn("install-macos-packages ", self.recorded())
        result = self.run_script(
            ["y", "y", "y", *self.remaining_answers()],
            updates={"TEST_CONFLICT": "1"},
        )
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("setup-macos --force", self.recorded())
        self.assertIn("install-macos-packages ", self.recorded())

    def test_declining_links_also_defers_packages(self):
        result = self.run_script(["n", *self.remaining_answers()])
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("setup-macos ", self.recorded())
        self.assertNotIn("install-macos-packages ", self.recorded())

    def test_package_failure_stops_before_preferences_and_verification(self):
        result = self.run_script(["y", "y"], updates={"TEST_PACKAGE_EXIT": "23"})
        self.assertEqual(result.returncode, 23, result.stdout)
        self.assertIn("Stopped during: Packages and plugins", result.stdout)
        self.assertNotIn("check-macos ", self.recorded())
        self.assertNotIn("Walkthrough finished", result.stdout)

    def test_failed_verification_exits_nonzero(self):
        result = self.run_script(
            ["y", "y", *self.remaining_answers()], updates={"TEST_CHECK_EXIT": "1"}
        )
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("Verification found problems", result.stdout)
        self.assertIn("brew bundle check --file Brewfile", self.recorded())

    def test_eof_and_quit_do_not_apply_configuration(self):
        for answers in ([], ["q"]):
            result = self.run_script(answers)
            self.assertEqual(result.returncode, 130, result.stdout)
        self.assertNotIn("setup-macos ", self.recorded())

    def test_identity_is_local_and_preserves_other_settings(self):
        identity = self.home / ".gitconfig.local"
        identity.write_text("[core]\n  editor = nano\n")
        result = self.run_script(
            ["y", "n", "y", "Test Person", "person@example.com", *["n"] * 6]
        )
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("editor = nano", identity.read_text())
        self.assertIn("name = Test Person", identity.read_text())
        self.assertIn("email = person@example.com", identity.read_text())

    def test_wrong_branch_is_left_untouched(self):
        self.git("-C", str(self.repo), "checkout", "-qb", "other")
        result = self.run_script()
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("Switch it to without-nix", result.stdout)
        self.assertEqual(self.recorded(), [])

    def test_absent_checkout_is_cloned(self):
        self.repo.rename(self.home / "previous-checkout")
        result = self.run_script(["y", "y", "y", *self.remaining_answers()])
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("clone", self.recorded())

    def test_unrelated_directory_is_not_replaced(self):
        self.repo.rename(self.home / "previous-checkout")
        self.repo.mkdir()
        marker = self.repo / "keep-me"
        marker.write_text("original")
        result = self.run_script()
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertEqual(marker.read_text(), "original")
        self.assertNotIn("clone", self.recorded())

    def test_homebrew_download_failure_is_reported_and_cleaned_up(self):
        result = self.run_script(
            invocation="""
stage=Homebrew
installer_file=''
trap finish EXIT
curl() { printf '%s' "$4" > "$EVENT_LOG"; return 22; }
install_homebrew
""",
            mocks="",
        )
        self.assertEqual(result.returncode, 22, result.stdout)
        self.assertIn("Stopped during: Homebrew", result.stdout)
        self.assertFalse(Path(self.events.read_text()).exists())

    def test_developer_tools_can_be_installed_before_cloning(self):
        mocks = (
            MOCKS
            + r"""
xcode-select() {
  if [[ $1 == --install ]]; then
    record install-developer-tools
    touch "$HOME/developer-tools-ready"
  else
    [[ -f "$HOME/developer-tools-ready" ]]
  fi
}
"""
        )
        result = self.run_script(
            ["y", "y", "y", *self.remaining_answers()], mocks=mocks
        )
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.recorded()[0], "install-developer-tools")

    def test_apps_agents_and_preferences_only_run_when_chosen(self):
        mocks = (
            MOCKS
            + r"""
open() { [[ $1 == -Ra ]] || record "open $*"; }
"""
        )
        result = self.run_script(
            ["y", "y", "n", *["y"] * 6, "n", "y", "n"], mocks=mocks
        )
        self.assertEqual(result.returncode, 0, result.stdout)
        for event in (
            "claude",
            "codex",
            "pi",
            "nvim",
            "open -a Ghostty",
            "open -a AeroSpace",
            "apply-macos-defaults ",
        ):
            self.assertIn(event, self.recorded())
        self.assertNotIn("killall Finder Dock", self.recorded())

    def test_platform_guard_rejects_root_and_intel(self):
        for mocks in (
            "id() { echo 0; }",
            "id() { echo 501; }; uname() { echo x86_64; }",
        ):
            result = self.run_script(invocation="check_platform", mocks=mocks)
            self.assertEqual(result.returncode, 1, result.stdout)
        self.assertEqual(self.recorded(), [])

    def test_extra_arguments_are_rejected(self):
        result = self.run_script(invocation="main --help extra", mocks="")
        self.assertEqual(result.returncode, 2, result.stdout)

    def test_noninteractive_run_is_rejected_before_actions(self):
        result = self.run_script(mocks="")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Run this script from a terminal", result.stdout)
        self.assertEqual(self.recorded(), [])

    def test_help_works_without_a_terminal(self):
        result = self.run_script(invocation="main --help", mocks="")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("usage:", result.stdout)
        self.assertEqual(self.recorded(), [])


if __name__ == "__main__":
    unittest.main()
