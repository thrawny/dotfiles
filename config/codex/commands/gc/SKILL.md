---
name: gc
description: Commit the current task's changes cleanly. Use when the user asks to commit work on the current branch, says `/gc`, or wants a focused git commit that stages only task-related files with a concise why-oriented message.
---

# gc

Create a focused commit for the current task.

## Workflow

1. Run `git status` to inspect the worktree.
2. Determine which files belong to the task at hand.
3. If the intended commit scope is unclear, ask before staging.
4. Stage only the relevant files. Leave unrelated changes untouched.
5. Prefer one non-interactive command that stages and commits, such as `git add <files> && git commit -m "..."`.
6. Write a concise imperative commit message that explains the why, not just the surface change.
7. If there is nothing to commit, say so and stop.

## Guardrails

- Never stage unrelated dirty files for convenience.
- Avoid vague messages like `fix stuff` or `updates`.
- Keep the result terse; do not add unnecessary narration around the commit.
