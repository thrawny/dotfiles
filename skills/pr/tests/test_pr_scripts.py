"""Integration tests for the PR skill's GitHub helper scripts."""

# pyright: basic

from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SKILL_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = SKILL_ROOT / "scripts" / "pr"

FAKE_GH = r"""#!/usr/bin/env python3
import json
import os
import sys

args = sys.argv[1:]
head = "a" * 40
no_checks = os.environ.get("FAKE_NO_CHECKS") == "1"
no_signals = os.environ.get("FAKE_NO_SIGNALS") == "1"

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
                "content": "+1",
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
                "commit_id": "b" * 40,
                "submitted_at": "2026-07-10T00:03:00Z",
                "body": "Reviewed commit: `bbbbbbbbbbbb`",
            }]
    print(json.dumps([items] if "--slurp" in args else items))
    raise SystemExit(0)

print("unsupported fake gh call: " + " ".join(args), file=sys.stderr)
raise SystemExit(2)
"""


class PrScriptTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.temp_path = Path(self.temp.name)
        fake_gh = self.temp_path / "gh"
        fake_gh.write_text(FAKE_GH)
        fake_gh.chmod(0o755)
        self.env = os.environ.copy()
        self.env["PATH"] = f"{self.temp_path}:{self.env['PATH']}"

    def tearDown(self) -> None:
        self.temp.cleanup()

    def run_script(
        self, *args: str, env: dict[str, str] | None = None
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [str(SCRIPT), *args],
            check=False,
            capture_output=True,
            text=True,
            env=env or self.env,
        )

    def test_snapshot_is_bounded_and_current_head_aware(self) -> None:
        result = self.run_script("snapshot", "12", "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(data["reviewers"][0]["state"], "finished")
        self.assertEqual(data["reviewers"][0]["final_artifacts"], 2)
        self.assertEqual(
            [thread["id"] for thread in data["threads"]["currentUnresolved"]],
            ["THREAD_1", "THREAD_2"],
        )
        self.assertEqual(
            data["readiness"]["machineBlockers"],
            ["failed-checks", "unresolved-threads"],
        )
        self.assertTrue(data["readiness"]["humanApprovalRequired"])

    def test_threads_list_and_explicit_resolution(self) -> None:
        listed = self.run_script("threads", "list", "12", "--json")
        self.assertEqual(listed.returncode, 0, listed.stderr)
        self.assertEqual(json.loads(listed.stdout)["threads"][0]["id"], "THREAD_1")

        resolved = self.run_script("threads", "resolve", "THREAD_1")
        self.assertEqual(resolved.returncode, 0, resolved.stderr)
        self.assertIn("resolved THREAD_1", resolved.stdout)

    def test_failed_check_logs_are_saved_and_excerpted(self) -> None:
        output_dir = self.temp_path / "logs"
        result = self.run_script(
            "failed-checks",
            "12",
            "--output-dir",
            str(output_dir),
            "--json",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(data["failedCount"], 1)
        self.assertTrue(Path(data["runs"][0]["logPath"]).exists())
        self.assertTrue(
            any("widget mismatch" in line for line in data["runs"][0]["excerpt"])
        )

    def test_waiter_accepts_no_checks_and_inactive_optional_reviewer(self) -> None:
        env = self.env.copy()
        env["FAKE_NO_CHECKS"] = "1"
        env["FAKE_NO_SIGNALS"] = "1"
        result = self.run_script(
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
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("checks_total=0", result.stdout)
        self.assertIn("codex_state=inactive", result.stdout)


if __name__ == "__main__":
    unittest.main()
