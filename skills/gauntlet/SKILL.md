---
name: gauntlet
description: Review current changes with Claude (Opus) by default, or an explicitly selected Codex reviewer, verify findings, fix major implementation bugs and summarize. Use for gauntlet review-and-fix requests or loops to convergence.
---

# Gauntlet

Run the current diff through the configured reviewers, **fix the major issues by default**, and summarize. Claude `/code-review` on Opus 5.5 runs by default; Codex `review` runs only when a run selects it. When both run, merge their findings: the engines mostly surface *different* findings, so their union improves recall. Confidence comes from per-finding verification (§4), not from agreement.

Reviewer selection and launch are handled by the bundled `scripts/gauntlet-review` launcher; this skill owns the judgment around it.

This skill is tuned for **recall at generation time and precision at judgment time**. The reviewers are deliberately asked to be exhaustive, so expect more raw findings than pass the bar — including some false positives. That is the intended shape: a finding you never generate cannot be caught in step 4, but a bad one can. Do not try to restore precision by softening the launcher's prompts; restore it by verifying and declining in step 4.

Default behavior: fix major findings (high severity, or P1–P2 when Codex runs) that triage as implementation bugs; design gaps and scope increases are escalated or deferred, not autofixed (§4). Minor and declined findings are reported, not fixed. If the user asks for report-only, do steps 1–3 and skip the fixing.

One run is one sample. When the user wants the change actually driven to convergence — before pushing, before a PR, or when they ask to "loop" or "keep going until it's clean" — follow the loop protocol in §6, whose terminal rules decide which round ends the loop.

## 1. Build a context brief (this is what scopes the review)

The brief is the local stand-in for a PR description — without it, reviewers flag intentional choices as bugs. Write a short brief covering:

- **Intent** — what this change does and why.
- **Original task / goal** it serves.
- **Deliberate choices** reviewers should NOT flag (intentional tradeoffs, accepted limitations).
- **Out of scope** — areas not to comment on (pre-existing code, unrelated files).

Derive it from the conversation, the task, commit messages, or the PR description. If the intent is genuinely unclear, ask the user one question rather than guessing — a wrong brief produces wrong findings. The script passes this brief verbatim to the selected reviewers, and adds the scope and self-verification instructions itself.

## 2. Run the reviewers

The launcher is bundled at `scripts/gauntlet-review` in this skill's directory. Invoke it by its full path (substitute this skill's directory for `<skill-dir>`):

```bash
bash <skill-dir>/scripts/gauntlet-review "<your context brief>"
```

