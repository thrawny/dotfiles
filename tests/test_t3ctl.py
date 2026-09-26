"""T3 Code HTTP commands, token lifecycle, and SSH argument boundaries."""

import argparse
import io
import json
import runpy
import shlex
import subprocess
from pathlib import Path
from types import SimpleNamespace
from typing import Any
from unittest.mock import MagicMock

import pytest

SCRIPT = Path(__file__).resolve().parents[1] / "bin/t3ctl"
cli = SimpleNamespace(**runpy.run_path(str(SCRIPT), run_name="t3ctl_test"))


def parse(*args: str) -> argparse.Namespace:
    return cli.parser().parse_args(args)


def project() -> dict[str, Any]:
    return {
        "id": "p1",
        "title": "repo",
        "workspaceRoot": "/srv/repo",
        "defaultModelSelection": None,
    }


def thread() -> dict[str, Any]:
    return {
        "id": "t1",
        "projectId": "p1",
        "modelSelection": {"instanceId": "claudeAgent", "model": "claude-opus-5"},
        "runtimeMode": "approval-required",
        "interactionMode": "plan",
        "session": {"status": "ready"},
        "messages": [{"id": "m1", "role": "user", "turnId": "turn1"}],
        "latestTurn": {"turnId": "turn1", "state": "completed"},
    }


def fake_api(t: dict[str, Any] | None = None) -> Any:
    api = MagicMock()
    api.shell.return_value = {"projects": [project()], "threads": [t or thread()]}
    api.thread.return_value = t or thread()
    api.dispatch.return_value = {"sequence": 42}
    return api


def test_start_has_distinct_ids_and_safe_permissions():
    api = fake_api()
    receipt = cli.start(api, parse("start", "repo", "hello", "--model", "gpt-6-sol"))
    create, turn = [call.args[0] for call in api.dispatch.call_args_list]
    assert create["type"] == "thread.create"
    assert create["runtimeMode"] == "approval-required"
    assert create["worktreePath"] is None
    assert create["modelSelection"] == {"instanceId": "codex", "model": "gpt-6-sol"}
    assert turn["threadId"] == create["threadId"] == receipt["threadId"]
    assert turn["message"]["messageId"] == receipt["messageId"]
    assert receipt["messageId"] != receipt["commandId"]
    assert receipt["sequence"] == 42


def test_start_requires_model_before_mutating():
    api = fake_api()
    with pytest.raises(cli.CliError, match="no model default"):
        cli.start(api, parse("start", "repo", "hello"))
    api.dispatch.assert_not_called()


def test_provider_without_model_is_rejected():
    api = fake_api()
    with pytest.raises(cli.CliError, match="--provider requires --model"):
        cli.start(api, parse("start", "repo", "hello", "--provider", "claudeAgent"))
    api.dispatch.assert_not_called()


def test_wait_with_null_turn_id_does_not_accept_previous_completion(
    monkeypatch: pytest.MonkeyPatch,
):
    t = thread()
    t["messages"][0].update(turnId=None, createdAt="2026-09-23T12:01:00Z")
    t["latestTurn"]["requestedAt"] = "2026-09-23T12:00:00Z"
    clock = iter([0, 2])
    monkeypatch.setattr(cli.time, "monotonic", lambda: next(clock))
    value, code = cli.wait_for_turn(
        fake_api(t), parse("wait", "t1", "--message-id", "m1", "--timeout", "1")
    )
    assert value["state"] == "timeout"
    assert code == 124


def test_start_retains_thread_on_uncertain_delivery():
    api = fake_api()
    api.dispatch.side_effect = [{"sequence": 1}, cli.CliError("disconnected")]
    with pytest.raises(cli.CliError, match="inspect it before retrying"):
        cli.start(api, parse("start", "repo", "hello", "--model", "gpt-6-sol"))
    assert api.dispatch.call_count == 2


def test_send_preserves_model_and_modes():
    api = fake_api()
    cli.execute(api, parse("send", "t1", "follow up"))
    command = api.dispatch.call_args.args[0]
    assert command["modelSelection"] == thread()["modelSelection"]
    assert command["runtimeMode"] == "approval-required"
    assert command["interactionMode"] == "plan"


@pytest.mark.parametrize(
    "changes",
    [
        {"session": {"status": "starting"}},
        {"latestTurn": {"state": "running"}},
        {"hasPendingApprovals": True},
        {"hasPendingUserInput": True},
        {"backgroundLiveness": "monitoring"},
        {"archivedAt": "2026-01-01T00:00:00Z"},
    ],
)
def test_send_refuses_busy_blocked_and_archived(changes: dict[str, Any]):
    api = fake_api({**thread(), **changes})
    with pytest.raises(cli.CliError):
        cli.execute(api, parse("send", "t1", "follow up"))
    api.dispatch.assert_not_called()


