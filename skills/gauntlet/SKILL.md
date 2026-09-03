---
name: gauntlet
description: Run Claude and Codex code reviews in parallel over the current changes, dedupe the findings, then fix the major ones (verifying each first) and summarize. Use when the user wants a thorough, cross-checked review-and-fix from both engines rather than just one.
---

# Gauntlet

Run the current diff through two independent reviewers at once — one Claude `/code-review` and one Codex `review` — merge their findings, **fix the major issues by default**, and summarize. The engines mostly surface *different* findings — that disjoint union is the value of running two, and confidence comes from per-finding verification (§4), not from agreement.

The parallel launch is handled by the bundled `scripts/gauntlet-review` launcher; this skill owns the judgment around it.

This skill is tuned for **recall at generation time and precision at judgment time**. The reviewers are deliberately asked to be exhaustive, so expect more raw findings than pass the bar — including some false positives. That is the intended shape: a finding you never generate cannot be caught in step 4, but a bad one can. Do not try to restore precision by softening the launcher's prompts; restore it by verifying and declining in step 4.

Default behavior: fix major findings (high severity / Codex P1–P2) that triage as implementation bugs; design gaps and scope increases are escalated or deferred, not autofixed (§4). Minor and declined findings are reported, not fixed. If the user asks for report-only, do steps 1–3 and skip the fixing.

One run is one sample. When the user wants the change actually driven to convergence — before pushing, before a PR, or when they ask to "loop" or "keep going until it's clean" — follow the loop protocol in §6 rather than calling a single quiet round done.

## 1. Build a context brief (this is what scopes the review)

The brief is the local stand-in for a PR description — without it, reviewers flag intentional choices as bugs. Write a short brief covering:

- **Intent** — what this change does and why.
- **Original task / goal** it serves.
- **Deliberate choices** reviewers should NOT flag (intentional tradeoffs, accepted limitations).
- **Out of scope** — areas not to comment on (pre-existing code, unrelated files).

Derive it from the conversation, the task, commit messages, or the PR description. If the intent is genuinely unclear, ask the user one question rather than guessing — a wrong brief produces wrong findings. The script passes this brief verbatim to both reviewers, and adds the scope and self-verification instructions itself.

## 2. Run the reviewers

The launcher is bundled at `scripts/gauntlet-review` in this skill's directory. Invoke it by its full path (substitute this skill's directory for `<skill-dir>`):

```bash
bash <skill-dir>/scripts/gauntlet-review "<your context brief>"
```

- Scope is auto-detected: the current branch's diff against origin's remote-tracking default branch (for example, `origin/main`), or uncommitted changes when already on the corresponding local branch. Override with `--base <branch>`, `--uncommitted`, or `--commit <sha>` (before the brief). For a long brief, pipe it on stdin with a trailing `-`.
- Both engines run by default. Restrict with `--reviewers claude` or `--reviewers codex` (comma list; `GAUNTLET_REVIEWERS` sets the default) — for a single-engine loop the user asked for, or to stop spending one engine's quota. Unlike quota degradation this is deterministic: a deselected engine never runs, even if its quota comes back mid-loop. A single-reviewer run generates a smaller union of findings — expect lower recall, not lower precision; verification (step 4.1) is unchanged.
- It runs both reviewers in parallel and prints two delimited blocks labeled with each reviewer's state — `===== CLAUDE REVIEW [ok] =====` and `===== CODEX REVIEW [ok] =====`. **Reviews take 5–20 minutes. If the harness offers managed background execution that notifies on completion, launch the command that way and continue other work until the notification arrives. Only without such a mechanism, run it in the foreground with the longest timeout available.**
- Codex reasoning effort defaults to `high`; raise it for a single run with `GAUNTLET_CODEX_EFFORT` (for example `xhigh`) or change the model with `GAUNTLET_CODEX_MODEL`.
- Every run saves each reviewer's raw output, the reviewed SHA, and the brief under a per-repo/per-branch state dir, and prints a `===== GAUNTLET STATE =====` footer with the round number, the output path, and the ledger path. **Note those paths** — the raw output is how you re-check a dedupe decision without paying for another 5–20 minute round.
- If this branch already has a `ledger.md` (see §6), the launcher picks it up automatically and tells the reviewers not to repeat findings already adjudicated there. A `NOTE:` line always says which ledger was used. Suppress it with `--no-prior`, or point elsewhere with `--prior <file>`.
- **Graceful degradation:** a reviewer that is unauthenticated or out of usage/quota gets an `[unavailable: …]` block, and the script prints a `NOTE:` line saying what dropped, succeeding on the reviewer that ran. Proceed with the available findings and tell the user what was skipped and why. With only one reviewer the union of findings is smaller — a recall loss verification can't recover, so note it in the summary. If neither ran the script prints `ERROR:` and exits non-zero — report that and stop.

## 3. Dedupe

Merge the blocks into one set of unique issues:

- Two findings are the **same issue** when they point at the same file and overlapping location *and* describe the same root cause — even if worded or scored differently. Merge them.
- For each unique issue, record who raised it: `claude`, `codex`, or **both**. This is telemetry, not confidence — every major finding gets the same verification in step 4.1 regardless of source. Two independent engines mostly find *different* things; a single-source finding is the normal case, not a mark against it, and agreement changes nothing about how a finding is handled.
- Codex scores P1/P2/P3, Claude scores high/medium/low — normalize to one scale (high/medium/low); on conflict take the higher.