- Scope is auto-detected: the current branch's diff against origin's remote-tracking default branch (for example, `origin/main`), or uncommitted changes when already on the corresponding local branch. Override with `--base <branch>`, `--uncommitted`, or `--commit <sha>` (before the brief). For a long brief, pipe it on stdin with a trailing `-`.
- Claude runs by default. Run Codex only when the user asks for it, and select it on each invocation: `--reviewers codex` or `--reviewers claude,codex`, or `GAUNTLET_REVIEWERS` set on that one command. In a loop, pass the same selection every round. An unset or empty variable uses Claude, and the flag overrides the variable. For example, `bash <skill-dir>/scripts/gauntlet-review --reviewers claude,codex "<brief>"` runs both. Never export `GAUNTLET_REVIEWERS` into a shell, service or job environment. Unlike quota degradation this is deterministic: a deselected engine never runs, even if its quota comes back mid-loop. A single-reviewer run generates a smaller union of findings — expect lower recall, not lower precision; verification (step 4.1) is unchanged.
- It runs the selected reviewers (in parallel when both are selected) and prints two delimited blocks labeled with each reviewer's state — `===== CLAUDE REVIEW [ok] =====` and `===== CODEX REVIEW [ok] =====`. **Reviews take 5–20 minutes. If the harness offers managed background execution that notifies on completion, launch the command that way and continue other work until the notification arrives. Only without such a mechanism, run it in the foreground with the longest timeout available.**
- The Claude reviewer is pinned to `claude-opus-5-5` (subagents and fallbacks included) and ignores the user's model settings. Its effort defaults to `high`. Set `GAUNTLET_CLAUDE_EFFORT` to `low`, `medium`, `high`, `xhigh` or `max` to change it, as `GAUNTLET_CODEX_EFFORT` does for Codex; an unknown value stops the run before review. The effort is also passed as the `/code-review` level, so it changes the review recipe as well as reasoning effort, and `max` is the costliest.
- **Claude login.** Claude Code strips `CLAUDE_CODE_OAUTH_TOKEN` from its tool subprocesses, so a gauntlet started from a Claude session cannot inherit it. When the environment has no Claude credential (`CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_API_KEY` or similar), the launcher reads the token from `$GAUNTLET_CLAUDE_TOKEN_FILE`, default `~/.config/gauntlet/claude-oauth-token` (under `$XDG_CONFIG_HOME` when set). The file holds only the token from `claude setup-token`, mode 600. It is read, never sourced, and only the reviewer process receives the token. A token in the environment takes precedence. A missing, empty or group/world-accessible file, or `SANDBOX` without an environment token, blocks the reviewer with the reason in its evidence. A Claude run that called no model, such as a login or 401 refusal, is blocked too, not a review.
- When Codex is selected, its reasoning effort defaults to `high`; change it for that run with `GAUNTLET_CODEX_EFFORT` or the model with `GAUNTLET_CODEX_MODEL`.
- Every run saves each reviewer's raw output, the reviewed SHA, and the brief under a per-repo/per-branch state dir, and prints a `===== GAUNTLET STATE =====` footer with the round number, the output path, and the ledger path. **Note those paths** — the raw output is how you re-check a dedupe decision without paying for another 5–20 minute round.
- If this branch already has a `ledger.md` (see §6), the launcher picks it up automatically and tells the reviewers not to repeat findings already adjudicated there. A `NOTE:` line always says which ledger was used. Suppress it with `--no-prior`, or point elsewhere with `--prior <file>`.
- **Infrastructure retries:** the launcher retries only the failed reviewer, serially, with the same command/model/provider: at most three attempts and five minutes of retry scheduling per reviewer, with 30/60 second exponential backoff (120 second ceiling). A later `resetAt` (epoch seconds or ISO timestamp) or numeric `Retry-After` takes precedence; if it exceeds the budget, stop blocked. Running review time also counts toward that scheduling budget; individual reviewer duration is not limited. Capacity, rate-limit and temporary transport failures qualify; auth, quota, configuration, human stop, unknown failures and exhausted retries block. Partial findings stay available for triage, but all selected reviewers must succeed before the round can be dry or end the loop in any adjudicated state (§6). Read the failure evidence instead of launching another invocation to reset its budget.
- `resetAt` is the provider-supplied absolute instant normalized to RFC3339 UTC, or null when absent/invalid; timezone-free timestamps are invalid. Numeric `Retry-After` affects only local `next_attempt_at`, never `resetAt` or budget renewal. Interrupted attempts have no automatic restart/resume path: preserve their evidence and budgets for human inspection.
- **Structured handoff:** consume the atomically published `result.json` (`schemaVersion: 1`, `kind: gauntlet-review-result`), never assistant completion prose. It carries outcome/reason, reviewer attempts/maxAttempts, retry budget exhaustion, reset time, exact reviewed head/fingerprint, round identity and ledger path. Launcher outcomes are `review-complete`, `blocked`, or `exhausted`; terminal results always have `retryable: false` and `retryOwner: gauntlet`. `review-complete` requires triage and is not convergence. After judging the loop terminal state in §6, publish it with `python3 <skill-dir>/scripts/review-result.py <round-dir> <outcome>`, where `<outcome>` is `converged`, `minor-only`, `round-limit`, `capped` or `escalated`. Failed reviews reject adjudicated outcomes. Supervisors fail closed on absent/unknown evidence and never reset these budgets.
- Each reviewer writes an fsynced `<engine>.attempts.jsonl` with launch intent, exact command, scope fingerprint, raw output paths, retry owner, next attempt time and terminal/exhaustion evidence. A branch lock prevents concurrent launcher invocations. An interrupted invocation with an unknown active outcome requires inspecting and settling the process before removing a stale `active.lock`; never replay an unknown attempt. Factory/supervisor callers consume this evidence and leave infrastructure retries to `gauntlet` rather than wrapping it in another retry loop.
- The recorded `round` is an invocation ID, including blocked invocations. Count only `completed_review_round: yes` in `meta.txt` toward the round limits in §6 (three rounds, five at most); infrastructure attempts do not consume completed review rounds or count as dry. A terminal infrastructure outcome is **Blocked**, never one of the adjudicated states. When resuming, keep counting from the rounds already completed and keep any extra rounds the user granted. The recorded HEAD plus fingerprint covers tracked changes and untracked content; any change during review or backoff blocks result use. Scope changes require a fresh review, never continuation of the old result.


