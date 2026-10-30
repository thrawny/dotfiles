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


def fleet(t3="0.1.3-nightly.20261025.3669", openclaw="2026.10.7"):
    return {key: t3 if key.endswith("t3") else openclaw for key in updater.ATTRS}


def test_no_change():
    assert updater.changed_versions(fleet(), fleet()) == []


def test_version_updates_cover_both_hosts():
    assert updater.changed_versions(fleet(), fleet(openclaw="2026.10.8")) == [
        "m1-openclaw",
        "obelisk-openclaw",
    ]


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
    hook.write_text("#!/bin/sh\nexit 1\n")
    hook.chmod(0o700)
    lock.write_text('{"version":2}')
    with pytest.raises(subprocess.CalledProcessError):
        updater.push_candidate(
            candidate, {"source": base, "lock": {"version": 2}}, tmp_path, "2026-10-31"
        )
    receipt = json.loads((tmp_path / "latest.json").read_text())
    assert receipt["outcome"] == "pending-push"
    assert receipt["commit"] == git("rev-parse", "HEAD")
    assert git("--git-dir", str(origin), "rev-parse", "refs/heads/main") == base
    assert (
        updater.attempt_reason(receipt, dt.datetime(2026, 11, 1, 10, tzinfo=dt.UTC))
        == "uncertain-mutation-requires-reconciliation"
    )
