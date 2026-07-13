---
name: pr
description: Drive a pull request to terminal readiness through a review-fix-monitor loop. Use when the user asks to create, update, check, or fix a PR; address review feedback; monitor CI or agent reviewers; or keep a PR green.
---

# Pull Request Loop

Create or resume the current branch's pull request, then keep looping until it is ready to merge or genuinely blocked. A narrower user request, such as status-only or one-pass review, takes precedence.

Set `PR_SKILL_DIR` to the directory containing the exact `SKILL.md` loaded for this run. The helper path below is relative to that directory, never to the repository working directory. Invoke it as `"$PR_SKILL_DIR/scripts/pr" <subcommand>`.

## 1. Establish the PR

Inspect the branch, worktree, remote, and existing PR. Push task-related commits when needed; create a PR only when one does not already exist.

For a new PR, explain:

- **Goal** — the user or engineering outcome.
- **Reviewer focus** — likely correctness, regression, test, security, or data-loss risks.
- **Deliberate choices** — accepted trade-offs, limitations, and scope boundaries reviewers should preserve.

Omit ceremonial lists of successful local checks. If behavior or scope changes later, update the PR title/body so reviewers do not evaluate a stale contract.

Before expensive final validation or reviewer waits, check whether the branch is behind its base. Update it according to repository policy first; do not choose rebase versus merge when that policy or the user's intent is unclear. Re-run relevant validation after updating.

This step is complete when the current branch has an accurate PR and its remote state is current.

## 2. Take a bounded snapshot

Run `snapshot` instead of assembling large `gh pr view`, REST, and GraphQL payloads by hand:

```bash
"$PR_SKILL_DIR/scripts/pr" snapshot [<pr>]
```

Use `--json` only when structured output is useful. The snapshot separates:

- current, failed, pending, and absent checks;
- current-head, stale, resolved, and unresolved review threads;
- active or finished optional AI reviewers;
- machine blockers from required human approval.

Treat commit IDs, Codex's `Reviewed commit` marker, and GitHub's outdated state as stronger freshness evidence than timestamps. Never fix an old-head finding blindly.

If checks failed, retrieve bounded diagnostics with:

```bash
"$PR_SKILL_DIR/scripts/pr" failed-checks [<pr>]
```

It saves complete GitHub Actions logs under `/tmp` and prints only bounded failure excerpts. External checks are reported with their links.

## 3. Wait without consuming the agent turn

When checks or an AI reviewer are still running, launch the waiter with background Bash instead of writing a polling loop:

```text
bash({
  command: "\"$PR_SKILL_DIR/scripts/pr\" wait [<pr>] --timeout 20m",
  timeout: 600,
  background: true
})
```

For background Bash, `timeout` is an early wake-up: it triggers an agent turn if the command is still running but leaves the zmx task alive and still watched for completion. The waiter's own `--timeout` is its actual maximum wait. Do not wrap the command with the shell `timeout` executable.

The waiter:

- allows checks a short activation grace and supports repositories with no checks;
- treats AI reviewers as optional;
- waits while Codex has an eyes reaction;
- treats a current-head Codex comment, review, or thumbs-up as completion;
- degrades instead of blocking forever when a reviewer is absent or unavailable;
- resets all observed state when the PR head changes.

Use `--require-checks` only when the repository must publish at least one check. Script success means signals settled, not that checks passed or reviewers found nothing. Run `snapshot` again after it wakes the agent.

Do not manually post `@codex review` after every push when the repository automatically reviews pushes. Trigger it only when repository behavior requires manual activation or Codex stayed inactive beyond the grace period and a new review is actually needed. Avoid duplicate review requests.

## 4. Fix and close the loop

For each actionable issue:

1. Verify it against the code, current head, and intended scope.
2. Apply a focused fix and run relevant validation.
3. Commit and push the correction when the remote PR needs it.
4. Reply with concise evidence when useful.
5. Explicitly resolve the handled review thread.

List bounded thread details and IDs with:

```bash
"$PR_SKILL_DIR/scripts/pr" threads list [<pr>]
```

Resolve only threads whose disposition you have verified:

```bash
"$PR_SKILL_DIR/scripts/pr" threads resolve <thread-id> [<thread-id> ...]
```

A reply such as “Fixed in …” does not resolve a GitHub thread. Resolve fixed findings, documented false positives, and intentional/deferred choices only when their disposition is complete. Leave genuine blockers and needs-human decisions unresolved. Surface permission or tool failures rather than claiming resolution.

Every push, base update, retry, or resolved comment invalidates the previous snapshot: return to step 2. A new push may trigger another reviewer pass, and that pass belongs to the same loop.

## Terminal criterion

Finish only when the latest snapshot shows:

- no failed or pending required checks;
- no merge conflicts or required base update;
- no actionable current-head finding;
- no handled-but-unresolved review thread;
- no active reviewer;
- an otherwise mergeable PR.

Required human approval is a terminal handoff, not a reason to poll indefinitely. Report it separately from machine blockers. Otherwise continue the loop or report the specific blocker requiring user input.
