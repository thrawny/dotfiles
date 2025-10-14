## Context

- `git status`
- `git diff HEAD`
- `git branch --show-current`
- `git log --oneline -10`

## Task

Create one clean commit from the current workspace.

1. Review both staged and unstaged changes so you fully understand what will ship.
2. Confirm which files belong in the commit.
3. Before any `git add`, `git commit`, or other write action, Codex **must** request elevated permission; skipping the approval step triggers index-lock failures and the command will not succeed.
4. After approval, stage the required files—never include `.envrc`.
5. Craft a concise, imperative commit message that follows the existing style and explains the reasoning, not just the edits.

If there is nothing to commit, report that outcome. If the change set feels unclear or incomplete, pause and ask for direction instead of guessing.
