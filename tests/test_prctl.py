"""Integration tests for prctl against a fake gh."""

# pyright: basic

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
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
comment_reaction = os.environ.get("FAKE_COMMENT_REACTION") == "1"
human_review_state = os.environ.get("FAKE_HUMAN_REVIEW_STATE")


def views_so_far():
    counter_path = os.environ.get("FAKE_PR_VIEW_COUNTER")
    try:
        return int(open(counter_path).read()) if counter_path else 0
    except (FileNotFoundError, ValueError):
        return 0


# The first pr view is the initial read; anything "late" shows up from the
# second view on, which is the watcher's first poll.
late = views_so_far() >= 2

if args[:2] == ["pr", "view"]:
    current_head = head
    counter_path = os.environ.get("FAKE_PR_VIEW_COUNTER")
    if counter_path:
        try:
            view_count = int(open(counter_path).read())
        except (FileNotFoundError, ValueError):
            view_count = 0
        with open(counter_path, "w") as counter:
            counter.write(str(view_count + 1))
        if os.environ.get("FAKE_HEAD_CHANGE_AFTER_INITIAL") == "1" and view_count > 0:
            current_head = "c" * 40
    state = os.environ.get("FAKE_PR_STATE", "OPEN")
    if os.environ.get("FAKE_LATE_PR_STATE") and views_so_far() >= 2:
        state = os.environ["FAKE_LATE_PR_STATE"]
    checks_pending = (
        os.environ.get("FAKE_CHECKS_PENDING_INITIAL") == "1" and views_so_far() < 2
    )
    checks = [] if no_checks else [{
        "name": "test",
        "status": "IN_PROGRESS" if checks_pending else "COMPLETED",
        "conclusion": "" if checks_pending else os.environ.get(
            "FAKE_CHECK_CONCLUSION", "FAILURE"
        ),
        "detailsUrl": "https://github.com/acme/widgets/actions/runs/123/job/456",
        "workflowName": "CI",
    }]
    print(json.dumps({
        "number": 12,
        "title": "Improve widgets",
        "url": "https://github.com/acme/widgets/pull/12",
        "state": state,
        "headRefOid": current_head,
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
    if endpoint == "user":
        print(json.dumps({"login": os.environ.get("FAKE_LOGIN", "octocat")}))
        raise SystemExit(0)
    if "/commits/" in endpoint:
        print(json.dumps({"commit": {"committer": {"date": "2026-07-10T00:00:00Z"}}}))
        raise SystemExit(0)

    items = []
    if comment_reaction:
        if endpoint.startswith("repos/acme/widgets/issues/12/comments?"):
            items = [{
                "id": 555,
                "user": {"login": "ReviewerOne"},
                "body": "@codex review",
                "created_at": "2026-07-10T00:05:00Z",
                "reactions": {"total_count": 1, "eyes": 1},
            }, {
                "id": 444,
                "user": {"login": "ReviewerOne"},
                "body": "@codex review",
                "created_at": "2026-07-09T23:00:00Z",
                "reactions": {"total_count": 1, "eyes": 1},
            }]
        elif endpoint.startswith("repos/acme/widgets/issues/comments/555/reactions?"):
            items = [{
                "user": {"login": "chatgpt-codex-connector[bot]"},
                "content": "eyes",
                "created_at": "2026-07-10T00:05:30Z",
            }]
        elif "/issues/comments/" in endpoint:
            print("unexpected reaction lookup: " + endpoint, file=sys.stderr)
            raise SystemExit(2)
    elif not no_signals:
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
                "state": "APPROVED",
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
    if human_review_state and "/reviews?" in endpoint:
        items.append({
            "id": 99,
            "user": {"login": "ReviewerOne"},
            "commit_id": head,
            "submitted_at": "2026-07-10T00:04:00Z",
            "state": human_review_state,
        })
    if endpoint.startswith("repos/acme/widgets/issues/12/comments?"):
        if os.environ.get("FAKE_EARLY_COMMENT_AT"):
            items.append({
                "id": 800,
                "user": {"login": "ReviewerTwo"},
                "body": "Looked at it before the watcher started",
                "created_at": os.environ["FAKE_EARLY_COMMENT_AT"],
                "html_url": "https://github.com/acme/widgets/pull/12#issuecomment-800",
            })
        if os.environ.get("FAKE_EDITED_COMMENT") == "1":
            items.append({
                "id": 801,
                "user": {"login": "ci-helper[bot]"},
                "body": "Sticky status, edited on every poll",
                "created_at": "2026-07-10T00:00:30Z",
                "updated_at": f"2026-07-10T00:0{min(views_so_far(), 9)}:00Z",
            })
        if late and os.environ.get("FAKE_LATE_COMMENT_AUTHOR"):
            items.append({
                "id": 900,
                "user": {"login": os.environ["FAKE_LATE_COMMENT_AUTHOR"]},
                "body": "Could this handle the empty widget?",
                "created_at": "2026-07-10T00:10:00Z",
                "html_url": "https://github.com/acme/widgets/pull/12#issuecomment-900",
            })
    if late and os.environ.get("FAKE_LATE_REVIEW_STATE") and "/reviews?" in endpoint:
        items.append({
            "id": 901,
            "user": {"login": "ReviewerOne"},
            "submitted_at": "2026-07-10T00:11:00Z",
            "state": os.environ["FAKE_LATE_REVIEW_STATE"],
            "body": "",
            "html_url": "https://github.com/acme/widgets/pull/12#pullrequestreview-901",
        })
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
    assert "start a new waiter" not in result.stdout


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


def test_reaction_on_a_trigger_comment_marks_the_reviewer_active(
    tmp_path: Path,
) -> None:
    pr_harness = PrHarness(tmp_path)
    env = pr_harness.env.copy()
    env["FAKE_COMMENT_REACTION"] = "1"
    result = pr_harness.run("snapshot", "12", "--json", env=env)
    assert result.returncode == 0, result.stderr
    data = json.loads(result.stdout)
    reviewer = data["reviewers"][0]
    assert reviewer["state"] == "active"
    assert reviewer["active_reactions"] == 1
    assert reviewer["issue_comments"] == 0


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
    assert "reviewer timeout: codex still active with no final review" in result.stdout
    assert "start a new waiter" in result.stdout
    assert result.stdout.count("snapshot ") == 2


def test_waiter_reports_deadline_settle_as_inconclusive(tmp_path: Path) -> None:
    pr_harness = PrHarness(tmp_path)
    env = pr_harness.env.copy()
    env["FAKE_ACTIVE_REVIEWER"] = "1"
    result = pr_harness.run(
        "wait",
        "12",
        "--interval",
        "1",
        "--timeout",
        "3",
        "--reviewer-timeout",
        "30",
        env=env,
    )
    assert result.returncode == 0, result.stderr
    assert "settled" in result.stdout
    assert "wait timeout reached before reviewers settled" in result.stdout
    assert "start a new waiter" in result.stdout


def test_waiter_can_require_approval_from_a_specific_reviewer(tmp_path: Path) -> None:
    pr_harness = PrHarness(tmp_path)
    env = pr_harness.env.copy()
    env["FAKE_HUMAN_REVIEW_STATE"] = "APPROVED"
    result = pr_harness.run(
        "wait",
        "12",
        "--require-approval-from",
        "reviewerone",
        "--interval",
        "1",
        "--timeout",
        "2",
        env=env,
    )
    assert result.returncode == 0, result.stderr
    assert "reason=approved" in result.stdout
    assert "reviewer=reviewerone" in result.stdout


def test_required_approval_wait_wakes_on_changes_requested(tmp_path: Path) -> None:
    pr_harness = PrHarness(tmp_path)
    env = pr_harness.env.copy()
    env["FAKE_HUMAN_REVIEW_STATE"] = "CHANGES_REQUESTED"
    result = pr_harness.run(
        "wait",
        "12",
        "--require-approval-from",
        "ReviewerOne",
        "--interval",
        "1",
        "--timeout",
        "2",
        env=env,
    )
    assert result.returncode == 0, result.stderr
    assert "reason=changes-requested" in result.stdout


def test_required_approval_wait_wakes_on_pr_closure(tmp_path: Path) -> None:
    pr_harness = PrHarness(tmp_path)
    env = pr_harness.env.copy()
    env["FAKE_PR_STATE"] = "CLOSED"
    result = pr_harness.run(
        "wait",
        "12",
        "--require-approval-from",
        "ReviewerOne",
        env=env,
    )
    assert result.returncode == 0, result.stderr
    assert "reason=pr-closed" in result.stdout
    assert "state=CLOSED" in result.stdout


def test_required_approval_wait_wakes_on_head_change(tmp_path: Path) -> None:
    pr_harness = PrHarness(tmp_path)
    env = pr_harness.env.copy()
    env["FAKE_PR_VIEW_COUNTER"] = str(tmp_path / "pr-view-count")
    env["FAKE_HEAD_CHANGE_AFTER_INITIAL"] = "1"
    result = pr_harness.run(
        "wait",
        "12",
        "--require-approval-from",
        "ReviewerOne",
        "--interval",
        "1",
        "--timeout",
        "2",
        env=env,
    )
    assert result.returncode == 0, result.stderr
    assert "reason=head-changed" in result.stdout
    assert "old=aaaaaaaaaaaa" in result.stdout
    assert "new=cccccccccccc" in result.stdout


def test_required_approval_wait_times_out_without_that_reviewers_decision(
    tmp_path: Path,
) -> None:
    pr_harness = PrHarness(tmp_path)
    env = pr_harness.env.copy()
    result = pr_harness.run(
        "wait",
        "12",
        "--require-approval-from",
        "ReviewerOne",
        "--interval",
        "1",
        "--timeout",
        "1",
        env=env,
    )
    assert result.returncode == 1
    assert "timed out" in result.stderr
    assert "reviewer=ReviewerOne" in result.stderr


def watch_env(pr_harness: PrHarness, **values: str) -> dict[str, str]:
    env = pr_harness.env.copy()
    env["FAKE_NO_SIGNALS"] = "1"
    env["FAKE_PR_VIEW_COUNTER"] = str(pr_harness.temp_path / "pr-view-count")
    env.update(values)
    return env


def watch(
    pr_harness: PrHarness, env: dict[str, str], *args: str
) -> subprocess.CompletedProcess[str]:
    return pr_harness.run(
        "watch", "12", "--interval", "1", "--timeout", "3", *args, env=env
    )


def test_watch_wakes_on_a_teammates_comment(tmp_path: Path) -> None:
    pr_harness = PrHarness(tmp_path)
    env = watch_env(pr_harness, FAKE_LATE_COMMENT_AUTHOR="ReviewerOne")
    result = watch(pr_harness, env)
    assert result.returncode == 0, result.stderr
    assert "woke reason=activity pr=#12" in result.stdout
    assert "comment @ReviewerOne: Could this handle the empty widget?" in result.stdout
    assert "#issuecomment-900" in result.stdout
    assert "next-since=" in result.stdout


def test_watch_counts_a_bot_comment(tmp_path: Path) -> None:
    pr_harness = PrHarness(tmp_path)
    env = watch_env(pr_harness, FAKE_LATE_COMMENT_AUTHOR="scanner[bot]")
    result = watch(pr_harness, env)
    assert result.returncode == 0, result.stderr
    assert "comment @scanner[bot]" in result.stdout


def test_watch_skips_the_signed_in_user_unless_asked(tmp_path: Path) -> None:
    pr_harness = PrHarness(tmp_path)
    env = watch_env(pr_harness, FAKE_LATE_COMMENT_AUTHOR="Octocat")
    skipped = watch(pr_harness, env, "--timeout", "2")
    assert skipped.returncode == 1
    assert "ignore=octocat" in skipped.stdout
    assert "timed out" in skipped.stderr

    (tmp_path / "pr-view-count").unlink()
    included = watch(pr_harness, env, "--include-self")
    assert included.returncode == 0, included.stderr
    assert "comment @Octocat" in included.stdout


def test_watch_ignores_named_authors(tmp_path: Path) -> None:
    pr_harness = PrHarness(tmp_path)
    env = watch_env(pr_harness, FAKE_LATE_COMMENT_AUTHOR="noisy[bot]")
    result = watch(pr_harness, env, "--timeout", "2", "--ignore-author", "noisy")
    assert result.returncode == 1
    assert "woke" not in result.stdout


def test_watch_does_not_wake_on_an_edited_comment(tmp_path: Path) -> None:
    pr_harness = PrHarness(tmp_path)
    env = watch_env(pr_harness, FAKE_EDITED_COMMENT="1")
    result = watch(pr_harness, env, "--timeout", "2")
    assert result.returncode == 1
    assert "woke" not in result.stdout


def test_watch_reports_an_approval(tmp_path: Path) -> None:
    pr_harness = PrHarness(tmp_path)
    env = watch_env(pr_harness, FAKE_LATE_REVIEW_STATE="APPROVED")
    result = watch(pr_harness, env)
    assert result.returncode == 0, result.stderr
    assert "review approved @ReviewerOne: (no text)" in result.stdout


def test_watch_since_counts_activity_from_before_the_watcher(tmp_path: Path) -> None:
    pr_harness = PrHarness(tmp_path)
    env = watch_env(pr_harness, FAKE_EARLY_COMMENT_AT="2026-07-10T00:05:00Z")
    quiet = watch(pr_harness, env, "--timeout", "2")
    assert quiet.returncode == 1

    (tmp_path / "pr-view-count").unlink()
    caught = watch(pr_harness, env, "--since", "2026-07-10T00:04:00Z")
    assert caught.returncode == 0, caught.stderr
    assert "comment @ReviewerTwo" in caught.stdout


def test_watch_wakes_on_a_new_commit(tmp_path: Path) -> None:
    pr_harness = PrHarness(tmp_path)
    env = watch_env(pr_harness, FAKE_HEAD_CHANGE_AFTER_INITIAL="1")
    result = watch(pr_harness, env)
    assert result.returncode == 0, result.stderr
    assert "woke reason=commit" in result.stdout
    assert "old=aaaaaaaaaaaa new=cccccccccccc" in result.stdout


def test_watch_on_limits_the_events(tmp_path: Path) -> None:
    pr_harness = PrHarness(tmp_path)
    env = watch_env(pr_harness, FAKE_HEAD_CHANGE_AFTER_INITIAL="1")
    result = watch(pr_harness, env, "--timeout", "2", "--on", "activity,state")
    assert result.returncode == 1
    assert "on=state,activity" in result.stdout


def test_watch_rejects_an_unknown_event(tmp_path: Path) -> None:
    result = PrHarness(tmp_path).run("watch", "12", "--on", "commit,labels")
    assert result.returncode == 2
    assert "unknown: labels" in result.stderr


def test_watch_wakes_when_the_pr_merges(tmp_path: Path) -> None:
    pr_harness = PrHarness(tmp_path)
    env = watch_env(pr_harness, FAKE_LATE_PR_STATE="MERGED")
    result = watch(pr_harness, env)
    assert result.returncode == 0, result.stderr
    assert "woke reason=merged" in result.stdout


def test_watch_wakes_when_a_check_newly_fails(tmp_path: Path) -> None:
    pr_harness = PrHarness(tmp_path)
    env = watch_env(pr_harness, FAKE_CHECKS_PENDING_INITIAL="1")
    result = watch(pr_harness, env)
    assert result.returncode == 0, result.stderr
    assert "woke reason=checks" in result.stdout
    assert "checks_pending=0 checks_failed=1" in result.stdout
    assert "failed (new): test" in result.stdout


def test_watch_keeps_waiting_when_checks_go_green(tmp_path: Path) -> None:
    pr_harness = PrHarness(tmp_path)
    env = watch_env(
        pr_harness, FAKE_CHECKS_PENDING_INITIAL="1", FAKE_CHECK_CONCLUSION="SUCCESS"
    )
    result = watch(pr_harness, env, "--timeout", "2")
    assert result.returncode == 1
    assert "woke" not in result.stdout


def test_watch_ignores_a_failure_that_was_already_there(tmp_path: Path) -> None:
    pr_harness = PrHarness(tmp_path)
    result = watch(pr_harness, watch_env(pr_harness), "--timeout", "2")
    assert result.returncode == 1
    assert "woke" not in result.stdout
