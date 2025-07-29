---
allowed-tools: Bash(git status), Bash(git fetch), Bash(git rebase), Bash(git add), Bash(git commit), Bash(git branch), Bash(git log), Bash(git diff), Bash(git mergetool), Bash(git rebase --continue), Bash(git rebase --abort)
description: Rebase current branch with main and handle any conflicts that arise
---

## Context

!`git status --porcelain`
!`git branch --show-current`
!`git log --oneline -5`

## Your task

Rebase the current branch with the main branch and handle any conflicts that arise. Follow these guidelines:

1. **Check current state**: Verify the working directory is clean and identify the current branch
   - Ensure no uncommitted changes exist
   - Confirm we're not already on main branch
   - Show current branch status

2. **Fetch latest changes**: Update remote references to get the latest main branch
   - Run `git fetch origin` to get latest remote changes
   - Confirm main branch is up to date

3. **Start the rebase**: Begin rebasing current branch onto main
   - Execute `git rebase origin/main`
   - Monitor for any conflicts that arise

4. **Handle conflicts if they occur**:
   - If conflicts are detected, list the conflicted files
   - Provide clear guidance on next steps:
     - Option 1: Auto-resolve simple conflicts where possible
     - Option 2: Open merge tool with `git mergetool`
     - Option 3: Manually resolve conflicts and continue
   - After conflicts are resolved, continue with `git rebase --continue`

5. **Verify successful completion**:
   - Confirm rebase completed successfully
   - Show updated commit history with `git log --oneline -5`
   - Display current branch status

6. **Handle failure scenarios**:
   - If rebase fails and cannot be resolved automatically, offer to abort with `git rebase --abort`
   - Provide clear error messages and suggested manual steps
   - Always leave the repository in a clean state

If the working directory has uncommitted changes, offer to stash them first. If we're already on the main branch, suggest switching to a feature branch first.