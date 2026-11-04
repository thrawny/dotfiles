"""Decision checks before building or replacing fleet app runtimes."""

import datetime as dt
import importlib.util
from pathlib import Path
from typing import Any

import pytest

spec = importlib.util.spec_from_file_location(
    "nightly_app_update",
    Path(__file__).resolve().parents[1] / "scripts/nightly-app-update.py",
)
assert spec is not None and spec.loader is not None
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)
install_spec = importlib.util.spec_from_file_location(
    "install_nightly_app_update",
    Path(__file__).resolve().parents[1] / "scripts/install-nightly-app-update.py",
)
assert install_spec is not None and install_spec.loader is not None
installer = importlib.util.module_from_spec(install_spec)
install_spec.loader.exec_module(installer)
diagnostic_spec = importlib.util.spec_from_file_location(
    "openclaw_diagnostics",
    Path(__file__).resolve().parents[1] / "scripts/openclaw-diagnostics.py",
)
assert diagnostic_spec is not None and diagnostic_spec.loader is not None
diagnostics = importlib.util.module_from_spec(diagnostic_spec)
diagnostic_spec.loader.exec_module(diagnostics)


def fleet(t3="0.1.3-nightly.20261025.3669", openclaw="2026.10.7"):
    return {key: t3 if key.endswith("t3") else openclaw for key in updater.ATTRS}


def test_no_change():
    assert updater.changed_versions(fleet(), fleet()) == []


def test_auth_readiness_uses_effective_selection_and_hides_profile_identity():
    data = {
        "auth": {
            "oauth": {
                "providers": [
                    {
                        "provider": "openai",
                        "status": "ok",
                        "profiles": [
                            {"profileId": "renewed-private-login", "status": "ok"}
                        ],
                        "effectiveProfiles": [
                            {
                                "profileId": "expired-private-login",
                                "status": "expired",
                                "remainingMs": -1,
                                "expiresAt": 1,
                            }
                        ],
                    }
                ]
            },
            "runtimeAuthRoutes": [{"authStatus": "usable"}],
            "missingProvidersInUse": [],
            "modelRouteIssues": [],
        }
    }
    result = diagnostics.auth_summary(data)
    assert result["selection_ready"] is False
    assert result["providers"][0]["effective"][0]["remaining_ms"] == -1
    assert "private-login" not in str(result)
    data["auth"]["oauth"]["providers"][0]["effectiveProfiles"] = [
        {
            "profileId": "renewed-private-login",
            "status": "ok",
            "remainingMs": 1000,
        }
    ]
    assert diagnostics.auth_summary(data)["selection_ready"] is True
    data["auth"]["runtimeAuthRoutes"][0].update(
        {"status": "unavailable", "runtimeStatus": "unavailable"}
    )
    result = diagnostics.auth_summary(data)
    assert result["selection_ready"] is True
    assert result["runtime_ready"] is False


@pytest.mark.parametrize(
    "finding",
    [
        "config-warning",
        "doctor-warning",
        "doctor-separate-warning",
        "failed-check",
        "runtime-unavailable",
    ],
)
def test_diagnostic_receipt_retains_warnings_and_failures(finding):
    import json

    checks = {
        "config": {"outcome": "passed", "valid": True, "warning_count": 0},
        "doctor": {"outcome": "passed", "ok": True, "findings": [], "warnings": []},
        "health": {"outcome": "passed", "ready": True},
        "ui": {"outcome": "passed", "http_code": 200},
        "nodes": {"outcome": "passed", "nodes": [{"paired": True, "connected": True}]},
        "memory": {"outcome": "passed", "ready": True},
        "agents": {"outcome": "passed", "agents": ["main"]},
        "auth-main": {
            "outcome": "passed",
            "selection_ready": True,
            "runtime_ready": True,
        },
    }
    record = {
        "complete": True,
        "checks": checks,
        "runtime": "/nix/store/runtime",
        "config_path": "/nix/store/config",
        "duration_seconds": 1,
    }
    assert updater.diagnostic_result(json.dumps(record), 0)["outcome"] == "healthy"
    if finding == "config-warning":
        checks["config"]["warning_count"] = 1
    elif finding == "doctor-warning":
        checks["doctor"]["findings"] = [{"severity": "warning"}]
    elif finding == "doctor-separate-warning":
        checks["doctor"] = {
            "outcome": "passed",
            **diagnostics.doctor_summary(
                {
                    "schemaVersion": 1,
                    "ok": True,
                    "checksRun": 1,
                    "checksSkipped": 0,
                    "findings": [],
                    "warnings": [
                        {
                            "checkId": "inspection-incomplete",
                            "severity": "warning",
                            "message": "private-output",
                        }
                    ],
                }
            ),
        }
    elif finding == "runtime-unavailable":
        checks["auth-main"]["runtime_ready"] = False
    else:
        checks["ui"] = {"outcome": "failed", "error": "TimeoutExpired"}
    result = updater.diagnostic_result(json.dumps(record), 0)
    assert result["outcome"] == ("failed" if finding == "failed-check" else "findings")
    assert result["checks"] == checks


