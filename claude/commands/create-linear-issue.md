---
allowed-tools: mcp__linear__list_teams, mcp__linear__get_team, mcp__linear__create_issue, mcp__linear__list_issue_statuses, mcp__linear__list_issue_labels
argument-hint: issue title and description (e.g., "Fix user authentication bug - Users cannot login with email")
description: Create Linear issue with user confirmation - for capturing issues when you discover something interesting
---

## Context

! List available Linear teams
```
mcp__linear__list_teams
```

## Your task

**Create Linear Issue** - Create a Linear issue with user confirmation before creation.

This command is for capturing issues when you discover something interesting but aren't ready to start work immediately. Follow these guidelines:

1. **Parse the issue input**:

   - Extract title from the first part before " - " or use entire input as title
   - Use everything after " - " as initial description content
   - If no argument provided, ask user for issue title

2. **Get Linear workspace context**:

   - List available teams and select the most appropriate one
   - Get available issue statuses and labels for the team
   - Default to "Todo" or "Backlog" status for new issues

3. **Create the Linear issue**:

   - **First, generate and display the issue content for review**:
     - Show the proposed title
     - Display the full description that will be created with structured format:
       ```
       ## Description
       {use user input for the problem/feature description}
       
       ## Technical Implementation
       {suggest implementation approach based on title and description}
       
       ## Definition of Done
       {generate reasonable completion criteria based on the issue type}
       ```
     - **Ask for user confirmation** before creating the issue
   - **Smart content generation for new issues**:
     - **Description**: Use user input to describe the problem or feature
     - **Technical Implementation**: Suggest approach based on issue type and existing codebase patterns
     - **Definition of Done**: Generate standard completion criteria (tests pass, code review, deployment)
   - After user approval, create the issue with appropriate team, status ("Todo" or "Backlog"), and labels
   - Capture the issue ID and URL for later use

4. **Provide completion summary**:
   - Display the created Linear issue URL and key
   - Show suggested branch name format: `{issue-key}-{kebab-case-title}` for when ready to start work
   - Provide brief next steps guidance

**Error handling**:

- If Linear team selection fails, list available teams and ask user to specify

**Branch naming examples**:

- Input: "Fix login bug - Users can't authenticate with email" → Branch: "t-123-fix-login-bug"
- Input: "Add user dashboard" → Branch: "t-124-add-user-dashboard"
- Input: "Update API documentation for v2 endpoints" → Branch: "t-125-update-api-documentation"