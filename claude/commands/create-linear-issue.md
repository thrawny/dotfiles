---
allowed-tools: mcp__linear__list_teams, mcp__linear__get_team, mcp__linear__create_issue, mcp__linear__list_issue_statuses, mcp__linear__list_issue_labels, Bash(git status:*), Bash(git add:*), Bash(git commit:*), Bash(git push:*), Bash(git branch:*), Bash(git checkout:*), Bash(gh pr:*), Read, Grep
argument-hint: issue title and description (e.g., "Fix user authentication bug - Users cannot login with email")
description: Create Linear issue, checkout new branch, commit changes, and create PR
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

! Get recent git changes for context
```bash
git diff HEAD~3..HEAD --name-only
```

! Get recent commit messages for context
```bash
git log --oneline -5
```

! Check for staged/unstaged changes
```bash
git diff --cached --name-only && git diff --name-only
```

! List available Linear teams
```
mcp__linear__list_teams
```

## Your task

Based on the command input and current git context, create a complete Linear issue workflow. Follow these guidelines:

1. **Parse the issue input and gather context**:

   - Extract title from the first part before " - " or use entire input as title
   - Use everything after " - " as initial description content
   - If no argument provided, ask user for issue title
   - Analyze current git status, recent commits, and changed files to understand context
   - Use file contents and code changes to intelligently infer technical implementation needs

2. **Get Linear workspace context**:

   - List available teams and select the most appropriate one
   - Get available issue statuses and labels for the team
   - Default to "Todo" or "Backlog" status if available

3. **Create the Linear issue with intelligent content**:

   - Create issue with parsed title and structured description format:
     ```
     ## Description
     {use user input, or infer from changed files and context}
     
     ## Technical Implementation
     {analyze current changes, file types, and codebase to suggest implementation approach}
     
     ## Definition of Done
     {generate reasonable completion criteria based on the issue type and context}
     ```
   - **Smart content generation**:
     - **Description**: Use user input first, or analyze git diff/status to understand what's being worked on
     - **Technical Implementation**: Examine changed files, imports, function signatures to infer technical approach
     - **Definition of Done**: Generate standard criteria (tests pass, code review, deployment) plus context-specific items
   - Only prompt user for missing information that cannot be reasonably inferred
   - Set appropriate team, status, and labels
   - Capture the issue ID and URL for later use

4. **Generate branch name**:

   - Use Linear issue key (e.g., "DEV-123") as branch prefix
   - Convert title to kebab-case for branch suffix
   - Format: `{issue-key}-{kebab-case-title}` (e.g., "DEV-123-fix-user-authentication")
   - Truncate if branch name would be too long (max 50 chars)

5. **Git workflow**:

   - Check if there are unstaged changes and stage them with `git add -A`
   - Create and checkout new branch with generated name
   - If there are staged changes, commit them with message: "Initial work on {issue-title}\n\nLinear issue: {issue-url}\n\n🤖 Generated with [Claude Code](https://claude.ai/code)\n\nCo-Authored-By: Claude <noreply@anthropic.com>"
   - Push branch to origin with upstream tracking

6. **Create Pull Request**:

   - Create PR with title matching the Linear issue title
   - Include PR body with:
     - Brief summary of changes
     - Link to Linear issue
     - Test plan section
     - Claude signature
   - Use format: "## Summary\n\n{brief-summary}\n\n## Linear Issue\n\n{issue-url}\n\n## Test Plan\n\n- [ ] Test the changes\n- [ ] Verify functionality\n\n🤖 Generated with [Claude Code](https://claude.ai/code)"

7. **Provide completion summary**:
   - Display Linear issue URL and key
   - Display new branch name
   - Display PR URL
   - Provide next steps guidance

**Error handling**:

- If Linear team selection fails, list available teams and ask user to specify
- If branch creation fails (name conflict), append timestamp or increment number
- If no changes to commit, create empty commit with issue reference
- If PR creation fails, provide manual instructions

**Branch naming examples**:

- Input: "Fix login bug - Users can't authenticate with email" → Branch: "t-123-fix-login-bug"
- Input: "Add user dashboard" → Branch: "t-124-add-user-dashboard"
- Input: "Update API documentation for v2 endpoints" → Branch: "t-125-update-api-documentation"