def test_diagnostic_timeout_keeps_completed_streamed_checks():
    import json

    check = {"outcome": "passed", "valid": True}
    partial = json.dumps({"check": "config", "result": check}) + '\n{"check":'
    result = updater.diagnostic_result(partial, None)
    assert result["outcome"] == "failed"
    assert result["checks"] == {"config": check}


@pytest.mark.parametrize("schema", [None, 2, True, "1"])
def test_doctor_summary_rejects_unknown_schemas(schema):
    with pytest.raises(ValueError):
        diagnostics.doctor_summary(
            {
                "schemaVersion": schema,
                "ok": True,
                "checksRun": 1,
                "checksSkipped": 0,
                "findings": [],
            }
        )


def test_installation_suppresses_due_old_receipt_until_next_night():
    now = dt.datetime(2026, 10, 31, 15, tzinfo=dt.UTC)
    old = {"outcome": "failed", "night": "2026-10-30"}
    assert updater.attempt_reason(old, now) is None
    deadline = installer.next_dispatch(now)
    policy = {"not_before": deadline.isoformat()}
    assert (
        updater.installation_reason(now, policy, False)
        == "schedule-installation-window"
    )
    assert updater.installation_reason(deadline, policy, False) is None
    assert (
        updater.installation_reason(deadline, policy, True)
        == "schedule-installation-incomplete"
    )


def test_installation_before_two_waits_for_the_upcoming_night():
    now = dt.datetime(2026, 10, 31, 0, 59, tzinfo=dt.UTC)
    assert installer.next_dispatch(now) == dt.datetime(2026, 10, 31, 1, tzinfo=dt.UTC)


def test_schedule_final_verification_failure_restores_prior_plist(tmp_path):
    import plistlib

    target = tmp_path / "schedule.plist"
    prior = plistlib.dumps({"version": "old"})
    target.write_bytes(prior)

    def operate(action, file):
        if action == "verify" and plistlib.loads(file.read_bytes())["version"] == "new":
            raise RuntimeError("verification failed")

    with pytest.raises(RuntimeError):
        installer.replace_agent(target, {"version": "new"}, True, operate)
    assert target.read_bytes() == prior


def test_version_updates_cover_both_hosts():
    assert updater.changed_versions(fleet(), fleet(openclaw="2026.10.8")) == [
        "m1-openclaw",
        "obelisk-openclaw",
    ]


def test_obelisk_only_drift_still_selects_official_release_check():
    installed = fleet(openclaw="2026.10.8")
    installed["obelisk-openclaw"] = "2026.10.7"
    changed = updater.changed_versions(installed, fleet(openclaw="2026.10.8"))
    assert changed == ["obelisk-openclaw"]
    assert updater.changed_apps(changed) == {"openclaw"}


@pytest.mark.parametrize("version", ["unknown", "2026.10.7-rc.1", "", "2026.9.9"])
def test_unknown_versions_and_downgrades_hold(version):
    with pytest.raises(ValueError):
        updater.changed_versions(fleet(), fleet(openclaw=version))


def test_incompatible_host_versions_hold():
    candidate = fleet()
    candidate["m1-openclaw"] = "2026.10.8"
    with pytest.raises(ValueError):
        updater.changed_versions(fleet(), candidate)


def test_missed_night_runs_once_after_wake():
    now = dt.datetime(2026, 10, 31, 10, tzinfo=dt.UTC)
    assert updater.due_day(now, "2026-10-30") == "2026-10-31"
    assert updater.due_day(now, "2026-10-31") is None


def test_repeated_stockholm_dst_hour_runs_once():
    first = dt.datetime(2026, 10, 25, 0, 5, tzinfo=dt.UTC)
    second = dt.datetime(2026, 10, 25, 1, 5, tzinfo=dt.UTC)
    day = updater.due_day(first, None)
    assert day == "2026-10-25"
    assert updater.due_day(second, day) is None