## 3. Dedupe

With one reviewer there is nothing to merge: list its findings and go to step 4. When both ran, merge the blocks into one set of unique issues:

- Two findings are the **same issue** when they point at the same file and overlapping location *and* describe the same root cause — even if worded or scored differently. Merge them.
- For each unique issue, record who raised it: `claude`, `codex`, or **both**. This is telemetry, not confidence — every major finding gets the same verification in step 4.1 regardless of source. Two independent engines mostly find *different* things; a single-source finding is the normal case, not a mark against it, and agreement changes nothing about how a finding is handled.
- Claude scores high/medium/low and Codex scores P1/P2/P3. Map P1/P2/P3 to high/medium/low, and on conflict take the higher.

## 4. Triage, then fix

For each finding that is **major** (high severity, or Codex P1–P2):

1. **Verify it against the real code first** — open the file and adjacent code and confirm the bug is real, in scope, and not already handled. Reading is usually enough; the gates were green before this run, so re-running them settles nothing. Probe directly only when the finding hinges on a case no test covers. This verification is the *primary* false-positive guard — the reviewers are asked to be exhaustive precisely because this step exists, so it is not optional and a healthy run declines a real share of findings. A false positive, a choice the brief marks intentional, or an out-of-scope finding is **declined** with the reason recorded — do not blindly apply findings.
2. **Classify the fix, not the finding.** A verified-real finding is not automatically autofixable — what matters is what its fix would do. The change's **boundary** is the blueprint when one exists (its filetree is the set of touchable files; Decisions and Will-not-touch are the recorded calls); otherwise it is the footprint and evident intent of the diff under review.
   - **Implementation bug** — the fix corrects code against something that already exists (a recorded decision, an existing invariant, the change's own intent) and stays inside the boundary. Fix it. Blueprint silence on the detail is fine — the interior of the boundary is implementor discretion.
   - **Design gap** — the fix would contradict a recorded decision, touch files outside the boundary, or create something new that outlives this diff: a new interface, public API shape, config surface, dependency direction, or invariant. Do **not** fix it, however small the diff looks — a small fix that makes an unowned decision is scope damage, not progress. Ledger it and escalate (below).
   - **Scope increase** — real, but serves work the user never asked for. Ledger as deferred, report as follow-up work, don't fix.
3. Fix implementation bugs surgically: address the finding, don't expand scope or refactor unrelated code.

**Escalation:** finish the round — verify, classify, and fix the remaining implementation bugs — then stop the loop and put the design gaps to the user as a batch, each stated as the decision it requires, with your recommendation. Never start another round with design gaps unresolved: their resolution changes the code the next round would review. When a blueprint exists, record the resolution in it first, then implement. Conflicting findings (two fixes that can't both be applied) escalate the same way.

Commit the fixes, then record every finding in the ledger (§6) with its verdict — fixed with the commit SHA, declined with the reason, design gap with the decision it requires, or deferred as scope. Leave **minor** findings (medium/low, or Codex P3) as a reported list — don't fix them unless the user asks, but still ledger them, or the next round re-raises them.

Committing is not just hygiene when looping. On a branch the scope is `git diff <base>...HEAD`, which is **committed work only**: uncommitted fixes are invisible to the next round, so it re-finds everything you just fixed and the loop cannot converge. The inverse holds on the default branch, where the scope is `--uncommitted` — committing there empties the scope and the next round reports a false dry round. So: **commit between rounds on a branch, never on the default branch.**

## 5. Summarize

Present one unified report, highest severity first:

| Severity | Location | Issue | Flagged by | Status |
|----------|----------|-------|------------|--------|
| high | `path:line` | one-line description | both | fixed |
| high | `path:line` | … | claude | declined (false positive: …) |
| high | `path:line` | … | both | design gap (escalated: needs decision on …) |
| medium | `path:line` | … | codex | deferred (scope: …) |
| medium | `path:line` | … | claude | reported |

Close with a one-line tally: total unique findings, how many both reviewers agreed on (when both ran), how many were fixed vs declined vs escalated as design gaps vs deferred vs left as minor, whether either reviewer failed to run, and, in a §6 loop, the terminal state and the completed rounds used.

## 6. The ledger, and looping to convergence

One gauntlet is one sample, and one sample does not exhaust a diff. Measured against the hosted Codex PR reviewer on real PRs: it re-reads the **full** diff every round rather than just the new commits, and roughly two-thirds of what its later rounds found sat in code an earlier round had already read and passed over. Extra rounds pay not because the reviewer gets smarter but because a diff is not exhausted in one pass.

That only works with a memory. Without one, round 2 spends its reviews re-deriving round 1's findings and you dedupe the duplicates away — you paid for the round and got the remainder. The ledger is what turns the next round outward onto new ground, and it is the same mechanism the hosted reviewer uses.

**The ledger** lives at the path the launcher prints (`<state-dir>/<repo>/<branch>/ledger.md`), outside the working tree so it never lands inside its own review. One line per finding, appended at the end of each round's step 4:

```
- path:line — severity — one-line description — **fixed** in <sha>
- path:line — severity — one-line description — **declined**: <why>
- path:line — severity — one-line description — **design gap**: <the decision it requires; update with the resolution and fix SHA once made>
- path:line — severity — one-line description — **deferred (scope)**: <why it's beyond the ask>
- path:line — severity — one-line description — **minor, not fixed**
```

Record **declined findings too, with the reason.** They are the ones that come back every round otherwise, and a loop whose dry-round counter keeps getting reset by the same false positives never terminates. The reason is also what lets a later review overturn a wrong decline — the launcher explicitly invites reviewers to challenge a decline whose stated reason is factually wrong, which is the one place this beats the hosted reviewer, since GitHub only shows it a resolved thread.

**The loop:**

1. Run the gauntlet (steps 1–5). The ledger is picked up automatically from round 2 on.
2. Fix, commit, append every finding to the ledger with its verdict.
3. A round is **dry** when it surfaces nothing that isn't already in the ledger. Judge that against the *whole* ledger — fixed, declined, and minor alike — not just what you fixed. Open **design gap** entries don't count against dryness: they clear through the user (§4), not through more rounds, so an otherwise-dry round with unresolved design gaps is still dry.
4. After each round, check the terminal states below in order; the first that matches ends the loop, and the final summary must name it. A loop that stops on the round limit looks identical to one that converged unless the report says which. A **major blocker** is a verified major implementation bug (§4) that this round fixed, so no round has reviewed the fix yet. A round's **new findings** are the findings it raised that weren't in the ledger before this round, minus those declined in §4 step 1; minor findings count without verification. Round numbers here count completed review rounds, not the launcher's invocation ID, which includes blocked invocations.
   - **Blocked**: a selected reviewer failed or its retry budget expired. Report the evidence and wait for resolution. A blocked invocation is not a completed round, and it never matches any state below.
   - **Escalated**: the round raised design gaps, now batched for the user (§4). Not a failure; the loop resumes after they're resolved, and the resolution earns a review round even past round 3, but never past round 5 unless the user asks. A resolution made after round 5 ships unreviewed, and the summary says so.
   - **Converged**: the round was dry.
   - **Terminal: minor only** (`minor-only`): the round has at most two new findings and no major blocker; a round whose findings were all declined has zero and ends here too. This applies to any round, round 1 included. Ledger the findings as usual and run no further round. It is a finished review, not a cap.
   - **Terminal: round limit** (`round-limit`): three rounds are complete and the latest has no major blocker. Rounds 4 and 5 exist only to review major-blocker fixes or a design-gap resolution.
   - **Capped**: round 5 finished with a major blocker, so its fix ships unreviewed. Stop and report that fix rather than keep paying: past this point rounds tend to churn fixes into new findings faster than they settle. The user can explicitly ask for more rounds; never extend past round 5 on your own.

   Otherwise run the next round: for example, when the round fixed a major blocker, or raised more than two new findings before round 3.

Expect later rounds to flag the *fixes* from earlier rounds — that is a real and recurring category, not noise, and it is why a round that fixed a major blocker ends the loop only at the round-5 cap or on escalation. Converging locally before pushing is also what makes any finding a hosted reviewer reports afterwards genuinely informative: it is a miss, rather than a finding in fix code nothing had reviewed yet.

Each round invokes the selected reviewers and takes roughly 5–20 minutes, so state the reviewer selection and expected cost before starting a long loop on a large diff. Two or three rounds is the useful range for most changes.
