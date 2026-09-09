"""Test walkthrough decisions without installing software or touching the host home."""

import os
import subprocess
from collections.abc import Sequence
from pathlib import Path

import pytest

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


class Walkthrough:
    root: Path
    home: Path
    repo: Path
    events: Path
    fixture: Path
    environment: dict[str, str]

    def __init__(self, root: Path):
        self.root = root.resolve()
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
                '#!/usr/bin/env bash\nset -eu\nprintf "%s %s\\n" "${0##*/}" "$*" >> "$EVENT_LOG"\n'
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

    def git(self, *args: str):
        return subprocess.check_output(
            ["git", *args], env=self.environment, stderr=subprocess.STDOUT
        )

    def run_script(
        self,
        answers: Sequence[str] = (),
        invocation: str = "main",
        mocks: str = MOCKS,
        updates: dict[str, str] | None = None,
    ):
        return subprocess.run(
            ["bash", "-c", 'source "$BOOTSTRAP"\n' + mocks + "\n" + invocation],
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


@pytest.fixture
def walkthrough(tmp_path: Path) -> Walkthrough:
    return Walkthrough(tmp_path)


def test_existing_homebrew_and_checkout_then_repeat(walkthrough: Walkthrough):
    local_edit = walkthrough.repo / "keep-me"
    local_edit.write_text("uncommitted")
    for _ in range(2):
        result = walkthrough.run_script(["y", "y", *walkthrough.remaining_answers()])
        assert result.returncode == 0, result.stdout
    assert local_edit.read_text() == "uncommitted"
    assert "clone" not in walkthrough.recorded()
    assert "install-homebrew" not in walkthrough.recorded()
    assert walkthrough.recorded().count("install-macos-packages ") == 2
    assert "brew bundle check --file Brewfile" in walkthrough.recorded()
    assert "apply-macos-defaults " not in walkthrough.recorded()


def test_missing_homebrew_can_be_installed(walkthrough: Walkthrough):
    result = walkthrough.run_script(
        ["y", "y", "y", *walkthrough.remaining_answers()],
        updates={"TEST_BREW_READY": "0"},
    )
    assert result.returncode == 0, result.stdout
    assert "install-homebrew" in walkthrough.recorded()
    assert "install-macos-packages " in walkthrough.recorded()


def test_missing_homebrew_can_be_deferred_while_linking(walkthrough: Walkthrough):
    result = walkthrough.run_script(
        ["n", "y", *walkthrough.remaining_answers()],
        updates={"TEST_BREW_READY": "0"},
    )
    assert result.returncode == 0, result.stdout
    assert "setup-macos " in walkthrough.recorded()
    assert "install-macos-packages " not in walkthrough.recorded()
    assert "install-homebrew" not in walkthrough.recorded()
    assert "finished with deferred steps" in result.stdout


def test_conflicts_require_explicit_backup_choice(walkthrough: Walkthrough):
    result = walkthrough.run_script(
        ["y", "n", *walkthrough.remaining_answers()], updates={"TEST_CONFLICT": "1"}
    )
    assert result.returncode == 0, result.stdout
    assert "setup-macos --force" not in walkthrough.recorded()
    assert "install-macos-packages " not in walkthrough.recorded()
    result = walkthrough.run_script(
        ["y", "y", "y", *walkthrough.remaining_answers()],
        updates={"TEST_CONFLICT": "1"},
    )
    assert result.returncode == 0, result.stdout
    assert "setup-macos --force" in walkthrough.recorded()
    assert "install-macos-packages " in walkthrough.recorded()


def test_declining_links_also_defers_packages(walkthrough: Walkthrough):
    result = walkthrough.run_script(["n", *walkthrough.remaining_answers()])
    assert result.returncode == 0, result.stdout
    assert "setup-macos " not in walkthrough.recorded()
    assert "install-macos-packages " not in walkthrough.recorded()


def test_package_failure_stops_before_preferences_and_verification(
    walkthrough: Walkthrough,
):
    result = walkthrough.run_script(["y", "y"], updates={"TEST_PACKAGE_EXIT": "23"})
    assert result.returncode == 23, result.stdout
    assert "Stopped during: Packages and plugins" in result.stdout
    assert "check-macos " not in walkthrough.recorded()
    assert "Walkthrough finished" not in result.stdout


def test_failed_verification_exits_nonzero(walkthrough: Walkthrough):
    result = walkthrough.run_script(
        ["y", "y", *walkthrough.remaining_answers()], updates={"TEST_CHECK_EXIT": "1"}
    )
    assert result.returncode == 1, result.stdout
    assert "Verification found problems" in result.stdout
    assert "brew bundle check --file Brewfile" in walkthrough.recorded()


def test_eof_and_quit_do_not_apply_configuration(walkthrough: Walkthrough):
    for answers in ([], ["q"]):
        result = walkthrough.run_script(answers)
        assert result.returncode == 130, result.stdout
    assert "setup-macos " not in walkthrough.recorded()


def test_identity_is_local_and_preserves_other_settings(walkthrough: Walkthrough):
    identity = walkthrough.home / ".gitconfig.local"
    identity.write_text("[core]\n  editor = nano\n")
    result = walkthrough.run_script(
        ["y", "n", "y", "Test Person", "person@example.com", *["n"] * 6]
    )
    assert result.returncode == 0, result.stdout
    assert "editor = nano" in identity.read_text()
    assert "name = Test Person" in identity.read_text()
    assert "email = person@example.com" in identity.read_text()


def test_wrong_branch_is_left_untouched(walkthrough: Walkthrough):
    walkthrough.git("-C", str(walkthrough.repo), "checkout", "-qb", "other")
    result = walkthrough.run_script()
    assert result.returncode == 1, result.stdout
    assert "Switch it to without-nix" in result.stdout
    assert walkthrough.recorded() == []


def test_absent_checkout_is_cloned(walkthrough: Walkthrough):
    walkthrough.repo.rename(walkthrough.home / "previous-checkout")
    result = walkthrough.run_script(["y", "y", "y", *walkthrough.remaining_answers()])
    assert result.returncode == 0, result.stdout
    assert "clone" in walkthrough.recorded()


def test_unrelated_directory_is_not_replaced(walkthrough: Walkthrough):
    walkthrough.repo.rename(walkthrough.home / "previous-checkout")
    walkthrough.repo.mkdir()
    marker = walkthrough.repo / "keep-me"
    marker.write_text("original")
    result = walkthrough.run_script()
    assert result.returncode == 1, result.stdout
    assert marker.read_text() == "original"
    assert "clone" not in walkthrough.recorded()


def test_homebrew_download_failure_is_reported_and_cleaned_up(
    walkthrough: Walkthrough,
):
    result = walkthrough.run_script(
        invocation="""
stage=Homebrew
installer_file=''
trap finish EXIT
curl() { printf '%s' "$4" > "$EVENT_LOG"; return 22; }
install_homebrew
""",
        # The production script uses BSD mktemp -t; keep this cleanup test
        # portable without changing the macOS installer itself.
        mocks='mktemp() { command mktemp "$HOME/installer.XXXXXX"; }',
    )
    assert result.returncode == 22, result.stdout
    assert "Stopped during: Homebrew" in result.stdout
    assert not Path(walkthrough.events.read_text()).exists()


def test_developer_tools_can_be_installed_before_cloning(walkthrough: Walkthrough):
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
    result = walkthrough.run_script(
        ["y", "y", "y", *walkthrough.remaining_answers()], mocks=mocks
    )
    assert result.returncode == 0, result.stdout
    assert walkthrough.recorded()[0] == "install-developer-tools"


def test_apps_agents_and_preferences_only_run_when_chosen(walkthrough: Walkthrough):
    mocks = (
        MOCKS
        + r"""
open() { [[ $1 == -Ra ]] || record "open $*"; }
"""
    )
    result = walkthrough.run_script(
        ["y", "y", "n", *["y"] * 6, "n", "y", "n"], mocks=mocks
    )
    assert result.returncode == 0, result.stdout
    for event in (
        "claude",
        "codex",
        "pi",
        "nvim",
        "open -a Ghostty",
        "open -a AeroSpace",
        "apply-macos-defaults ",
    ):
        assert event in walkthrough.recorded()
    assert "killall Finder Dock" not in walkthrough.recorded()


def test_platform_guard_rejects_root_and_intel(walkthrough: Walkthrough):
    for mocks in (
        "id() { echo 0; }",
        "id() { echo 501; }; uname() { echo x86_64; }",
    ):
        result = walkthrough.run_script(invocation="check_platform", mocks=mocks)
        assert result.returncode == 1, result.stdout
    assert walkthrough.recorded() == []


def test_extra_arguments_are_rejected(walkthrough: Walkthrough):
    result = walkthrough.run_script(invocation="main --help extra", mocks="")
    assert result.returncode == 2, result.stdout


def test_noninteractive_run_is_rejected_before_actions(walkthrough: Walkthrough):
    result = walkthrough.run_script(mocks="")
    assert result.returncode != 0
    assert "Run this script from a terminal" in result.stdout
    assert walkthrough.recorded() == []


def test_help_works_without_a_terminal(walkthrough: Walkthrough):
    result = walkthrough.run_script(invocation="main --help", mocks="")
    assert result.returncode == 0, result.stdout
    assert "usage:" in result.stdout
    assert walkthrough.recorded() == []
