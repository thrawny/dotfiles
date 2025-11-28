---
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*), Bash(git diff:*), Bash(git log:*), Bash(git branch:*), Bash(git push:*)
description: Create a smart git commit and push to remote
model: claude-haiku-4-5-20251001
---

## Context

- Current git status: !`git status`
- Current git diff (staged and unstaged changes): !`git diff HEAD`
- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -10`

## Your task

Based on the above git context, create a single well-crafted git commit and push it to the remote repository. Follow these guidelines:

1. **Analyze the changes**: Look at both staged and unstaged changes to understand what modifications have been made
2. **Stage relevant files**: Add any untracked or modified files that should be part of this commit
   - Check for and stage new/untracked files using `git add` for files that should be included
   - Don't commit .envrc files - these are local environment configurations that should not be shared
3. **Write a meaningful commit message** that:
   - Uses imperative mood (e.g., "Add feature" not "Added feature")
   - Is concise but descriptive (max 4 lines of text)
   - Follows the existing commit message style shown in recent commits
   - Explains the "why" rather than just the "what"
4. **Include the Claude signature**: End the commit with the standard Claude Code signature
5. **Push to remote**: After committing, push the changes to the remote repository
   - Use `git push` for established branches
   - Use `git push -u origin <branch>` for new branches that need upstream tracking

If there are no changes to commit, let me know. If the changes seem incomplete or you need clarification about what should be included, ask before proceeding.