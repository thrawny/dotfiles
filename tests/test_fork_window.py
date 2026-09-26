"""Fork routing without opening terminals or starting paid model turns."""

import importlib.util
import io
import json
import shlex
import subprocess
import sys
from importlib.machinery import SourceFileLoader
from pathlib import Path
from types import ModuleType
from unittest.mock import patch

import pytest

ROOT = Path(__file__).resolve().parents[1]
SESSION = "12345678-1234-4123-8123-123456789abc"


def identity(name: str) -> str:
    return name


def fake_binary(name: str) -> str:
    return f"/bin/{name}"


@pytest.fixture
def fork() -> ModuleType:
    loader = SourceFileLoader("fork_window", str(ROOT / "bin/fork-window"))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


@pytest.fixture(autouse=True)
def clean_environment():
    with patch.dict("os.environ", {}, clear=True):
        yield


@pytest.mark.parametrize("harness", ["pi", "claude", "codex"])
def test_requires_exact_session(fork: ModuleType, harness: str):
    with pytest.raises(fork.ForkError, match="exact session"):
        fork.session_ref(harness, None)


@pytest.mark.parametrize(
    "harness,variable", [("claude", "CLAUDE_SESSION_ID"), ("codex", "CODEX_THREAD_ID")]
)
def test_session_environment(fork: ModuleType, harness: str, variable: str):
    with patch.dict("os.environ", {variable: SESSION}):
        assert fork.session_ref(harness, None) == SESSION
        with pytest.raises(fork.ForkError, match="full session UUID"):
            fork.session_ref(harness, "--last")


def test_pi_file(fork: ModuleType, tmp_path: Path):
    file = tmp_path / "session.jsonl"
    file.write_text('{"type":"session"}\n')
    assert fork.session_ref("pi", str(file)) == str(file)
    with pytest.raises(fork.ForkError, match="does not exist"):
        fork.session_ref("pi", str(tmp_path / "missing.jsonl"))


@pytest.mark.parametrize(
    "harness,flags",
    [
        ("pi", ["--fork", SESSION, "--"]),
        ("claude", ["--resume", SESSION, "--fork-session"]),
        ("codex", ["fork", SESSION]),
    ],
)
def test_native_fork_and_notice(fork: ModuleType, harness: str, flags: list[str]):
    with patch.object(fork.shutil, "which", side_effect=fake_binary):
        command = fork.fork_command(harness, SESSION)
    assert command[:7] == [
        "/bin/env",
        "-u",
        "CLAUDECODE",
        "-u",
        "CLAUDE_SESSION_ID",
        "-u",
        "CODEX_THREAD_ID",
    ]
    assert command[7:-1] == [f"/bin/{harness}", *flags]
    assert "wait for the user's next" in command[-1]
    assert "Do not run tools" in command[-1]
    assert "original session remains active" in command[-1]
    assert f"Source session: {SESSION}" in command[-1]


def test_herdr_precedes_hypr_and_quotes_once(fork: ModuleType, tmp_path: Path):
    command = [
        "/bin/pi",
        "--fork",
        "/some path/'session.jsonl",
        "$(touch /tmp/nope)\nnotice",
    ]
    response = json.dumps({"result": {"root_pane": {"pane_id": "w3:p99"}}})
    with (
        patch.dict(
            "os.environ",
            {
                "HERDR_ENV": "1",
                "HERDR_WORKSPACE_ID": "w3",
                "HYPRLAND_INSTANCE_SIGNATURE": "active",
            },
        ),
        patch.object(fork, "executable", side_effect=identity),
        patch.object(fork, "run", side_effect=[response, ""]) as run,
    ):
        assert "w3:p99" in fork.launch(command, tmp_path)
    assert run.call_args_list[0].args == (
        [
            "herdr",
            "tab",
            "create",
            "--workspace",
            "w3",
            "--cwd",
            str(tmp_path),
            "--focus",
        ],
        tmp_path,
    )
    launch_args = run.call_args_list[1].args[0]
    assert launch_args[:4] == ["herdr", "pane", "run", "w3:p99"]
    assert shlex.split(launch_args[4]) == command


