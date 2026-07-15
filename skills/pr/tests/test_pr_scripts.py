"""Integration tests for the PR skill's GitHub helper scripts."""

# pyright: basic

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
SCRIPT = REPO_ROOT / "bin" / "prctl"

FAKE_GH = r"""#!/usr/bin/env python3
import json
import os
import sys

args = sys.argv[1:]
head = "a" * 40
no_checks = os.environ.get("FAKE_NO_CHECKS") == "1"
no_signals = os.environ.get("FAKE_NO_SIGNALS") == "1"
active_reviewer = os.environ.get("FAKE_ACTIVE_REVIEWER") == "1"

if args[:2] == ["pr", "view"]:
    checks = [] if no_checks else [{
        "name": "test",
        "status": "COMPLETED",
        "conclusion": "FAILURE",
        "detailsUrl": "https://github.com/acme/widgets/actions/runs/123/job/456",
        "workflowName": "CI",
    }]
    print(json.dumps({
        "number": 12,
        "title": "Improve widgets",
        "url": "https://github.com/acme/widgets/pull/12",
        "state": "OPEN",
        "headRefOid": head,
        "headRefName": "feature/widgets",
        "baseRefName": "main",
        "isDraft": False,
        "mergeable": "MERGEABLE",
        "mergeStateStatus": "BLOCKED",
        "reviewDecision": "REVIEW_REQUIRED",
        "statusCheckRollup": checks,
    }))
    raise SystemExit(0)

if args[:2] == ["run", "view"]:
    print("build\tstep\tstarting\nbuild\tstep\terror: widget mismatch\nbuild\tstep\tfailed")
    raise SystemExit(0)

if args and args[0] == "api":
    joined = " ".join(args)
    endpoint = args[-1]
    if " graphql " in f" {joined} ":
        if "resolveReviewThread" in joined:
            thread_id = next(value.split("=", 1)[1] for value in args if value.startswith("threadId="))
            print(json.dumps({"data": {"resolveReviewThread": {"thread": {"id": thread_id, "isResolved": True}}}}))
        else:
            cursor = next((value.split("=", 1)[1] for value in args if value.startswith("cursor=")), None)
            number = "2" if cursor else "1"
            print(json.dumps({"data": {"repository": {"pullRequest": {"reviewThreads": {
                "nodes": [{
                    "id": f"THREAD_{number}",
                    "isResolved": False,
                    "isOutdated": False,
                    "path": "src/widget.py",
                    "line": 42,
                    "originalLine": 42,
                    "comments": {"nodes": [{
                        "author": {"login": "chatgpt-codex-connector"},
                        "body": "Fix the widget edge case",
                        "url": f"https://github.com/acme/widgets/pull/12#discussion_r{number}",
                        "createdAt": "2026-07-10T00:01:00Z",
                    }]},
                }],
                "pageInfo": {"hasNextPage": cursor is None, "endCursor": "NEXT" if cursor is None else None},
            }}}}}))
        raise SystemExit(0)
    if "/commits/" in endpoint:
        print(json.dumps({"commit": {"committer": {"date": "2026-07-10T00:00:00Z"}}}))
        raise SystemExit(0)

    items = []
    if not no_signals:
        if "/reactions?" in endpoint:
            items = [{
                "user": {"login": "chatgpt-codex-connector[bot]"},
                "content": "eyes" if active_reviewer else "+1",
                "created_at": "2026-07-10T00:02:00Z",
            }]
        elif "/reviews?" in endpoint:
            items = [{
                "user": {"login": "chatgpt-codex-connector"},
                "commit_id": head,
                "submitted_at": "2026-07-10T00:02:00Z",
                "body": "Reviewed commit: `aaaaaaaaaaaa`",
            }, {
                "user": {"login": "chatgpt-codex-connector[bot]"},
                "commit_id": head,
                "submitted_at": "2026-07-10T00:03:00Z",
                "body": "Reviewed commit: `bbbbbbbbbbbb`",
            }]
        elif "/pulls/" in endpoint and "/comments?" in endpoint:
            items = [{
                "user": {"login": "chatgpt-codex-connector[bot]"},
                "original_commit_id": "b" * 40,
                "commit_id": head,
                "created_at": "2026-07-10T00:03:00Z",
                "body": "Old inline finding",
            }]
    print(json.dumps([items] if "--slurp" in args else items))
    raise SystemExit(0)

print("unsupported fake gh call: " + " ".join(args), file=sys.stderr)
raise SystemExit(2)
"""


