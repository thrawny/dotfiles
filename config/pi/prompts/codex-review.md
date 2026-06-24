---
description: Run quiet Codex review, fix P1/P2 issues, and repeat until clean
---

## Argument

`$ARGUMENTS` = max number of review rounds (integer, default `3`). Stop early if a round finds no P1/P2 issues.

## Your task

Run a quiet Codex review to find code issues, fix any major ones (P1/P2), and repeat up to the round limit above.

1. **Determine review mode**:

   - Check current branch: `git rev-parse --abbrev-ref HEAD`
   - If on a branch other than `main`: review with `--base main`
   - If on `main`: review with `--uncommitted`

   Use `codex exec review`, not top-level `codex review`, so the final answer can be written to a file.

2. **Review loop** (repeat up to the round limit from `$ARGUMENTS`):

   - Run the appropriate quiet review command, redirecting progress output away from the agent context:

     ```bash
     review_out="$(mktemp)"
     review_log="$(mktemp)"
     codex exec --ephemeral --color never -o "$review_out" review --base main >"$review_log" 2>&1
     review_status=$?
     cat "$review_out"
     if [ "$review_status" -ne 0 ]; then
       printf '\nCodex review failed with status %s. Log tail:\n' "$review_status"
       tail -80 "$review_log"
     fi
     ```

     On `main`, replace `--base main` with `--uncommitted`.
   - Parse the output for P1 and P2 issues
   - If no P1/P2 issues remain, report success and stop
   - If P1/P2 issues are found:
     - Summarize the issues clearly
     - Fix each P1/P2 issue individually and commit it separately (use `commit` after each fix)
     - If you have not yet reached the round limit, start the next round

3. **After the final round**:

   - If issues remain, summarize what's left unresolved
   - Report how many rounds were completed and what was fixed
