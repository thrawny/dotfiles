"""Repo lookup and agent naming without Herdr or model turns."""

import importlib.util
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
    with patch.dict("os.environ", {}, clear=True):
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
    assert spawn.title_args(None, "codex") == []
    assert spawn.title_args("ABC-123 summary", "claude") == [
        "--name",
        "ABC-123 summary",
    ]
    assert spawn.title_args("fix retry timeouts", "claude") == [
        "--name",
        "fix retry timeouts",
    ]
    for bad in ("Fix retry", "one two three four", "two  spaces", " lead", ""):
        with pytest.raises(spawn.SpawnError, match="one to three"):
            spawn.title_args(bad, "claude")
    with pytest.raises(spawn.SpawnError, match="--kind claude"):
        spawn.title_args("ABC-123 summary", "codex")


def test_agent_args_follow_a_separator(spawn: ModuleType):
    with patch.object(spawn, "herdr") as herdr:
        spawn.start_agent("abc-1", "claude", "w1:p1", ["--name", "ABC-1 fix"])
    assert herdr.call_args.args[-3:] == ("--", "--name", "ABC-1 fix")


def test_resume_passes_the_session_id(spawn: ModuleType):
    session = "01234567-89ab-cdef-0123-456789abcdef"
    assert spawn.resume_args(None, "codex") == []
    assert spawn.resume_args(session, "claude") == ["--resume", session]
    with pytest.raises(spawn.SpawnError, match="Not a Claude session id"):
        spawn.resume_args("latest", "claude")
    with pytest.raises(spawn.SpawnError, match="--kind claude"):
        spawn.resume_args(session, "codex")


def test_new_worktree_goes_to_the_path_asked_for(spawn: ModuleType, tmp_path: Path):
    pane = {"pane_id": "w1:p1", "cwd": str(tmp_path / "wt")}
    replies: dict[str, dict[str, object]] = {
        "list": {"worktrees": []},
        "create": {"root_pane": pane},
    }

    def herdr(*args: str, **_: object) -> dict[str, object]:
        return replies[args[1]]

    with (
        patch.object(spawn, "herdr", side_effect=herdr) as fake,
        patch.object(spawn, "copy_local_files"),
    ):
        spawn.worktree_pane(tmp_path, "ABC-1-fix", "origin/main", str(tmp_path / "wt"))
    create = fake.call_args_list[1].args
    assert create[create.index("--path") + 1] == str(tmp_path / "wt")
