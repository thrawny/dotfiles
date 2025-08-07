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

2. **Ask clarifying questions**:
   - **MUST** ask clarifying questions before writing the PRD
   - Focus on understanding the "what" and "why", not the "how"
   - Provide options in letter/number lists for easy user responses
   - Cover key areas:
     - Problem/Goal: What problem does this solve?
     - Target User: Who will use this feature?
     - Core Functionality: Key actions users should perform
     - User Stories: Specific use cases and benefits
     - Acceptance Criteria: Success criteria for implementation
     - Scope/Boundaries: What should NOT be included
     - Data Requirements: What data is needed?
     - Design/UI: Any visual or UX requirements
     - Edge Cases: Potential error conditions or unusual scenarios

3. **Generate the PRD and create Linear issue**:
   - Use the user's answers to create a comprehensive PRD
   - Follow the standard PRD structure:
     - Introduction/Overview
     - Goals (specific, measurable objectives)
     - User Stories (detailed narratives)
     - Functional Requirements (numbered, specific)
     - Non-Goals (explicit scope boundaries)
     - Design Considerations (optional)
     - Technical Considerations (optional)
     - Success Metrics
     - Open Questions

4. **Create the Linear issue**:
   - List available teams and select the most appropriate one
   - Get available issue statuses and labels for the team
   - Create issue with the PRD content as description
   - Default to "Todo" status and assign to user
   - Generate appropriate title from the feature description

5. **Provide completion summary**:
   - Display the created Linear issue URL and key
   - Show suggested folder name format: `{issue-id}-{descriptive-name}`
   - Suggest next steps (e.g., using `/generate-tasks` command)

Target the PRD for a **junior developer** audience - be explicit, unambiguous, and avoid unnecessary jargon. Provide enough detail for clear understanding of the feature's purpose and core logic.