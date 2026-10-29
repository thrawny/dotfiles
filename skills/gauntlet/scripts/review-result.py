#!/usr/bin/env python3
"""Publish the versioned launcher/skill result; never infer convergence from exit."""

import json
import os
import runpy
import sys
from pathlib import Path


def build(directory, outcome=None):
    directory = Path(directory)
    meta = dict(
        line.split(": ", 1)
        for line in (directory / "meta.txt")
        .read_text()
        .split("--- brief ---")[0]
        .splitlines()
        if ": " in line
    )
    reviewers = []
    for engine in meta["reviewers"].split(","):
        events = [
            json.loads(line)
            for line in (directory / f"{engine}.attempts.jsonl")
            .read_text()
            .splitlines()
        ]
        last = events[-1]
        reviewers.append(
            dict(
                engine=engine,
                reasonClass=last["state"],
                reasonCode=last["state"],
                attempts=sum(e["state"] == "running" for e in events),
                maxAttempts=3,
                retryable=False,
                retryBudgetExhausted=last.get("exhausted", False),
                resetAt=last.get("resetAt"),
                evidence=str(directory / f"{engine}.attempts.jsonl"),
            )
        )
    current = runpy.run_path(str(Path(__file__).with_name("retry-review.py")))[
        "fingerprint"
    ](meta["scope"], meta.get("repo_root"))
    if any(
        json.loads(
            (directory / f"{r['engine']}.attempts.jsonl").read_text().splitlines()[0]
        )["fingerprint"]
        != current
        for r in reviewers
    ):
        for reviewer in reviewers:
            reviewer["reasonClass"] = reviewer["reasonCode"] = "scope-changed"
    complete = all(r["reasonClass"] == "ok" for r in reviewers)
    exhausted = any(r["retryBudgetExhausted"] for r in reviewers)
    if outcome not in (None, "converged", "capped", "escalated"):
        raise ValueError("unknown adjudicated outcome")
    if outcome and not complete:
        raise ValueError("failed review cannot have an adjudicated outcome")
    return dict(
        schemaVersion=1,
        kind="gauntlet-review-result",
        outcome=outcome
        or ("review-complete" if complete else "exhausted" if exhausted else "blocked"),
        reasonClass="adjudicated"
        if outcome
        else "review-complete"
        if complete
        else "reviewer-failure",
        reasonCode=outcome
        or (
            "all-selected-completed"
            if complete
            else "retry-budget-exhausted"
            if exhausted
            else "selected-reviewer-blocked"
        ),
        retryable=False,
        retryOwner="gauntlet",
        retryBudgetExhausted=exhausted,
        reviewedHead=meta["head_sha"],
        repoRoot=meta.get("repo_root"),
        scope=meta["scope"],
        fingerprint=events[0]["fingerprint"],
        round=int(meta["round"]),
        roundIdentity=str(directory.resolve()),
        ledger=str(directory.parent / "ledger.md"),
        priorLedger=meta["prior_ledger"],
        completedReviewRound=complete,
        reviewers=reviewers,
    )


def publish(directory, outcome=None):
    result = build(directory, outcome)
    if not result["completedReviewRound"]:
        meta_file = Path(directory) / "meta.txt"
        meta_file.write_text(
            meta_file.read_text().replace(
                "completed_review_round: yes", "completed_review_round: no"
            )
        )
    target = Path(directory) / "result.json"
    temporary = target.with_suffix(".tmp")
    with temporary.open("w") as stream:
        json.dump(result, stream, indent=2)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    temporary.replace(target)
    return target


def settled(directory, expected=None):
    journals = list(Path(directory).glob("*.attempts.jsonl"))
    terminal = {
        "ok",
        "transient",
        "auth",
        "quota",
        "human-stop",
        "terminal",
        "scope-changed",
        "empty-result",
        "output-error",
    }
    try:
        return (
            bool(journals)
            and (expected is None or len(journals) == expected)
            and all(
                json.loads(p.read_text().splitlines()[-1])["state"] in terminal
                for p in journals
            )
        )
    except (OSError, ValueError, IndexError, KeyError):
        return False


if __name__ == "__main__":
    if sys.argv[1] == "--settled":
        sys.exit(0 if settled(sys.argv[2], int(sys.argv[3])) else 1)
    target = publish(*sys.argv[1:])
    print(target)
    sys.exit(0 if json.loads(target.read_text())["completedReviewRound"] else 1)
