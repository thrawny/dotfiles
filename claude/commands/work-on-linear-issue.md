---
allowed-tools: mcp__linear__list_teams, mcp__linear__get_team, mcp__linear__list_issues, mcp__linear__get_issue, mcp__linear__update_issue, mcp__linear__list_issue_statuses, Bash(git status:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(git branch:*), Bash(git checkout:*)
argument-hint: issue ID or search term (e.g., "T-123" or "authentication bug")
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

! List available Linear teams

```
mcp__linear__list_teams
```

## Your task

**Work on Linear Issue** - Find an existing Linear issue and start working on it with proper branch setup.

This command helps you transition from issue planning to active development. Follow these guidelines:

1. **Find the Linear issue**:

   - If argument is an issue ID (e.g., "T-123", "DEV-456"), get that specific issue
   - If argument is a search term, search for issues matching the term
   - If no argument provided, list recent issues from your teams and let user select
   - Display the issue details (title, description, current status) for confirmation

2. **Get Linear workspace context**:

   - Get the issue's team information
   - List available issue statuses for status updates
   - Identify appropriate "In Progress" or "Started" status

3. **Generate branch name**:

   - Use Linear issue key (e.g., "DEV-123") as branch prefix
   - Convert issue title to kebab-case for branch suffix
   - Format: `{issue-key}-{kebab-case-title}` (e.g., "DEV-123-fix-user-authentication")
   - Truncate if branch name would be too long (max 50 chars)

4. **Git workflow**:

   - Check if there are uncommitted changes and handle appropriately:
     - If on main/master branch with uncommitted changes, stash them with message referencing the issue
     - If on feature branch with uncommitted changes, ask user what to do (commit, stash, or abort)
   - Create and checkout new branch with generated name

5. **Update Linear issue status**:

   - Update issue status to "In Progress"

6. **Provide work summary**:
   - Display Linear issue URL and key
   - Show current branch name
   - Display issue title and key details
   - Provide next steps guidance for development

**Error handling**:

- If issue ID not found, search for similar titles and suggest alternatives
- If multiple issues match search term, show list for user selection
- If branch creation fails (name conflict), append timestamp or increment number
- If issue status cannot be updated, continue with branch creation and warn user

**Branch naming examples**:

- Issue "T-123: Fix login bug" → Branch: "t-123-fix-login-bug"
- Issue "DEV-456: Add user dashboard" → Branch: "dev-456-add-user-dashboard"
- Issue "FEAT-789: Update API documentation" → Branch: "feat-789-update-api-documentation"

**Issue search examples**:

- Input: "T-123" → Gets specific issue T-123
- Input: "login bug" → Searches for issues containing "login" and "bug"
- Input: "" → Shows recent issues from your teams for selection
