---
allowed-tools: Bash(codex review:*), Bash(git branch:*), Bash(git rev-parse:*), Bash(git diff:*), Skill(gc)
argument-hint: max rounds (default 3)
description: Run codex review, fix P1/P2 issues, and repeat until clean
---

## Your task

Run `codex review` to find code issues, fix any major ones (P1/P2), and repeat until all major issues are resolved or the max number of rounds is reached.

1. **Determine review mode**:

   - Check if on a branch other than `main`: `git rev-parse --abbrev-ref HEAD`
   - If on a branch: use `codex review --base main`
   - If on `main`: use `codex review --uncommitted`

2. **Set max rounds**:

   - Use the argument if provided (e.g., `/codex-review 5`), otherwise default to 3

3. **Review loop** (up to max rounds):

   - Run the appropriate `codex review` command
   - Parse the output for P1 and P2 issues
   - If no P1/P2 issues remain, report success and stop
   - If P1/P2 issues are found:
     - Summarize the issues clearly
     - Fix each P1/P2 issue in the code
     - Commit the fixes (use `/gc`) so the next review round sees them
     - Move to the next round

4. **After all rounds**:

   - If issues remain after the final round, summarize what's left unresolved
   - Report how many rounds were completed and what was fixed