def test_stdin_and_empty_prompts(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setattr(cli.sys, "stdin", io.StringIO("multiline\nprompt\n"))
    assert cli.prompt_text("-") == "multiline\nprompt\n"
    with pytest.raises(cli.CliError, match="empty"):
        cli.prompt_text("  ")


def test_ambiguous_project():
    snapshot = {
        "projects": [
            project(),
            {**project(), "id": "p2", "workspaceRoot": "/elsewhere"},
        ]
    }
    with pytest.raises(cli.CliError, match="ambiguous"):
        cli.resolve_project(snapshot, "repo")
    assert cli.resolve_project(snapshot, "p1")["id"] == "p1"


@pytest.mark.parametrize(
    ("state", "code"), [("completed", 0), ("error", 1), ("interrupted", 1)]
)
def test_wait_terminal_states(state: str, code: int):
    api = fake_api({**thread(), "latestTurn": {"turnId": "turn1", "state": state}})
    value, exit_code = cli.wait_for_turn(api, parse("wait", "t1", "--message-id", "m1"))
    assert value["state"] == state
    assert exit_code == code


def test_wait_does_not_accept_previous_completion(monkeypatch: pytest.MonkeyPatch):
    api = fake_api()
    clock = iter([0, 2, 3])
    monkeypatch.setattr(cli.time, "monotonic", lambda: next(clock))
    value, code = cli.wait_for_turn(
        api, parse("wait", "t1", "--message-id", "new-message", "--timeout", "1")
    )
    assert value["state"] == "timeout"
    assert code == 124


def test_wait_reports_pending_input():
    api = fake_api({**thread(), "hasPendingApprovals": True})
    value, code = cli.wait_for_turn(api, parse("wait", "t1"))
    assert value["state"] == "blocked"
    assert code == 2


def test_dispatch_preserves_supplied_id():
    api = cli.Api(3773, "fake-token")
    api.request = MagicMock(return_value={"sequence": 2})
    command = {"type": "thread.archive", "threadId": "t1", "commandId": "retry-id"}
    api.dispatch(command)
    assert api.request.call_args.args[1]["commandId"] == "retry-id"


def test_token_revoked_on_failure(monkeypatch: pytest.MonkeyPatch):
    run = MagicMock(
        return_value=subprocess.CompletedProcess(
            [], 0, json.dumps({"token": "test-token", "sessionId": "s1"})
        )
    )
    monkeypatch.setattr(cli.subprocess, "run", run)
    with pytest.raises(cli.CliError):
        with cli.authenticated_api(parse("projects")):
            raise cli.CliError("test failure")
    assert run.call_count == 2
    assert "revoke" in run.call_args.args[0]
    assert run.call_args.args[0][-1] == "s1"
    assert "test-token" not in str(run.call_args_list)


def test_ssh_quotes_prompt_without_shell_interpretation():
    prompt = "hello ' ; $(touch /tmp/should-not-exist)\nworld"
    argv = ["start", "repo", prompt, "--model", "gpt-6-sol"]
    command = cli.remote_command(parse(*argv), argv)
    assert command[-2] == "root@obelisk"
    remote = shlex.split(command[-1])
    assert remote[-len(argv) :] == argv
    assert "--local" in remote
    assert remote[:4] == ["runuser", "-u", "t3code", "--"]


def test_wait_with_v1_null_user_turn_id():
    t = thread()
    t["messages"][0].update(turnId=None, createdAt="2026-09-23T12:00:00Z")
    t["latestTurn"]["requestedAt"] = "2026-09-23T12:00:00Z"
    value, code = cli.wait_for_turn(
        fake_api(t), parse("wait", "t1", "--message-id", "m1")
    )
    assert code == 0
    assert value["state"] == "completed"


def test_wait_rejects_superseded_message():
    t = thread()
    t["messages"].append({"id": "new", "role": "user", "turnId": None})
    with pytest.raises(cli.CliError, match="superseded"):
        cli.wait_for_turn(fake_api(t), parse("wait", "t1", "--message-id", "m1"))


def test_send_refuses_a_queued_turn():
    t = thread()
    t["latestUserMessageAt"] = "2026-09-23T12:00:01Z"
    t["latestTurn"]["requestedAt"] = "2026-09-23T12:00:00Z"
    api = fake_api(t)
    with pytest.raises(cli.CliError, match="busy"):
        cli.execute(api, parse("send", "t1", "hello"))
    api.dispatch.assert_not_called()


def test_http_request_auth_payload_and_no_retry():
    api = cli.Api(3773, "test-token")
    response = MagicMock()
    response.__enter__.return_value = io.BytesIO(b'{"sequence": 5}')
    api.opener = MagicMock()
    api.opener.open.return_value = response
    assert api.dispatch({"type": "thread.archive", "threadId": "t1"}) == {"sequence": 5}
    request = api.opener.open.call_args.args[0]
    assert request.full_url == "http://127.0.0.1:3773/api/orchestration/dispatch"
    assert request.get_header("Authorization") == "Bearer test-token"
    assert json.loads(request.data)["commandId"]
    api.opener.open.reset_mock()
    api.opener.open.side_effect = OSError("disconnected")
    with pytest.raises(cli.CliError, match="outcome may be unknown"):
        api.dispatch({"type": "thread.archive", "threadId": "t1"})
    assert api.opener.open.call_count == 1


def test_redirects_are_rejected():
    with pytest.raises(cli.CliError, match="redirected"):
        cli.NoRedirect().redirect_request(
            None, None, 302, "redirect", {}, "http://elsewhere/"
        )


def test_ssh_rejects_option_as_host():
    args = parse("projects")
    args.host = "-oProxyCommand=bad"
    with pytest.raises(cli.CliError, match="Invalid SSH host"):
        cli.remote_command(args, ["projects"])
