---
allowed-tools: Bash(linear issues:*), Bash(linear start:*), Bash(git status:*), Bash(git checkout:*), Bash(git branch:*), Bash(git stash:*)
argument-hint: issue ID or description (e.g., "T-123" or "the battery glitch issue")
description: Start working on an existing Linear issue - creates branch and updates issue status
---

## Context

! Get current git status

```bash
git status
```

! Get current branch name

```bash
git branch --show-current
```

! List available issues

```bash
linear issues
```

## Your task

**Work on Linear Issue** - Find and start working on a Linear issue with proper branch setup.

1. **Find the issue**:

   - If argument looks like an issue ID (e.g., "T-123"), use it directly
   - Otherwise, match the argument description against the `linear issues` output above
   - If multiple issues could match, ask the user to clarify
   - If no match found, tell the user

2. **Start the issue** using the `linear` CLI:

   ```bash
   linear start <issue-id>
   ```

   This will:
   - Assign the issue to you
   - Set status to "In Progress"
   - Output the branch name

3. **Git workflow**:

   - Check if there are uncommitted changes:
     - If on main/master with uncommitted changes, stash them
     - If on feature branch with uncommitted changes, ask user what to do
   - Create and checkout new branch using the branch name from `linear start` output

4. **Provide work summary**:
   - Show the branch name you created
   - Display issue title
