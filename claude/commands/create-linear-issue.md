---
allowed-tools: Read, Glob, Grep, TodoWrite, mcp__linear__list_teams, mcp__linear__get_team, mcp__linear__create_issue, mcp__linear__list_issue_statuses, mcp__linear__list_issue_labels
argument-hint: brief feature description
description: Generate a detailed Product Requirements Document (PRD) and create Linear issue from a feature description
---

## Context

! List available Linear teams
```
mcp__linear__list_teams
```

## Your task

Based on the provided feature description, create a detailed Product Requirements Document (PRD) and create a Linear issue. The PRD should be clear, actionable, and suitable for a junior developer to understand and implement.

1. **Receive and analyze the feature description**:
   - Parse the initial prompt for the feature request
   - Identify the core functionality being requested
   - Note any explicit requirements or constraints mentioned

2. **Ask clarifying questions** (only if needed):
   - Ask 1-3 essential questions if the request is unclear
   - Focus on problem/goal, basic user flow, and scope boundaries
   - Skip if the feature description is already clear

3. **Generate the PRD and create Linear issue**:
   - Create a concise PRD with standard structure:
     - Introduction/Overview (2-3 sentences)
     - Goals (1-2 specific objectives)
     - User Stories (max 2 stories, 1-2 sentences each)
     - Functional Requirements (max 3 numbered items, brief)
     - Non-Goals (2-4 boundaries)
     - Technical Considerations (optional, 2-3 key points)
     - Success Metrics (1-2 measurable outcomes)

4. **Create the Linear issue**:
   - List available teams and select the most appropriate one
   - Get available issue statuses and labels for the team
   - Create issue with the PRD content as description
   - Default to "Todo" status and assign to user
   - Generate appropriate title from the feature description

5. **Provide completion summary**:
   - Display the created Linear issue URL and key

Target the PRD for a **junior developer** audience - be clear and specific, but keep text minimal. Focus on essential information only.