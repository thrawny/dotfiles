"""Reviewer selection runs only the requested tools, without model invocations."""

import os
import subprocess
from pathlib import Path

import pytest

LAUNCHER = (
    Path(__file__).resolve().parents[1] / "skills/gauntlet/scripts/gauntlet-review"
)


@pytest.mark.parametrize(
    ("configured", "arguments", "expected"),
    [
        (None, [], {"codex"}),
        ("", [], {"codex"}),
        ("claude", [], {"claude"}),
        ("claude,codex", [], {"claude", "codex"}),
        ("codex", ["--reviewers", "claude"], {"claude"}),
        ("claude,codex", ["--reviewers", "codex"], {"codex"}),
        ("invalid", [], set()),
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
            'printf "No findings\\n"\n'
        )
        stub.chmod(0o755)
    environment = {
        key: value
        for key, value in os.environ.items()
        if not key.startswith("GAUNTLET_")
    }
    environment.update(
        PATH=f"{tools}:{environment['PATH']}",
        CALLS=str(calls),
        GAUNTLET_STATE_DIR=str(tmp_path / "state"),
    )
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

# Retry policy is plain-data logic; these tests use no provider calls or sleeps.
import importlib.util
import runpy

_spec = importlib.util.spec_from_file_location("retry_review", LAUNCHER.with_name("retry-review.py"))
retry_review = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(retry_review)


@pytest.mark.parametrize("diagnostic, expected", [
    ("model capacity temporarily unavailable", "transient"),
    ("429 rate limit", "transient"),
    ("connection reset", "transient"),
    ("401 temporarily unavailable", "auth"),
    ("quota exceeded 429", "quota"),
    ("invalid model", "terminal"),
])
def test_retry_classification(diagnostic, expected):
    assert retry_review.classify(1, diagnostic) == expected


@pytest.mark.parametrize("codes, diagnostic, expected, attempts", [
    ([1, 0], "503 model capacity", 0, 2),
    ([1, 1, 1], "429 rate limit", 1, 3),
    ([1], "invalid API key", 1, 1),
    ([130], "temporary transport error", 1, 1),
    ([1], '429 resetAt: 9999999999', 1, 1),
])
def test_retry_outcomes(tmp_path, monkeypatch, codes, diagnostic, expected, attempts):
    monkeypatch.setattr(retry_review, "fingerprint", lambda: "exact-scope")
    remaining = iter(codes)
    waits = []
    def invoke(command, stdout, stderr):
        code = next(remaining)
        stdout.write((diagnostic if code else "No findings").encode())
        return subprocess.CompletedProcess(command, code)
    output = tmp_path / "result.out"
    result = retry_review.run(tmp_path, "claude", str(output), ["reviewer"],
                              invoke=invoke, sleep=waits.append, clock=lambda: 0)
    import json
    events = [json.loads(line) for line in (tmp_path / "claude.attempts.jsonl").read_text().splitlines()]
    assert result == expected
    assert sum(event["state"] == "running" for event in events) == attempts
    assert output.exists() is (expected == 0)
    assert len(waits) == attempts - 1


def test_retry_scope_change_blocks(tmp_path, monkeypatch):
    scopes = iter(["before", "before", "after"])
    monkeypatch.setattr(retry_review, "fingerprint", lambda: next(scopes))
    def invoke(command, stdout, stderr):
        stdout.write(b"No findings")
        return subprocess.CompletedProcess(command, 0)
    output = tmp_path / "result"
    assert retry_review.run(tmp_path, "claude", str(output), ["reviewer"], invoke=invoke) == 1
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
    assert retry_review.run(tmp_path, "codex", str(output), ["codex", str(output)],
                            invoke=invoke, sleep=lambda _: None, clock=lambda: 0) == 0
    assert output.read_text() == "No findings"
    assert (tmp_path / "codex.attempt-1.out").read_text() == "partial"


@pytest.mark.parametrize('state, exhausted, outcome', [('ok', False, 'review-complete'), ('auth', False, 'blocked'), ('transient', True, 'exhausted')])
def test_structured_result_fails_closed(tmp_path, state, exhausted, outcome):
    import json
    result_module = runpy.run_path(str(LAUNCHER.with_name('review-result.py')))
    (tmp_path / 'meta.txt').write_text('reviewers: codex\nhead_sha: exact-head\nscope: --uncommitted\nround: 2\nprior_ledger: none\n')
    events = [dict(state='running', fingerprint=retry_review.fingerprint('--uncommitted')), dict(state=state, exhausted=exhausted, resetAt=123)]
    (tmp_path / 'codex.attempts.jsonl').write_text(''.join(json.dumps(e) + '\n' for e in events))
    result = result_module['build'](tmp_path)
    assert result['outcome'] == outcome
    assert result['retryable'] is False
    assert result['retryBudgetExhausted'] is exhausted
    assert result['reviewers'][0]['attempts'] == 1
    if state != 'ok':
        with pytest.raises(ValueError):
            result_module['build'](tmp_path, 'converged')
    else:
        assert result_module['build'](tmp_path, 'converged')['outcome'] == 'converged'


@pytest.mark.parametrize('text, expected', [
    ('resetAt: 2026-10-29T12:00:00+02:00', '2026-10-29T10:00:00Z'),
    ('resetAt: 2026-10-29T12:00:00', None),
    ('resetAt: invalid', None),
    ('Retry-After: 60', None),
    ('temporary capacity', None),
])
def test_provider_reset_is_absolute(text, expected):
    assert retry_review.reset_at(text) == expected


def test_successful_review_can_discuss_auth_and_quota():
    assert retry_review.classify(0, '401 authentication quota billing') == 'ok'


def test_retry_deadline_rechecked_after_sleep(tmp_path, monkeypatch):
    monkeypatch.setattr(retry_review, 'fingerprint', lambda: 'scope')
    now = [0]
    launches = []
    def invoke(command, stdout, stderr):
        launches.append(now[0])
        stdout.write(b'503 capacity')
        return subprocess.CompletedProcess(command, 1)
    def sleep(_):
        now[0] = 400
    assert retry_review.run(tmp_path, 'claude', str(tmp_path / 'out'), ['reviewer'],
                            invoke=invoke, sleep=sleep, clock=lambda: now[0]) == 1
    assert launches == [0]
    import json
    assert json.loads((tmp_path / 'claude.attempts.jsonl').read_text().splitlines()[-1])['exhausted']


def test_untracked_fingerprint_has_file_boundaries(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    subprocess.run(['git', 'init', '-q'], check=True)
    (tmp_path / 'a').write_text('x')
    (tmp_path / 'b').write_text('y')
    before = retry_review.fingerprint('')
    (tmp_path / 'a').write_text('xy')
    (tmp_path / 'b').write_text('')
    assert retry_review.fingerprint('') != before


def test_base_ref_is_part_of_fingerprint(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    subprocess.run(['git', 'init', '-q'], check=True)
    for index in range(2):
        subprocess.run(['git', '-c', 'user.name=Test', '-c', 'user.email=test@example.com',
                        'commit', '--allow-empty', '-qm', str(index)], check=True)
    subprocess.run(['git', 'branch', 'review-base', 'HEAD~'], check=True)
    before = retry_review.fingerprint('--base review-base')
    subprocess.run(['git', 'branch', '-f', 'review-base', 'HEAD'], check=True)
    assert retry_review.fingerprint('--base review-base') != before


def test_unknown_attempt_keeps_lock_ownership(tmp_path):
    module = runpy.run_path(str(LAUNCHER.with_name('review-result.py')))
    journal = tmp_path / 'codex.attempts.jsonl'
    journal.write_text('{"state":"running"}\n')
    assert not module['settled'](tmp_path, 1)
    journal.write_text('{"state":"ok"}\n')
    assert module['settled'](tmp_path, 1)
    assert not module['settled'](tmp_path, 2)


def test_output_error_cannot_publish_success(tmp_path, monkeypatch):
    monkeypatch.setattr(retry_review, 'fingerprint', lambda: 'scope')
    def invoke(command, stdout, stderr):
        stdout.write(b'No findings')
        return subprocess.CompletedProcess(command, 0)
    assert retry_review.run(tmp_path, 'claude', str(tmp_path), ['reviewer'], invoke=invoke) == 1
    import json
    assert json.loads((tmp_path / 'claude.attempts.jsonl').read_text().splitlines()[-1])['state'] == 'output-error'


def test_result_rechecks_scope_at_handoff(tmp_path):
    import json
    module = runpy.run_path(str(LAUNCHER.with_name('review-result.py')))
    (tmp_path / 'meta.txt').write_text('reviewers: codex\nhead_sha: old-head\nscope: --uncommitted\nround: 1\nprior_ledger: none\n')
    (tmp_path / 'codex.attempts.jsonl').write_text(json.dumps(dict(state='ok', fingerprint='old-scope')) + '\n')
    result = module['build'](tmp_path)
    assert result['outcome'] == 'blocked'
    assert result['reviewers'][0]['reasonClass'] == 'scope-changed'
