---
name: pr
description: Drive a pull request to terminal readiness through a review-fix-monitor loop. Use when the user asks to create, update, check, or fix a PR; address review feedback; monitor CI or agent reviewers; or keep a PR green.
---

# Pull Request Loop

Create or resume the current branch's pull request, then keep looping until it is ready to merge or genuinely blocked. A narrower user request, such as status-only or one-pass review, takes precedence.

## 1. Establish the PR

Inspect the branch, worktree, remote, and existing PR. Push task-related commits when needed; create a PR only when one does not already exist.

For a new PR, explain:

- **Goal** — the user or engineering outcome.
- **Reviewer focus** — likely correctness, regression, test, security, or data-loss risks.
- **Deliberate choices** — accepted trade-offs, limitations, and scope boundaries reviewers should preserve.

Omit ceremonial lists of successful local checks.

This step is complete when the current branch has an accurate PR and its remote state is current.

## 2. Inspect every readiness signal

Check CI, mergeability, reviews, inline comments, unresolved threads, and active reviewer reactions. An eyes reaction from Codex means its review is still running; wait or poll until it posts a result.

This step is complete when every current blocker and actionable finding is accounted for.

## 3. Fix and close the loop

For each actionable issue:

1. Verify it against the code and intended scope.
2. Apply a focused fix and run relevant validation.
3. Commit and push the correction when the remote PR needs it.
4. Resolve or mark the handled review thread as complete when the platform permits.

Report false positives or intentional choices with the reason. Surface tool, permission, ambiguity, or external failures that prevent resolving a thread.

Every push, retry, or resolved comment invalidates the previous snapshot: return to step 2. A new push may trigger another Codex review, and that review belongs to the same loop.

## Terminal criterion

Finish only when checks pass, the PR is mergeable, no actionable review item or handled resolvable thread remains, and active reviewers have reached a final result. Otherwise continue monitoring or report the specific blocker requiring user input.
