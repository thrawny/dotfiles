## Context

- Current git status: `git status`
- Current git diff (staged and unstaged changes): `git diff HEAD`
- Current branch: `git branch --show-current`
- Recent commits: `git log --oneline -10`

## Your task

Based on the above git context, create a single well-crafted git commit. Follow these guidelines:

1. Analyze the changes: Look at both staged and unstaged changes to understand what modifications have been made.
2. Stage relevant files: Add any untracked or modified files that should be part of this commit.
   - ALWAYS check for and stage new/untracked files using `git add` for files that should be included.
   - NEVER commit `.envrc` files.
3. Write a meaningful commit message that:
   - Uses imperative mood (e.g., "Add feature" not "Added feature").
   - Is concise but descriptive (max ~4 lines of text).
   - Follows the existing commit message style shown in recent commits.
   - Explains the "why" rather than just the "what".

If there are no changes to commit, say so. If the changes seem incomplete or you need clarification about what should be included, ask before proceeding.

