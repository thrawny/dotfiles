"""Repo lookup and agent naming without Herdr or model turns."""

import importlib.util
import os
import subprocess
from importlib.machinery import SourceFileLoader
from pathlib import Path
from types import ModuleType
from unittest.mock import patch

import pytest

ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def spawn() -> ModuleType:
    loader = SourceFileLoader("spawn_session", str(ROOT / "bin/spawn-session"))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


@pytest.fixture(autouse=True)
def clean_environment():
    with patch.dict("os.environ", {"PATH": os.environ["PATH"]}, clear=True):
        yield


def git_repo(path: Path) -> Path:
    path.mkdir(parents=True)
    subprocess.run(["git", "init", "-q", str(path)], check=True)
    return path.resolve()


def test_repo_by_name_under_code_dir(spawn: ModuleType, tmp_path: Path):
    repo = git_repo(tmp_path / "widgets")
    with patch.object(spawn, "CODE_DIR", tmp_path):
        assert spawn.resolve_repo("widgets") == repo
        with pytest.raises(spawn.SpawnError, match="not found"):
            spawn.resolve_repo("missing")


def test_repo_by_path_resolves_to_toplevel(spawn: ModuleType, tmp_path: Path):
    repo = git_repo(tmp_path / "widgets")
    (repo / "src").mkdir()
    assert spawn.resolve_repo(str(repo / "src")) == repo


def test_repo_must_be_git(spawn: ModuleType, tmp_path: Path):
    with pytest.raises(spawn.SpawnError, match="Not a git repository"):
        spawn.resolve_repo(str(tmp_path))


def test_agent_name_is_sanitized_and_unique(spawn: ModuleType):
    agents = {"agents": [{"name": "abc-123-retry"}, {"name": "abc-123-retry-2"}, {}]}
    with patch.object(spawn, "herdr", return_value=agents):
        assert spawn.agent_name(None, "ABC-123/Retry") == "abc-123-retry-3"
        assert spawn.agent_name(None, "2fa") == "agent-2fa"


def test_requested_agent_name_is_validated(spawn: ModuleType):
    assert spawn.agent_name("reviewer", "ignored") == "reviewer"
    with pytest.raises(spawn.SpawnError, match="must match"):
        spawn.agent_name("Bad Name", "ignored")


def test_title_becomes_the_claude_session_name(spawn: ModuleType):
    assert spawn.title_args(None, "codex", False) == []
    assert spawn.title_args("ABC-123 summary", "claude", False) == [
        "--name",
        "ABC-123 summary",
    ]
    assert spawn.title_args("fix retry timeouts", "claude", False) == [
        "--name",
        "fix retry timeouts",
    ]
    for bad in ("Fix retry", "one two three four", "two  spaces", " lead", ""):
        with pytest.raises(spawn.SpawnError, match="one to three"):
            spawn.title_args(bad, "claude", False)
    with pytest.raises(spawn.SpawnError, match="--kind claude"):
        spawn.title_args("ABC-123 summary", "codex", False)
    # A resumed session keeps a name the user gave it by hand.
    assert spawn.title_args("Widgets-001 API rebuild", "claude", True) == [
        "--name",
        "Widgets-001 API rebuild",
    ]


def test_resume_passes_the_session_id(spawn: ModuleType):
    session = "01234567-89ab-cdef-0123-456789abcdef"
    assert spawn.resume_args(None, "codex") == []
    assert spawn.resume_args(session, "claude") == ["--resume", session]
    with pytest.raises(spawn.SpawnError, match="Not a Claude session id"):
        spawn.resume_args("latest", "claude")
    with pytest.raises(spawn.SpawnError, match="--kind claude"):
        spawn.resume_args(session, "codex")


def test_model_and_effort_pass_through_to_claude(spawn: ModuleType):
    assert spawn.model_args(None, None, "codex") == []
    assert spawn.model_args("sonnet", "low", "claude") == [
        "--model",
        "sonnet",
        "--effort",
        "low",
    ]
    assert spawn.model_args("claude-opus-5-5[1m]", None, "claude") == [
        "--model",
        "claude-opus-5-5[1m]",
    ]
    with pytest.raises(spawn.SpawnError, match="Not a Claude model"):
        spawn.model_args("--dangerous", None, "claude")
    with pytest.raises(spawn.SpawnError, match="Effort must be"):
        spawn.model_args(None, "turbo", "claude")
    with pytest.raises(spawn.SpawnError, match="--kind claude"):
        spawn.model_args("sonnet", None, "codex")


STALLED = '{"error":{"code":"agent_prompt_stalled","message":"no working state"}}'
TIMEOUT = '{"error":{"code":"timeout","message":"timed out waiting for agent status"}}'
RULE = "─" * 40


def screen(box: str) -> str:
    return f"⏺ earlier output\n{RULE} review ─\n❯ {box}\n{RULE}\n  Opus │ main\n"


def test_prompt_box_reads_the_text_between_the_last_rules(spawn: ModuleType):
    stuck = screen("[Pasted text #1 +20 lines]last line of the brief\n  claude")
    assert (
        spawn.prompt_box(stuck)
        == "[Pasted text #1 +20 lines]last line of the brief\nclaude"
    )
    assert spawn.prompt_box(screen("")) == ""
    assert spawn.prompt_box("Do you trust this folder?\n") is None


def fake_herdr(spawn: ModuleType, waits: list[str | None], box: str):
    """Fakes for herdr and herdr_text: the prompt stalls, then each wait gives the next outcome."""
    sent: list[tuple[str, ...]] = []

    def herdr(*args: str, **_: object) -> dict[str, object]:
        if args[:2] == ("agent", "prompt"):
            raise spawn.SpawnError(STALLED)
        outcome = waits.pop(0)
        if outcome:
            raise spawn.SpawnError(outcome)
        return {}

    def herdr_text(*args: str, **_: object) -> str:
        if args[:2] == ("pane", "read"):
            return screen(box)
        sent.append(args[1:])
        return ""

    return (
        patch.object(spawn, "herdr", side_effect=herdr),
        patch.object(spawn, "herdr_text", side_effect=herdr_text),
        sent,
    )


def test_stalled_brief_is_submitted_by_closing_the_paste(spawn: ModuleType):
    fake, fake_text, sent = fake_herdr(
        spawn, [TIMEOUT, None], "[Pasted text #1 +20 lines]"
    )
    with fake, fake_text:
        spawn.submit_brief("abc-1", "w1:p1", "the brief")
    end_and_enter = [
        ("send-text", "w1:p1", "\x1b[201~"),
        ("send-keys", "w1:p1", "enter"),
    ]
    assert sent == end_and_enter * 2


def test_stalled_brief_gives_up_and_says_where_it_is(spawn: ModuleType):
    fake, fake_text, sent = fake_herdr(
        spawn, [TIMEOUT] * 3, "[Pasted text #1 +20 lines]"
    )
    with fake, fake_text, pytest.raises(spawn.SpawnError, match="sits unsent"):
        spawn.submit_brief("abc-1", "w1:p1", "the brief")
    assert len(sent) == 2 * spawn.SUBMIT_TRIES


def test_stalled_prompt_with_an_empty_box_presses_nothing(spawn: ModuleType):
    fake, fake_text, sent = fake_herdr(spawn, [], "")
    with fake, fake_text, pytest.raises(spawn.SpawnError, match="empty input box"):
        spawn.submit_brief("abc-1", "w1:p1", "the brief")
    assert sent == []
