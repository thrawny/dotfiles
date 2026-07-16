---
name: gauntlet
description: Run Claude and Codex code reviews in parallel over the current changes, dedupe the findings, then fix the major ones (verifying each first) and summarize. Use when the user wants a thorough, cross-checked review-and-fix from both engines rather than just one.
---

# Gauntlet

Run the current diff through a gauntlet of two independent reviewers — Claude's `/code-review` and Codex's `review` — at the same time, merge their findings, **fix the major issues by default**, and summarize. Issues that **both** engines flag are the highest-confidence ones.

The parallel launch is handled by the bundled `scripts/gauntlet-review` launcher; this skill owns the judgment around it.

Default behavior: fix major findings (high severity / Codex P1–P2). Minor and declined findings are reported, not fixed. If the user asks for report-only, do steps 1–3 and skip the fixing.

## 1. Build a context brief (this is what cuts false positives)

Reviewers given only a raw diff flag intentional choices as bugs. Write a short brief covering:

- **Intent** — what this change does and why.
- **Original task / goal** it serves.
- **Deliberate choices** reviewers should NOT flag (intentional tradeoffs, accepted limitations).
- **Out of scope** — areas not to comment on (pre-existing code, unrelated files).

Derive it from the conversation, the task, commit messages, or the PR description. If the intent is genuinely unclear, ask the user one question rather than guessing — a wrong brief produces wrong findings. The script passes this brief verbatim to both engines and adds a standard precision-over-recall instruction itself.

## 2. Run both reviewers

The launcher is bundled at `scripts/gauntlet-review` in this skill's directory. Invoke it by its full path (substitute this skill's directory for `<skill-dir>`):

```bash
bash <skill-dir>/scripts/gauntlet-review "<your context brief>"
```

- Scope is auto-detected: the current branch's diff against origin's remote-tracking default branch (for example, `origin/main`), or uncommitted changes when already on the corresponding local branch. Override with `--base <branch>`, `--uncommitted`, or `--commit <sha>` (before the brief). For a long brief, pipe it on stdin with a trailing `-`.
- It runs both engines in parallel and prints two delimited blocks labeled with each engine's state — `===== CLAUDE REVIEW [ok] =====` and `===== CODEX REVIEW [ok] =====`. **Reviews can take a while; allow a 20 minute timeout when running the command directly. If the agent environment has short command timeouts, unreliable disconnects, or the user wants the review to continue in the background, run it in a persistent `zmx` session instead and check the session logs for completion.**
- **Graceful degradation:** if an engine is unauthenticated or out of usage/quota, its block is labeled `[unavailable: …]` and the script prints a `NOTE: degraded to a single reviewer …` line, succeeding on the engine that worked. Proceed with the available findings and tell the user which engine was skipped and why. With only one reviewer there's no cross-engine agreement signal, so lean harder on per-finding verification (step 4.1). If both are unavailable the script prints `ERROR:` and exits non-zero — report that and stop.

## 3. Dedupe

Merge the two blocks into one set of unique issues:

- Two findings are the **same issue** when they point at the same file and overlapping location *and* describe the same root cause — even if worded or scored differently. Merge them.
- For each unique issue, record who raised it: `claude`, `codex`, or **both**.
- **Agreement is a confidence signal** — issues both engines flag are most likely real; surface them first.
- Codex scores P1/P2/P3, Claude scores high/medium/low — normalize to one scale (high/medium/low); on conflict take the higher.

## 4. Fix the major issues

For each finding that is **major** (high severity / Codex P1–P2):

1. **Verify it against the real code first** — open the file and adjacent code and confirm the bug is real, in scope, and not already handled. This verification is the main false-positive guard; the context brief is the other.
2. If it holds up, fix it. If it's a false positive, intentional per the brief, or out of scope, **decline it** and record why — do not blindly apply findings.
3. Keep fixes surgical: address the finding, don't expand scope or refactor unrelated code.

**Stop and ask the user instead of fixing** when a fix would change the change's intended contract, balloon the diff well past its original scope, or when two findings prescribe conflicting fixes. Autofix is for clear, contained corrections — not redesigns.

Commit the fixes. Leave **minor** findings (medium/low, Codex P3) as a reported list — don't fix them unless the user asks.

## 5. Summarize

Present one unified report, highest severity first:

| Severity | Location | Issue | Flagged by | Status |
|----------|----------|-------|------------|--------|
| high | `path:line` | one-line description | both | fixed |
| high | `path:line` | … | codex | declined (false positive: …) |
| medium | `path:line` | … | claude | reported |

Close with a one-line tally: total unique findings, how many both engines agreed on, how many were fixed vs declined vs left as minor, and whether either engine failed to run.