class PrHarness:
    def __init__(self, temp_path: Path) -> None:
        self.temp_path = temp_path
        fake_gh = temp_path / "gh"
        fake_gh.write_text(FAKE_GH)
        fake_gh.chmod(0o755)
        self.env = os.environ.copy()
        self.env["PATH"] = f"{temp_path}:{self.env['PATH']}"

    def run(
        self, *args: str, env: dict[str, str] | None = None
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(SCRIPT), *args],
            check=False,
            capture_output=True,
            text=True,
            env=self.env if env is None else env,
        )


def test_snapshot_is_bounded_and_current_head_aware(tmp_path: Path) -> None:
    result = PrHarness(tmp_path).run("snapshot", "12", "--json")
    assert result.returncode == 0, result.stderr
    data = json.loads(result.stdout)
    assert data["reviewers"][0]["state"] == "finished"
    assert data["reviewers"][0]["final_artifacts"] == 2
    assert [thread["id"] for thread in data["threads"]["currentUnresolved"]] == [
        "THREAD_1",
        "THREAD_2",
    ]
    assert data["readiness"]["machineBlockers"] == [
        "failed-checks",
        "unresolved-threads",
    ]
    assert data["readiness"]["humanApprovalRequired"]


def test_threads_list_and_explicit_resolution(tmp_path: Path) -> None:
    pr_harness = PrHarness(tmp_path)
    listed = pr_harness.run("threads", "list", "12", "--json")
    assert listed.returncode == 0, listed.stderr
    assert json.loads(listed.stdout)["threads"][0]["id"] == "THREAD_1"

    resolved = pr_harness.run("threads", "resolve", "PRRT_THREAD_1")
    assert resolved.returncode == 0, resolved.stderr
    assert "resolved PRRT_THREAD_1" in resolved.stdout


def test_thread_resolution_rejects_all_arguments_before_mutating(
    tmp_path: Path,
) -> None:
    result = PrHarness(tmp_path).run("threads", "resolve", "PRRT_THREAD_1", "12")
    assert result.returncode != 0
    assert result.stdout == ""
    assert "invalid review thread ID(s): 12" in result.stderr


def test_failed_check_logs_are_saved_and_excerpted(tmp_path: Path) -> None:
    pr_harness = PrHarness(tmp_path)
    output_dir = pr_harness.temp_path / "logs"
    result = pr_harness.run(
        "failed-checks",
        "12",
        "--output-dir",
        str(output_dir),
        "--json",
    )
    assert result.returncode == 0, result.stderr
    data = json.loads(result.stdout)
    assert data["failedCount"] == 1
    assert Path(data["runs"][0]["logPath"]).exists()
    assert any("widget mismatch" in line for line in data["runs"][0]["excerpt"])


def test_waiter_accepts_no_checks_and_inactive_optional_reviewer(
    tmp_path: Path,
) -> None:
    pr_harness = PrHarness(tmp_path)
    env = pr_harness.env.copy()
    env["FAKE_NO_CHECKS"] = "1"
    env["FAKE_NO_SIGNALS"] = "1"
    result = pr_harness.run(
        "wait",
        "12",
        "--interval",
        "1",
        "--timeout",
        "4",
        "--checks-grace",
        "1",
        "--reviewer-grace",
        "1",
        env=env,
    )
    assert result.returncode == 0, result.stderr
    assert "checks_total=0" in result.stdout
    assert "codex_state=inactive" in result.stdout


def test_active_reviewer_takes_precedence_over_final_artifacts(
    tmp_path: Path,
) -> None:
    pr_harness = PrHarness(tmp_path)
    env = pr_harness.env.copy()
    env["FAKE_ACTIVE_REVIEWER"] = "1"
    result = pr_harness.run("snapshot", "12", "--json", env=env)
    assert result.returncode == 0, result.stderr
    data = json.loads(result.stdout)
    assert data["reviewers"][0]["state"] == "active"
    assert "codex-active" in data["readiness"]["machineBlockers"]


def test_waiter_degrades_an_active_unavailable_reviewer(tmp_path: Path) -> None:
    pr_harness = PrHarness(tmp_path)
    env = pr_harness.env.copy()
    env["FAKE_ACTIVE_REVIEWER"] = "1"
    result = pr_harness.run(
        "wait",
        "12",
        "--interval",
        "1",
        "--timeout",
        "4",
        "--reviewer-timeout",
        "2",
        env=env,
    )
    assert result.returncode == 0, result.stderr
    assert "codex_state=unavailable" in result.stdout
    assert result.stdout.count("snapshot ") == 2