@pytest.mark.parametrize("phase", ["activating", "migrating", "pushing"])
def test_uncertain_mutation_is_never_replayed_next_night(phase):
    now = dt.datetime(2026, 10, 31, 10, tzinfo=dt.UTC)
    assert updater.attempt_reason({"outcome": phase, "night": "2026-10-29"}, now) == (
        "uncertain-mutation-requires-reconciliation"
    )


def test_active_work_defers_even_when_other_runs_finished():
    assert updater.activity_reason(["completed", "running"], []) is not None
    assert updater.activity_reason(["completed"], ["ready"]) is not None
    assert updater.activity_reason(["future-status"], []) is not None
    assert updater.activity_reason(["completed", "failed"], ["closed"]) is None


def test_real_read_only_database_activity_gate(tmp_path):
    import sqlite3

    database = tmp_path / "state.sqlite"
    with sqlite3.connect(database) as connection:
        connection.executescript(
            "CREATE TABLE orchestration_v2_projection_runs (status TEXT);"
            "CREATE TABLE orchestration_v2_projection_provider_sessions (status TEXT);"
            "INSERT INTO orchestration_v2_projection_runs VALUES ('running');"
        )
    assert updater.local_activity(database) == "active-or-unknown-t3-run"
    with sqlite3.connect(database) as connection:
        connection.execute(
            "UPDATE orchestration_v2_projection_runs SET status='completed'"
        )
    assert updater.local_activity(database) is None


def test_release_channel_and_exact_published_version_required():
    release = {
        "tag_name": "v2026.10.9",
        "draft": False,
        "prerelease": False,
        "published_at": "2026-10-29T12:00:00Z",
    }
    updater.validate_release("2026.10.9", release, nightly=False)
    for field, value in [
        ("tag_name", "v2026.10.8"),
        ("draft", True),
        ("prerelease", True),
        ("published_at", None),
    ]:
        with pytest.raises(ValueError):
            updater.validate_release(
                "2026.10.9", {**release, field: value}, nightly=False
            )


def test_unrelated_input_pin_change_rejected():
    import copy

    baseline: dict[str, Any] = {
        "root": "root",
        "nodes": {
            "root": {"inputs": {"nixpkgs": "nixpkgs", "nix-openclaw": "openclaw"}},
            "nixpkgs": {"locked": {"rev": "stable"}},
            "openclaw": {"locked": {"rev": "old"}},
        },
    }
    candidate = copy.deepcopy(baseline)
    candidate["nodes"]["openclaw"]["locked"]["rev"] = "new"
    updater.validate_input_scope(baseline, candidate)
    candidate["nodes"]["nixpkgs"]["locked"]["rev"] = "unrelated"
    with pytest.raises(ValueError):
        updater.validate_input_scope(baseline, candidate)


def test_transitive_scope_handles_node_renames_and_follows():
    import copy

    baseline: dict[str, Any] = {
        "root": "root",
        "nodes": {
            "root": {
                "inputs": {"nix-openclaw": "app", "hunk": "hunk", "nixpkgs": "shared"}
            },
            "app": {"locked": {"rev": "old"}},
            "hunk": {
                "locked": {"rev": "same"},
                "inputs": {"child": "child", "nixpkgs": ["nixpkgs"]},
            },
            "child": {"locked": {"rev": "retained"}},
            "shared": {"locked": {"rev": "shared-pin"}},
        },
    }
    candidate = copy.deepcopy(baseline)
    candidate["nodes"]["child-renamed"] = candidate["nodes"].pop("child")
    candidate["nodes"]["hunk"]["inputs"]["child"] = "child-renamed"
    candidate["nodes"]["app"]["locked"]["rev"] = "new"
    updater.validate_input_scope(baseline, candidate)
    candidate["nodes"]["child-renamed"]["locked"]["rev"] = "unrelated"
    with pytest.raises(ValueError):
        updater.validate_input_scope(baseline, candidate)


def test_failed_build_record_preserves_rollout_and_hides_tool_output(
    tmp_path, monkeypatch
):
    import json
    import subprocess

    rollout = tmp_path / "latest.json"
    rollout.write_text('{"outcome":"migrating","backup":"retained"}')

    def failed_preparation(*_args):
        raise subprocess.CalledProcessError(
            1, ["nix", "build"], output="private-output"
        )

    monkeypatch.setattr(updater, "prepare", failed_preparation)
    assert updater.prepare_recorded(tmp_path, tmp_path / "candidate", tmp_path) is False
    assert json.loads(rollout.read_text())["outcome"] == "migrating"
    evidence = (tmp_path / "preparation.jsonl").read_text()
    assert "private-output" not in evidence
    assert (
        json.loads((tmp_path / "preparation.json").read_text())["outcome"] == "failed"
    )


