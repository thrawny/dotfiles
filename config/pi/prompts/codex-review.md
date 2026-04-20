---
description: Run codex review, fix P1/P2 issues, and repeat until clean
---

## Argument

`$ARGUMENTS` = max number of review rounds (integer, default `3`). Stop early if a round finds no P1/P2 issues.

## Your task

Run `codex review` to find code issues, fix any major ones (P1/P2), and repeat up to the round limit above.

1. **Determine review mode**:

   - Check current branch: `git rev-parse --abbrev-ref HEAD`
   - If on a branch other than `main`: use `codex review --base main`
   - If on `main`: use `codex review --uncommitted`

2. **Review loop** (repeat up to the round limit from `$ARGUMENTS`):

   - Run the appropriate `codex review` command
   - Parse the output for P1 and P2 issues
   - If no P1/P2 issues remain, report success and stop
   - If P1/P2 issues are found:
     - Summarize the issues clearly
     - Fix each P1/P2 issue individually and commit it separately (use `commit` after each fix)
     - If you have not yet reached the round limit, start the next round

3. **After the final round**:

   - If issues remain, summarize what's left unresolved
   - Report how many rounds were completed and what was fixed
