---
allowed-tools: Read, Write, Glob, Grep, TodoWrite
argument-hint: brief feature description
description: Generate a detailed Product Requirements Document (PRD) from a feature description
---

## Context

Use Glob to check for existing feature directories and PRD files.

## Your task

Based on the provided feature description, create a detailed Product Requirements Document (PRD) in Markdown format. The PRD should be clear, actionable, and suitable for a junior developer to understand and implement.

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

3. **Generate the PRD**:
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

4. **Save the PRD**:
   - Create `/docs/features` directory if it doesn't exist
   - Create feature-specific directory: `/docs/features/[feature-name]/`
   - Save as `prd.md` in the feature directory
   - Use kebab-case for the feature name in folder name
   - Ensure the document is well-formatted and readable

5. **Provide completion summary**:
   - Confirm the PRD has been created
   - Mention the file location (e.g., `/docs/features/user-profile/prd.md`)
   - Suggest next steps (e.g., using `/generate-tasks user-profile` command)

Target the PRD for a **junior developer** audience - be explicit, unambiguous, and avoid unnecessary jargon. Provide enough detail for clear understanding of the feature's purpose and core logic.