@pytest.mark.parametrize("invalid_utf8", [False, True])
def test_command_failure_evidence_excludes_arguments_output_and_environment(
    tmp_path, invalid_utf8
):
    import json
    import os
    import subprocess
    import sys

    evidence = tmp_path / "steps.jsonl"
    token = updater.STEP_LOG.set(evidence)
    try:
        with pytest.raises(
            (subprocess.CalledProcessError, UnicodeDecodeError)
        ) as caught:
            updater.run(
                [
                    sys.executable,
                    "-c",
                    "import sys; sys.stdout.buffer.write(b'\\xff')"
                    if invalid_utf8
                    else "import sys; print('private-output'); sys.exit(7)",
                    "private-argument",
                ],
                tmp_path,
            )
        details = updater.failure_details(caught.value)
    finally:
        updater.STEP_LOG.reset(token)
    assert details["step"] == "subprocess"
    if not invalid_utf8:
        assert details["exit_code"] == 7
        assert json.loads(evidence.read_text().splitlines()[-1])["exit_code"] == 7
    else:
        assert json.loads(evidence.read_text().splitlines()[-1])["outcome"] == "failed"
    serialized = evidence.read_text() + json.dumps(details)
    assert "private-output" not in serialized
    assert "private-argument" not in serialized
    assert str(tmp_path) not in serialized
    assert sys.executable not in serialized
    assert os.environ.get("PATH", "private-path") not in serialized


def test_discard_candidate_cannot_delete_outside_its_owned_clone(tmp_path):
    owned = tmp_path / "runs/night/candidate"
    owned.mkdir(parents=True)
    (owned / "temporary-source").write_text("disposable")
    updater.discard_candidate(owned, tmp_path)
    assert not owned.exists()
    outside = tmp_path / "private-state"
    outside.mkdir()
    (outside / "keep").write_text("retained")
    link = tmp_path / "runs/night/candidate"
    link.symlink_to(outside, target_is_directory=True)
    with pytest.raises(ValueError):
        updater.discard_candidate(link, tmp_path)
    with pytest.raises(ValueError):
        updater.discard_candidate(outside, tmp_path)
    assert (outside / "keep").read_text() == "retained"


def test_push_failure_retains_exact_commit_and_stops_replay(tmp_path):
    import json
    import subprocess

    origin = tmp_path / "origin.git"
    subprocess.run(
        ["git", "init", "--bare", str(origin)], check=True, capture_output=True
    )
    candidate = tmp_path / "candidate"
    candidate.mkdir()

    def git(*args):
        return subprocess.run(
            ["git", *args], cwd=candidate, check=True, capture_output=True, text=True
        ).stdout.strip()

    git("init", "-b", "main")
    git("config", "user.name", "Updater test")
    git("config", "user.email", "updater@example.invalid")
    (candidate / "nix").mkdir()
    lock = candidate / "nix/flake.lock"
    lock.write_text('{"version":1}')
    git("add", ".")
    git("commit", "-m", "initial")
    base = git("rev-parse", "HEAD")
    git("remote", "add", "origin", str(origin))
    git("push", "origin", "HEAD:main")
    hook = origin / "hooks/pre-receive"
    hook.write_text("#!/bin/sh\necho private-push-output >&2\nexit 1\n")
    hook.chmod(0o700)
    lock.write_text('{"version":2}')
    with pytest.raises(subprocess.CalledProcessError):
        updater.push_candidate(
            candidate, {"source": base, "lock": {"version": 2}}, tmp_path, "2026-10-31"
        )
    receipt = json.loads((tmp_path / "latest.json").read_text())
    assert receipt["outcome"] == "pending-push"
    assert receipt["phase"] == "push-pins"
    assert receipt["step"] == "pins-push"
    assert receipt["exit_code"] == 1
    assert "private-push-output" not in (tmp_path / "latest.json").read_text()
    assert receipt["commit"] == git("rev-parse", "HEAD")
    assert git("--git-dir", str(origin), "rev-parse", "refs/heads/main") == base
    assert (
        updater.attempt_reason(receipt, dt.datetime(2026, 11, 1, 10, tzinfo=dt.UTC))
        == "uncertain-mutation-requires-reconciliation"
    )