def test_hypr_uses_ghostty_argv(fork: ModuleType, tmp_path: Path):
    command = ["codex", "fork", SESSION, "notice\n'quoted'"]
    with (
        patch.dict("os.environ", {"HYPRLAND_INSTANCE_SIGNATURE": "active"}),
        patch.object(fork, "executable", side_effect=identity),
        patch.object(fork, "run") as run,
    ):
        assert "Ghostty" in fork.launch(command, tmp_path)
    run.assert_called_once_with(
        ["ghostty", "+new-window", f"--working-directory={tmp_path}", "-e", *command],
        tmp_path,
    )


def test_missing_desktop(fork: ModuleType, tmp_path: Path):
    with pytest.raises(fork.ForkError, match="Herdr or a Hyprland"):
        fork.launch(["pi"], tmp_path)


def test_missing_workspace_does_not_fall_back(fork: ModuleType, tmp_path: Path):
    with patch.dict(
        "os.environ", {"HERDR_ENV": "1", "HYPRLAND_INSTANCE_SIGNATURE": "active"}
    ):
        with pytest.raises(fork.ForkError, match="caller workspace"):
            fork.launch(["pi"], tmp_path)


@pytest.mark.parametrize(
    "response", ["not json", "{}", '{"result":{"root_pane":{"pane_id":null}}}']
)
def test_malformed_herdr_response(fork: ModuleType, tmp_path: Path, response: str):
    with (
        patch.dict("os.environ", {"HERDR_ENV": "1", "HERDR_WORKSPACE_ID": "w3"}),
        patch.object(fork, "executable", side_effect=identity),
        patch.object(fork, "run", return_value=response) as run,
        pytest.raises(fork.ForkError, match="inspect it before retrying"),
    ):
        fork.launch(["pi"], tmp_path)
    assert run.call_count == 1


def test_failed_pane_run_retains_destination(fork: ModuleType, tmp_path: Path):
    response = json.dumps({"result": {"root_pane": {"pane_id": "w3:p99"}}})
    with (
        patch.dict("os.environ", {"HERDR_ENV": "1", "HERDR_WORKSPACE_ID": "w3"}),
        patch.object(fork, "executable", side_effect=identity),
        patch.object(
            fork, "run", side_effect=[response, fork.ForkError("broken")]
        ) as run,
        pytest.raises(fork.ForkError, match="w3:p99.*not confirmed"),
    ):
        fork.launch(["pi"], tmp_path)
    assert run.call_count == 2


def test_command_error(fork: ModuleType, tmp_path: Path):
    with (
        patch.object(
            fork.subprocess,
            "run",
            return_value=subprocess.CompletedProcess(
                ["herdr"], 1, "", "server unavailable"
            ),
        ),
        pytest.raises(fork.ForkError, match="server unavailable"),
    ):
        fork.run(["herdr"], tmp_path)


def test_sandbox_fails_before_launch(fork: ModuleType):
    with (
        patch.dict("os.environ", {"SANDBOX": "1"}),
        patch("sys.argv", ["fork-window", "codex", SESSION]),
        patch.object(fork, "launch") as launch,
    ):
        assert fork.main() == 1
    launch.assert_not_called()


@pytest.mark.parametrize(
    "harness,variable", [("claude", "CLAUDE_SESSION_ID"), ("codex", "CODEX_THREAD_ID")]
)
def test_auto_detect(fork: ModuleType, harness: str, variable: str):
    with patch.dict("os.environ", {variable: SESSION}):
        assert fork.detect_harness() == harness


def test_auto_detect_missing(fork: ModuleType):
    with pytest.raises(fork.ForkError, match="No current session ID"):
        fork.detect_harness()


