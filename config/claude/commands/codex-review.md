---
allowed-tools: Bash(codex review:*), Bash(git branch:*), Bash(git rev-parse:*), Bash(git diff:*), Skill(gc)
argument-hint: max rounds (default 3)
description: Run quiet Codex review, fix P1/P2 issues, and repeat until clean
---

## Your task

Run a quiet Codex review to find code issues, fix any major ones (P1/P2), and repeat until all major issues are resolved or the max number of rounds is reached.

1. **Determine review mode**:

   - Check if on a branch other than `main`: `git rev-parse --abbrev-ref HEAD`
   - If on a branch: review with `--base main`
   - If on `main`: review with `--uncommitted`

   Use `codex exec review`, not top-level `codex review`, so the final answer can be written to a file.

2. **Set max rounds**:

   - Use the argument if provided (e.g., `/codex-review 5`), otherwise default to 3

3. **Review loop** (up to max rounds):

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
     - Fix each P1/P2 issue individually and commit it separately (use `/gc` after each fix)
     - Move to the next round

4. **After all rounds**:

   - If issues remain after the final round, summarize what's left unresolved
   - Report how many rounds were completed and what was fixed