def test_runtime_identity_rejects_candidate_config_argument():
    package = "/nix/store/candidate-openclaw"
    assert updater.runtime_matches(package + "/bin/openclaw node run", package)
    assert updater.runtime_matches(
        "/nix/store/node/bin/node " + package + "/lib/openclaw.mjs node run", package
    )
    assert not updater.runtime_matches(
        "/nix/store/old/bin/openclaw --config " + package + "/config.json", package
    )
    assert not updater.runtime_matches(
        "/nix/store/node/bin/node /nix/store/old/app.mjs --config "
        + package
        + "/config.json",
        package,
    )
    assert not updater.runtime_matches(package + "-other/bin/openclaw", package)


def test_failed_process_creation_is_retryable_without_live_mutation(
    tmp_path, monkeypatch
):
    import json

    task = tmp_path / "task.md"
    task.write_text("No live operations in this test")
    monkeypatch.setenv("PATH", "")
    with pytest.raises(updater.MaintenanceNotStarted) as caught:
        updater.launch_maintenance(tmp_path, tmp_path, task, {})
    details = updater.failure_details(caught.value)
    assert details["step"] == "maintenance-agent"
    assert details["errno"] == 2
    assert (tmp_path / "agent.log").read_text() == ""
    monkeypatch.setattr(
        updater, "prepare", lambda *_a, **_kw: {"outcome": "prepared", "changed": []}
    )
    monkeypatch.setattr(updater, "idle_reason", lambda: None)
    monkeypatch.setattr(updater, "diagnose", lambda *_args: None)
    monkeypatch.setattr(updater, "build_candidates", lambda *_a: {})
    updater.scheduled(tmp_path, tmp_path, task)
    receipt = json.loads((tmp_path / "latest.json").read_text())
    assert receipt["outcome"] == "failed"
    assert receipt["step"] == "maintenance-agent"
    assert receipt["errno"] == 2
    tomorrow = dt.datetime.now(dt.UTC) + dt.timedelta(days=1)
    assert updater.attempt_reason(receipt, tomorrow) is None


@pytest.mark.parametrize("consume_prompt", [False, True])
def test_started_maintenance_failure_holds_replay_and_records_status(
    tmp_path, monkeypatch, consume_prompt
):
    import json
    import subprocess
    import sys

    task = tmp_path / "task.md"
    task.write_text("No live operations\n" * 100000)
    popen = subprocess.Popen

    def failed_agent(_args, **kwargs):
        return popen(
            [
                sys.executable,
                "-c",
                "import sys; "
                + ("sys.stdin.read(); " if consume_prompt else "")
                + "print('private-output'); sys.exit(7)",
            ],
            **kwargs,
        )

    monkeypatch.setattr(updater.subprocess, "Popen", failed_agent)
    monkeypatch.setattr(updater.time, "sleep", lambda _seconds: None)
    monkeypatch.setattr(
        updater, "prepare", lambda *_a, **_kw: {"outcome": "prepared", "changed": []}
    )
    monkeypatch.setattr(updater, "idle_reason", lambda: None)
    monkeypatch.setattr(updater, "diagnose", lambda *_args: None)
    monkeypatch.setattr(updater, "build_candidates", lambda *_a: {})
    updater.scheduled(tmp_path, tmp_path, task)
    receipt = json.loads((tmp_path / "latest.json").read_text())
    assert receipt["outcome"] == "uncertain"
    assert receipt["step"] == "maintenance-agent"
    assert isinstance(receipt["exit_code"], int)
    if consume_prompt:
        assert receipt["exit_code"] == 7
    steps = next((tmp_path / "runs").glob("*/steps.jsonl")).read_text()
    assert json.loads(steps.splitlines()[-1])["exit_code"] == receipt["exit_code"]
    assert "private-output" not in steps + json.dumps(receipt)
    assert (
        updater.attempt_reason(receipt, dt.datetime.now(dt.UTC) + dt.timedelta(days=1))
        == "uncertain-mutation-requires-reconciliation"
    )
    assert (
        updater.failure_details(updater.MaintenanceFailed(limit="deadline"))[
            "timed_out"
        ]
        is True
    )
    assert (
        updater.failure_details(updater.MaintenanceFailed(limit="output-capacity"))[
            "limit"
        ]
        == "output-capacity"
    )
