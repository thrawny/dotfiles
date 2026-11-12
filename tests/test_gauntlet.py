"""Reviewer selection runs only the requested tools, without model invocations."""

import json
import os
import subprocess
from pathlib import Path

import pytest

LAUNCHER = (
    Path(__file__).resolve().parents[1] / "skills/gauntlet/scripts/gauntlet-review"
)


def _isolated_environment(
    tmp_path: Path, tools: Path, token_file: bool = True
) -> dict[str, str]:
    """Stub reviewers first on PATH, with a fixture token file and no host login."""
    environment = {
        key: value
        for key, value in os.environ.items()
        if not key.startswith(
            ("GAUNTLET_", "CLAUDE_CODE_OAUTH", "ANTHROPIC_", "XDG_CONFIG", "SANDBOX")
        )
    }
    environment.update(
        HOME=str(tmp_path),
        PATH=f"{tools}:{environment['PATH']}",
        GAUNTLET_STATE_DIR=str(tmp_path / "state"),
    )
    if token_file:
        path = tmp_path / ".config/gauntlet/claude-oauth-token"
        path.parent.mkdir(parents=True)
        path.write_text("fixture-token\n")
        path.chmod(0o600)
    return environment


@pytest.mark.parametrize(
    ("configured", "arguments", "expected"),
    [
        (None, [], {"claude"}),
        ("", [], {"claude"}),
        ("claude", [], {"claude"}),
        ("claude,codex", [], {"claude", "codex"}),
        ("codex", ["--reviewers", "claude"], {"claude"}),
        ("claude,codex", ["--reviewers", "codex"], {"codex"}),
        ("invalid", [], set()),
        (None, ["--base", "missing-ref"], set()),
    ],
)
def test_reviewer_selection(
    tmp_path: Path,
    configured: str | None,
    arguments: list[str],
    expected: set[str],
) -> None:
    repository = tmp_path / "repository"
    repository.mkdir()
    subprocess.run(["git", "init", "-q", str(repository)], check=True)
    tools = tmp_path / "tools"
    tools.mkdir()
    calls = tmp_path / "calls"
    calls.mkdir()
    for reviewer in ("claude", "codex"):
        stub = tools / reviewer
        stub.write_text(
            "#!/bin/sh\n"
            f'touch "$CALLS/{reviewer}"\n'
            'while [ "$#" -gt 0 ]; do\n'
            '  if [ "$1" = "-o" ]; then shift; printf "No findings\\n" > "$1"; fi\n'
            "  shift\n"
            "done\n"
            f"printf '%s\\n' '{_claude_json('No findings', True)}'\n"
        )
        stub.chmod(0o755)
    environment = _isolated_environment(tmp_path, tools)
    environment["CALLS"] = str(calls)
    if configured is not None:
        environment["GAUNTLET_REVIEWERS"] = configured
    result = subprocess.run(
        ["bash", str(LAUNCHER), "--uncommitted", *arguments, "Fixture review"],
        cwd=repository,
        env=environment,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert (result.returncode == 0) is bool(expected), result.stderr
    assert {entry.name for entry in calls.iterdir()} == expected
    assert not list((tmp_path / "state").glob("**/active.lock"))
    if arguments == ["--base", "missing-ref"]:
        followup = subprocess.run(
            ["bash", str(LAUNCHER), "--uncommitted", "Fixture review"],
            cwd=repository,
            env=environment,
            capture_output=True,
            text=True,
            timeout=10,
        )
        assert followup.returncode == 0, followup.stderr
        assert {entry.name for entry in calls.iterdir()} == {"claude"}


# Retry policy is plain-data logic; these tests use no provider calls or sleeps.
import importlib.util
import runpy

_spec = importlib.util.spec_from_file_location(
    "retry_review", LAUNCHER.with_name("retry-review.py")
)
assert _spec is not None and _spec.loader is not None
retry_review = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(retry_review)


@pytest.mark.parametrize(
    "diagnostic, expected",
    [
        ("model capacity temporarily unavailable", "transient"),
        ("429 rate limit", "transient"),
        ("connection reset", "transient"),
        ("401 temporarily unavailable", "auth"),
        ("quota exceeded 429", "quota"),
        ("invalid model", "terminal"),
        ("HTTP 403 rate limit: Retry-After: 1", "transient"),
        ("HTTP 403 Forbidden: invalid API key", "auth"),
    ],
)
def test_retry_classification(diagnostic, expected):
    assert retry_review.classify(1, diagnostic) == expected


def _claude_json(result, model_used):
    # Shape of `claude -p --output-format json`. A forked /code-review reports
    # num_turns 0 even when it ran; only modelUsage shows a model was called.
    usage = {"claude-opus-5-5": {"outputTokens": 10}} if model_used else {}
    return json.dumps(
        {
            "type": "result",
            "is_error": False,
            "num_turns": 0,
            "result": result,
            "modelUsage": usage,
        }
    )


@pytest.mark.parametrize(
    "output, expected",
    [
        (_claude_json("Not logged in · Please run /login", False), "auth"),
        (
            _claude_json(
                "Failed to authenticate. API Error: 401 Invalid bearer token", False
            ),
            "auth",
        ),
        (_claude_json("Weekly usage limit reached", False), "quota"),
        (_claude_json("a.py:1 — high — a 401 is retried as authenticated", True), "ok"),
        ("Warning: no stdin data\n" + _claude_json("Not logged in", False), "auth"),
        (_claude_json("Not logged in", False) + "\nWarning: after\n", "auth"),
        ("No findings", "terminal"),
        # Ids and timings in the object must not drive the verdict.
        (
            json.dumps(
                {
                    "is_error": True,
                    "subtype": "error_during_execution",
                    "session_id": "3f2a9c4e-1b7d-4a29-9e0f-8c4291d6b7aa",
                    "duration_ms": 40123,
                    "errors": ["invalid model"],
                    "modelUsage": {"claude-opus-5-5": {}},
                }
            ),
            "terminal",
        ),
    ],
)
def test_claude_run_that_called_no_model_is_not_a_review(output, expected):
    assert retry_review.classify(*retry_review.claude_reply(0, output)) == expected


@pytest.mark.parametrize(
    "codes, diagnostic, expected, attempts",
    [
        ([1, 0], "503 model capacity", 0, 2),
        ([1, 1, 1], "429 rate limit", 1, 3),
        ([1], "invalid API key", 1, 1),
        ([130], "temporary transport error", 1, 1),
        ([1], "429 resetAt: 9999999999", 1, 1),
    ],
)
def test_retry_outcomes(tmp_path, monkeypatch, codes, diagnostic, expected, attempts):
    monkeypatch.setattr(retry_review, "fingerprint", lambda: "exact-scope")
    remaining = iter(codes)
    waits = []

    def invoke(command, stdout, stderr):
        code = next(remaining)
        stdout.write((diagnostic if code else _claude_json("No findings", True)).encode())
        return subprocess.CompletedProcess(command, code)

    output = tmp_path / "result.out"
    result = retry_review.run(
        tmp_path,
        "claude",
        str(output),
        ["reviewer"],
        invoke=invoke,
        sleep=waits.append,
        clock=lambda: 0,
    )
    import json

    events = [
        json.loads(line)
        for line in (tmp_path / "claude.attempts.jsonl").read_text().splitlines()
    ]
    assert result == expected
    assert sum(event["state"] == "running" for event in events) == attempts
    assert output.exists() is (expected == 0)
    assert len(waits) == attempts - 1


def test_retry_scope_change_blocks(tmp_path, monkeypatch):
    scopes = iter(["before", "before", "after"])
    monkeypatch.setattr(retry_review, "fingerprint", lambda: next(scopes))

    def invoke(command, stdout, stderr):
        stdout.write(_claude_json("No findings", True).encode())
        return subprocess.CompletedProcess(command, 0)

    output = tmp_path / "result"
    assert (
        retry_review.run(tmp_path, "claude", str(output), ["reviewer"], invoke=invoke)
        == 1
    )
    assert not output.exists()


def test_codex_retry_publishes_only_success(tmp_path, monkeypatch):
    monkeypatch.setattr(retry_review, "fingerprint", lambda: "same-head-and-tree")
    answers = iter([(1, "503 capacity", "partial"), (0, "completed", "No findings")])

    def invoke(command, stdout, stderr):
        code, diagnostic, answer = next(answers)
        stdout.write(diagnostic.encode())
        Path(command[1]).write_text(answer)
        return subprocess.CompletedProcess(command, code)

    output = tmp_path / "codex.out"
    assert (
        retry_review.run(
            tmp_path,
            "codex",
            str(output),
            ["codex", str(output)],
            invoke=invoke,
            sleep=lambda _: None,
            clock=lambda: 0,
        )
        == 0
    )
    assert output.read_text() == "No findings"
    assert (tmp_path / "codex.attempt-1.out").read_text() == "partial"


@pytest.mark.parametrize(
    "state, exhausted, outcome",
    [
        ("ok", False, "review-complete"),
        ("auth", False, "blocked"),
        ("transient", True, "exhausted"),
    ],
)
def test_structured_result_fails_closed(tmp_path, state, exhausted, outcome):
    import json

    result_module = runpy.run_path(str(LAUNCHER.with_name("review-result.py")))
    (tmp_path / "meta.txt").write_text(
        "reviewers: codex\nhead_sha: exact-head\nscope: --uncommitted\nround: 2\nprior_ledger: none\n"
    )
    events = [
        dict(state="running", fingerprint=retry_review.fingerprint("--uncommitted")),
        dict(state=state, exhausted=exhausted, resetAt=123),
    ]
    (tmp_path / "codex.attempts.jsonl").write_text(
        "".join(json.dumps(e) + "\n" for e in events)
    )
    result_module["publish"](tmp_path)
    result = result_module["build"](tmp_path)
    assert result["outcome"] == outcome
    assert result["retryable"] is False
    assert result["retryBudgetExhausted"] is exhausted
    assert result["reviewers"][0]["attempts"] == 1
    if state != "ok":
        with pytest.raises(ValueError):
            result_module["build"](tmp_path, "converged")
    else:
        assert result_module["build"](tmp_path, "converged")["outcome"] == "converged"


@pytest.mark.parametrize(
    "text, expected",
    [
        ("resetAt: 2026-10-29T12:00:00+02:00", "2026-10-29T10:00:00Z"),
        ("resetAt: 2026-10-29T12:00:00", None),
        ("resetAt: invalid", None),
        ("Retry-After: 60", None),
        ("temporary capacity", None),
    ],
)
def test_provider_reset_is_absolute(text, expected):
    assert retry_review.reset_at(text) == expected


def test_successful_review_can_discuss_auth_and_quota():
    assert retry_review.classify(0, "401 authentication quota billing") == "ok"


def test_retry_deadline_rechecked_after_sleep(tmp_path, monkeypatch):
    monkeypatch.setattr(retry_review, "fingerprint", lambda: "scope")
    now = [0]
    launches = []

    def invoke(command, stdout, stderr):
        launches.append(now[0])
        stdout.write(b"503 capacity resetAt: 1970-01-01T00:01:00Z")
        return subprocess.CompletedProcess(command, 1)

    def sleep(_):
        now[0] = 400

    assert (
        retry_review.run(
            tmp_path,
            "claude",
            str(tmp_path / "out"),
            ["reviewer"],
            invoke=invoke,
            sleep=sleep,
            clock=lambda: now[0],
        )
        == 1
    )
    assert launches == [0]
    import json

    terminal = json.loads(
        (tmp_path / "claude.attempts.jsonl").read_text().splitlines()[-1]
    )
    assert terminal["exhausted"]
    assert terminal["resetAt"] == "1970-01-01T00:01:00Z"


def test_untracked_fingerprint_has_file_boundaries(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    subprocess.run(["git", "init", "-q"], check=True)
    (tmp_path / "a").write_text("x")
    (tmp_path / "b").write_text("y")
    before = retry_review.fingerprint("")
    (tmp_path / "a").write_text("xy")
    (tmp_path / "b").write_text("")
    assert retry_review.fingerprint("") != before


def test_base_ref_is_part_of_fingerprint(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    subprocess.run(["git", "init", "-q"], check=True)
    for index in range(2):
        subprocess.run(
            [
                "git",
                "-c",
                "user.name=Test",
                "-c",
                "user.email=test@example.com",
                "commit",
                "--allow-empty",
                "-qm",
                str(index),
            ],
            check=True,
        )
    subprocess.run(["git", "branch", "review-base", "HEAD~"], check=True)
    before = retry_review.fingerprint("--base review-base")
    subprocess.run(["git", "branch", "-f", "review-base", "HEAD"], check=True)
    assert retry_review.fingerprint("--base review-base") != before


def test_unknown_attempt_keeps_lock_ownership(tmp_path):
    module = runpy.run_path(str(LAUNCHER.with_name("review-result.py")))
    journal = tmp_path / "codex.attempts.jsonl"
    journal.write_text('{"state":"running"}\n')
    assert not module["settled"](tmp_path, 1)
    journal.write_text('{"state":"ok"}\n')
    assert module["settled"](tmp_path, 1)
    assert not module["settled"](tmp_path, 2)


def test_output_error_cannot_publish_success(tmp_path, monkeypatch):
    monkeypatch.setattr(retry_review, "fingerprint", lambda: "scope")

    def invoke(command, stdout, stderr):
        stdout.write(_claude_json("No findings", True).encode())
        return subprocess.CompletedProcess(command, 0)

    assert (
        retry_review.run(tmp_path, "claude", str(tmp_path), ["reviewer"], invoke=invoke)
        == 1
    )
    import json

    assert (
        json.loads((tmp_path / "claude.attempts.jsonl").read_text().splitlines()[-1])[
            "state"
        ]
        == "output-error"
    )


def test_result_rechecks_scope_at_handoff(tmp_path):
    import json

    module = runpy.run_path(str(LAUNCHER.with_name("review-result.py")))
    (tmp_path / "meta.txt").write_text(
        "reviewers: codex\nhead_sha: old-head\nscope: --uncommitted\nround: 1\nprior_ledger: none\n"
    )
    (tmp_path / "codex.attempts.jsonl").write_text(
        json.dumps(dict(state="ok", fingerprint="old-scope")) + "\n"
    )
    result = module["build"](tmp_path)
    assert result["outcome"] == "blocked"
    assert result["reviewers"][0]["reasonClass"] == "scope-changed"


def test_fingerprint_covers_root_untracked_from_subdirectory(tmp_path, monkeypatch):
    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True)
    sub = tmp_path / "sub"
    sub.mkdir()
    monkeypatch.chdir(sub)
    item = tmp_path / "untracked"
    item.write_text("before")
    before = retry_review.fingerprint("")
    item.write_text("after")
    assert retry_review.fingerprint("") != before
    assert retry_review.fingerprint("", str(tmp_path)) == retry_review.fingerprint("")


def test_fingerprint_covers_unborn_staged_changes(tmp_path, monkeypatch):
    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True)
    monkeypatch.chdir(tmp_path)
    item = tmp_path / "staged"
    item.write_text("before")
    subprocess.run(["git", "add", "staged"], check=True)
    before = retry_review.fingerprint("")
    item.write_text("after")
    subprocess.run(["git", "add", "staged"], check=True)
    assert retry_review.fingerprint("") != before


def test_intent_records_owner_and_paths(tmp_path, monkeypatch):
    monkeypatch.setattr(retry_review, "fingerprint", lambda: "scope")

    def interrupt(*args, **kwargs):
        raise KeyboardInterrupt

    with pytest.raises(KeyboardInterrupt):
        retry_review.run(
            tmp_path, "codex", str(tmp_path / "out"), ["reviewer"], invoke=interrupt
        )
    import json

    event = json.loads((tmp_path / "codex.attempts.jsonl").read_text().splitlines()[-1])
    assert event["retry_owner"] == "gauntlet"
    assert Path(event["raw"]).parent == tmp_path
    assert Path(event["answer"]).parent == tmp_path


def test_partial_findings_do_not_override_transport_diagnostic(tmp_path, monkeypatch):
    monkeypatch.setattr(retry_review, "fingerprint", lambda: "scope")
    results = iter([1, 0])

    def invoke(command, stdout, stderr):
        code = next(results)
        stdout.write(b"HTTP 503 model capacity" if code else b"completed")
        Path(command[1]).write_text("src/foo.py:401 authentication finding")
        return subprocess.CompletedProcess(command, code)

    assert (
        retry_review.run(
            tmp_path,
            "codex",
            str(tmp_path / "out"),
            ["reviewer", str(tmp_path / "out")],
            invoke=invoke,
            sleep=lambda _: None,
            clock=lambda: 0,
        )
        == 0
    )


def test_capped_adjudication_preserves_completed_review_after_fixes(
    tmp_path, monkeypatch
):
    import json

    repo = tmp_path / "repo"
    repo.mkdir()
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    monkeypatch.chdir(repo)
    scope = retry_review.fingerprint("--uncommitted")
    directory = tmp_path / "round-01"
    directory.mkdir()
    (directory / "meta.txt").write_text(
        f"reviewers: codex\nrepo_root: {repo}\nhead_sha: reviewed-head\nscope: --uncommitted\nround: 1\nprior_ledger: none\n"
    )
    (directory / "codex.attempts.jsonl").write_text(
        json.dumps(dict(state="ok", fingerprint=scope)) + "\n"
    )
    module = runpy.run_path(str(LAUNCHER.with_name("review-result.py")))
    module["publish"](directory)
    (repo / "fix").write_text("post-review fix")
    for outcome in ("capped", "escalated"):
        result = module["build"](directory, outcome)
        assert result["outcome"] == outcome
        assert result["reviewedHead"] == "reviewed-head"
        assert result["fingerprint"] == scope
        assert result["adjudicationFingerprint"] != scope
    with pytest.raises(ValueError):
        module["build"](directory, "converged")


_LOGGED_OUT_CLAUDE = (
    f"#!/bin/sh\necho '{_claude_json('Not logged in · Please run /login', False)}'\n"
)


@pytest.mark.parametrize(
    ("reviewer", "script", "partial", "token_file"),
    [
        (
            "codex",
            '#!/bin/sh\nwhile [ "$#" -gt 0 ]; do\n  if [ "$1" = "-o" ]; then shift; echo PARTIAL_FINDING > "$1"; fi\n  shift\ndone\necho "invalid model" >&2\nexit 1\n',
            "PARTIAL_FINDING",
            True,
        ),
        # Logged out, claude -p answers /code-review with exit 0 and no model turn.
        ("claude", _LOGGED_OUT_CLAUDE, "Not logged in", True),
        # Without a token anywhere, the reviewer is blocked before it starts.
        ("claude", _LOGGED_OUT_CLAUDE, "is missing", False),
    ],
)
def test_blocked_launcher_exposes_partial_and_result(
    tmp_path, reviewer, script, partial, token_file
):
    repo = tmp_path / "repo"
    repo.mkdir()
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    tools = tmp_path / "tools"
    tools.mkdir()
    stub = tools / reviewer
    stub.write_text(script)
    stub.chmod(0o755)
    environment = _isolated_environment(tmp_path, tools, token_file)
    result = subprocess.run(
        ["bash", str(LAUNCHER), "--uncommitted", "--reviewers", reviewer, "Fixture"],
        cwd=repo,
        env=environment,
        capture_output=True,
        text=True,
        timeout=10,
    )
    import json

    evidence = next((tmp_path / "state").glob("**/result.json"))
    assert result.returncode != 0
    assert partial in result.stdout
    assert str(evidence) in result.stdout
    assert json.loads(evidence.read_text())["outcome"] == "blocked"


def _token_file(tmp_path, content="tok-file\n", mode=0o600):
    path = tmp_path / "token"
    path.write_bytes(content if isinstance(content, bytes) else content.encode())
    path.chmod(mode)
    return path


@pytest.mark.parametrize(
    ("content", "mode", "token", "problem"),
    [
        ("  tok-file\n", 0o600, "tok-file", None),
        ("", 0o600, None, "is empty"),
        ("\n \n", 0o600, None, "is empty"),
        ("tok-file\n", 0o640, None, "group or others"),
        ("tok-file\n", 0o604, None, "group or others"),
        ("CLAUDE_CODE_OAUTH_TOKEN=tok", 0o600, None, "only the token"),
        ('"tok-file"', 0o600, None, "only the token"),
        (b"\xff\xfe", 0o600, None, "not text"),
    ],
)
def test_claude_token_file(tmp_path, content, mode, token, problem):
    path = _token_file(tmp_path, content, mode)
    found, reason = retry_review.claude_token(
        {"HOME": "/nonexistent", "GAUNTLET_CLAUDE_TOKEN_FILE": str(path)}
    )
    assert found == token
    assert (reason is None) if problem is None else (problem in reason)


def test_claude_token_default_path_missing_and_env_precedence(tmp_path):
    found, reason = retry_review.claude_token({"HOME": str(tmp_path)})
    assert found is None and "missing" in reason
    default = tmp_path / ".config/gauntlet/claude-oauth-token"
    default.parent.mkdir(parents=True)
    default.write_text("tok-default")
    default.chmod(0o600)
    assert retry_review.claude_token({"HOME": str(tmp_path)}) == ("tok-default", None)
    # A credential already in the environment wins; the file is not consulted.
    assert retry_review.claude_token(
        {"HOME": str(tmp_path), "CLAUDE_CODE_OAUTH_TOKEN": "tok-env"}
    ) == (None, None)


def test_blocked_claude_records_auth_without_launching(tmp_path, monkeypatch):
    monkeypatch.setattr(retry_review, "fingerprint", lambda: "scope")
    launched = []
    assert (
        retry_review.run(
            tmp_path,
            "claude",
            str(tmp_path / "out"),
            ["reviewer"],
            invoke=lambda *args, **kwargs: launched.append(args),
            blocked="Claude token file x is missing",
        )
        == 1
    )
    event = json.loads((tmp_path / "claude.attempts.jsonl").read_text().splitlines()[-1])
    assert launched == []
    assert event["state"] == "auth"