def test_auto_detect_ambiguous(fork: ModuleType):
    with patch.dict(
        "os.environ", {"CLAUDE_SESSION_ID": SESSION, "CODEX_THREAD_ID": SESSION}
    ):
        with pytest.raises(fork.ForkError, match="Ambiguous"):
            fork.detect_harness()


@pytest.mark.parametrize(
    "harness,variable", [("claude", "CLAUDE_SESSION_ID"), ("codex", "CODEX_THREAD_ID")]
)
def test_no_argument_cli(fork: ModuleType, harness: str, variable: str):
    with (
        patch.dict("os.environ", {variable: SESSION}),
        patch("sys.argv", ["fork-window"]),
        patch.object(fork, "fork_command", return_value=["native-fork"]) as command,
        patch.object(fork, "launch", return_value="Launched") as launch,
    ):
        assert fork.main() == 0
    command.assert_called_once_with(harness, SESSION)
    launch.assert_called_once()


def test_explicit_harness_overrides_ambiguous_environment(fork: ModuleType):
    with (
        patch.dict(
            "os.environ", {"CLAUDE_SESSION_ID": SESSION, "CODEX_THREAD_ID": SESSION}
        ),
        patch("sys.argv", ["fork-window", "codex"]),
        patch.object(fork, "fork_command", return_value=["native-fork"]) as command,
        patch.object(fork, "launch", return_value="Launched"),
    ):
        assert fork.main() == 0
    command.assert_called_once_with("codex", SESSION)


def test_claude_hook_appends_exact_id(fork: ModuleType, tmp_path: Path):
    env_file = tmp_path / "shell env.sh"
    env_file.write_text("export EXISTING=value\n")
    with (
        patch.dict(
            "os.environ",
            {"CLAUDE_ENV_FILE": str(env_file), "CLAUDE_SESSION_ID": "stale-parent-id"},
        ),
        patch("sys.stdin", io.StringIO(json.dumps({"session_id": SESSION}))),
    ):
        fork.claude_session_start()
    assert (
        env_file.read_text()
        == f"export EXISTING=value\n\nexport CLAUDE_SESSION_ID={SESSION}\n"
    )


@pytest.mark.parametrize(
    "payload",
    [
        "not json",
        "{}",
        "[]",
        "null",
        '{"session_id":12}',
        '{"session_id":"$(touch /tmp/nope)"}',
    ],
)
def test_claude_hook_rejects_invalid_payload(
    fork: ModuleType, tmp_path: Path, payload: str
):
    env_file = tmp_path / "env.sh"
    with (
        patch.dict("os.environ", {"CLAUDE_ENV_FILE": str(env_file)}),
        patch("sys.stdin", io.StringIO(payload)),
        pytest.raises(fork.ForkError, match="valid session_id UUID"),
    ):
        fork.claude_session_start()
    assert not env_file.exists()


def test_claude_hook_without_env_file(fork: ModuleType):
    with patch("sys.stdin", io.StringIO("")):
        fork.claude_session_start()


def test_hook_entry_point(tmp_path: Path):
    env_file = tmp_path / "env.sh"
    result = subprocess.run(
        [sys.executable, str(ROOT / "bin/fork-window"), "--claude-session-start"],
        input=json.dumps({"session_id": SESSION}),
        env={"CLAUDE_ENV_FILE": str(env_file), "SANDBOX": "1"},
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    assert result.stdout == ""
    assert f"export CLAUDE_SESSION_ID={SESSION}" in env_file.read_text()


def test_example_config_installs_hook():
    settings = json.loads((ROOT / "config/claude/settings.example.json").read_text())
    commands = [
        hook["command"]
        for group in settings["hooks"]["SessionStart"]
        for hook in group["hooks"]
    ]
    assert "fork-window --claude-session-start" in commands
    assert any("agent-switch track session-start" in command for command in commands)


def test_missing_executable(fork: ModuleType):
    with patch.object(fork.shutil, "which", return_value=None):
        with pytest.raises(fork.ForkError, match="not found"):
            fork.fork_command("codex", SESSION)
