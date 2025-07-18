---
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git branch:*), Bash(git push:*), Bash(gh pr:*)
description: Create a pull request with context analysis
---

## Context

- Current git status: !`git status`
- Current git diff (staged and unstaged changes): !`git diff HEAD`
- Current branch: !`git branch --show-current`
- Recent commits on current branch: !`git log --oneline -10`
- Branch comparison with main: !`git diff main...HEAD --stat`

## Your task

Based on the above git context, create a pull request or push the current branch if a pull request exists already. Follow these guidelines:

1. **Analyze the changes**: Look at all commits and changes that will be included in the PR
2. **Ensure branch is pushed**: Check if the current branch is pushed to remote and push if needed
3. **Create meaningful PR title and description** that:
   - Uses imperative mood (e.g., "Add feature" not "Added feature")
   - Is concise but descriptive
   - Follows existing PR conventions
   - Explains the "why" and impact, not just the "what"
4. **Include test plan**: Add a brief test plan or checklist for reviewers
5. **Include the Claude signature**: End the PR description with the standard Claude Code signature

If there are no changes to create a PR for, or if the current branch is the main branch, let me know. If you need clarification about what should be included, ask before proceeding.
