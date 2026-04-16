---
name: git-commit
description: >
  Create focused git commits for the current task. Use when the user asks to
  commit, make a git commit, stage and commit changes, or write a commit
  message. DIRECT trigger: if the user's whole message is just "commit" or just
  "gc", use this skill. Determine the correct files to stage, ask if scope is
  unclear, then stage and commit with a concise imperative message.
---

# Git Commit

1. Run `git status --short` to inspect the worktree.
2. Determine which changes belong in this commit from the current task and recent conversation.
3. If the intended scope is unclear, ask before staging.
4. Stage only the relevant files.
5. Review staged contents with `git diff --cached --stat` and, when needed, `git diff --cached`.
6. Write a concise imperative commit message focused on why.
7. Commit with `git commit -m "..."`.
8. If there is nothing to commit, say so and stop.
