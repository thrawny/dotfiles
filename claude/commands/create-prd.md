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

2. **Ask clarifying questions** (only if needed):
   - Ask 1-3 essential questions if the request is unclear
   - Focus on problem/goal, basic user flow, and scope boundaries
   - Skip if the feature description is already clear

3. **Generate the PRD**:
   - Create a concise PRD with standard structure:
     - Introduction/Overview (2-3 sentences)
     - Goals (1-2 specific objectives)
     - User Stories (max 2 stories, 1-2 sentences each)
     - Functional Requirements (max 3 numbered items, brief)
     - Non-Goals (2-4 boundaries)
     - Technical Considerations (optional, 2-3 key points)
     - Success Metrics (1-2 measurable outcomes)

4. **Save the PRD**:
   - Create `/docs/features` directory if it doesn't exist
   - Create feature-specific directory: `/docs/features/[feature-name]/`
   - Save as `prd.md` in the feature directory
   - Use kebab-case for the feature name in folder name
   - Ensure the document is well-formatted and readable

5. **Provide completion summary**:
   - Confirm the PRD has been created
   - Mention the file location

Target the PRD for a **junior developer** audience - be clear and specific, but keep text minimal. Focus on essential information only.