## 4. Triage, then fix

For each finding that is **major** (high severity / Codex P1–P2):

1. **Verify it against the real code first** — open the file and adjacent code and confirm the bug is real, in scope, and not already handled. Reading is usually enough; the gates were green before this run, so re-running them settles nothing. Probe directly only when the finding hinges on a case no test covers. This verification is the *primary* false-positive guard — the reviewers are asked to be exhaustive precisely because this step exists, so it is not optional and a healthy run declines a real share of findings. A false positive, a choice the brief marks intentional, or an out-of-scope finding is **declined** with the reason recorded — do not blindly apply findings.
2. **Classify the fix, not the finding.** A verified-real finding is not automatically autofixable — what matters is what its fix would do. The change's **boundary** is the blueprint when one exists (its filetree is the set of touchable files; Decisions and Will-not-touch are the recorded calls); otherwise it is the footprint and evident intent of the diff under review.
   - **Implementation bug** — the fix corrects code against something that already exists (a recorded decision, an existing invariant, the change's own intent) and stays inside the boundary. Fix it. Blueprint silence on the detail is fine — the interior of the boundary is implementor discretion.
   - **Design gap** — the fix would contradict a recorded decision, touch files outside the boundary, or create something new that outlives this diff: a new interface, public API shape, config surface, dependency direction, or invariant. Do **not** fix it, however small the diff looks — a small fix that makes an unowned decision is scope damage, not progress. Ledger it and escalate (below).
   - **Scope increase** — real, but serves work the user never asked for. Ledger as deferred, report as follow-up work, don't fix.
3. Fix implementation bugs surgically: address the finding, don't expand scope or refactor unrelated code.

**Escalation:** finish the round — verify, classify, and fix the remaining implementation bugs — then stop the loop and put the design gaps to the user as a batch, each stated as the decision it requires, with your recommendation. Never start another round with design gaps unresolved: their resolution changes the code the next round would review. When a blueprint exists, record the resolution in it first, then implement. Conflicting findings (two fixes that can't both be applied) escalate the same way.

Commit the fixes, then record every finding in the ledger (§6) with its verdict — fixed with the commit SHA, declined with the reason, design gap with the decision it requires, or deferred as scope. Leave **minor** findings (medium/low, Codex P3) as a reported list — don't fix them unless the user asks, but still ledger them, or the next round re-raises them.

Committing is not just hygiene when looping. On a branch the scope is `git diff <base>...HEAD`, which is **committed work only**: uncommitted fixes are invisible to the next round, so it re-finds everything you just fixed and the loop cannot converge. The inverse holds on the default branch, where the scope is `--uncommitted` — committing there empties the scope and the next round reports a false dry round. So: **commit between rounds on a branch, never on the default branch.**

## 5. Summarize

Present one unified report, highest severity first:

| Severity | Location | Issue | Flagged by | Status |
|----------|----------|-------|------------|--------|
| high | `path:line` | one-line description | both | fixed |
| high | `path:line` | … | codex | declined (false positive: …) |
| high | `path:line` | … | both | design gap (escalated: needs decision on …) |
| medium | `path:line` | … | codex | deferred (scope: …) |
| medium | `path:line` | … | claude | reported |

Close with a one-line tally: total unique findings, how many both reviewers agreed on, how many were fixed vs declined vs escalated as design gaps vs deferred vs left as minor, and whether either reviewer failed to run.

## 6. The ledger, and looping to convergence

One gauntlet is one sample, and one sample does not exhaust a diff. Measured against the hosted Codex PR reviewer on real PRs: it re-reads the **full** diff every round rather than just the new commits, and roughly two-thirds of what its later rounds found sat in code an earlier round had already read and passed over. Extra rounds pay not because the reviewer gets smarter but because a diff is not exhausted in one pass.

That only works with a memory. Without one, round 2 spends both reviews re-deriving round 1's findings and you dedupe the duplicates away — you paid for the round and got the remainder. The ledger is what turns the next round outward onto new ground, and it is the same mechanism the hosted reviewer uses.

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
4. The loop has three terminal states, and the final summary must name which one happened — a loop that exits on budget looks identical to one that exits on convergence unless the report says so:
   - **Converged** — one dry round.
   - **Escalated** — design gaps are batched and waiting on the user (§4). Not a failure; the loop resumes after they're resolved.
   - **Capped** — round 4 finished without converging. Stop and report rather than keep paying: past this point rounds tend to churn fixes into new findings faster than they settle. The user can explicitly ask for more rounds; never extend past the cap on your own.

Expect later rounds to flag the *fixes* from earlier rounds — that is a real and recurring category, not noise, and it is the reason to keep looping rather than stopping at the first quiet round. Converging locally before pushing is also what makes any finding a hosted reviewer reports afterwards genuinely informative: it is a miss, rather than a finding in fix code nothing had reviewed yet.

Each round costs one Claude and one Codex review at 5–20 minutes, so say so before starting a long loop on a large diff. Two or three rounds is the useful range for most changes.
