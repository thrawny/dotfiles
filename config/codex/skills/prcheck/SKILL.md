---
name: prcheck
description: Monitor the pull request associated with the current branch and address issues until it is ready to merge. Use when the user says `/prcheck`, asks to watch PR status, or wants CI failures, review comments, merge conflicts, or mergeability issues handled in a loop.
---

# prcheck

Monitor the current branch's pull request and fix what can be fixed.

## Workflow

1. Resolve the PR for the current branch. If none exists, say so and suggest creating one.
2. Use a wait interval from the user when provided. Otherwise default to 120 seconds.
3. Wait first, then do the first status check.
4. Inspect PR state, mergeability, review decision, checks, and recent review comments.
5. Use the GitHub app when it gives better structured context. Use `gh` for checks, logs, or any gaps.
6. If checks are pending, keep waiting and re-checking.
7. If issues appear, address them directly:
   - failing CI
   - review feedback
   - merge conflicts
   - build or test failures
8. Continue until checks are passing, the PR is mergeable, and there is no outstanding action left for Codex.
9. If manual intervention is required, explain exactly what is blocked.

## Status output

Each loop should include:

- timestamp
- current check/review state
- actions taken, if any
- remaining blockers, if any

## Guardrails

- Do not stop at the first failure; keep iterating until the PR is either healthy or genuinely blocked.
- Distinguish pending from failing.
- Prefer concrete root-cause fixes over retrying blindly.
