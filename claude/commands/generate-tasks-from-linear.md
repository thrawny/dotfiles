---
allowed-tools: Read, Write, Glob, Grep, TodoWrite, mcp__linear__get_issue
argument-hint: Linear issue ID (e.g., T-962)
description: Generate a detailed task list from a Linear issue for implementation
---

## Context

<!-- Check current directory and available feature directories -->

## Your task

Based on an existing Linear issue, create a detailed, step-by-step task list to guide a developer through implementation.

1. **Locate and analyze the Linear issue**:

   - Fetch the specified Linear issue (provided as argument)
   - If no argument provided, ask user for Linear issue ID
   - Analyze the issue description, requirements, and technical considerations
   - Extract key implementation needs from the issue

2. **Assess current codebase state**:

   - Review existing infrastructure and architectural patterns
   - Identify existing components, utilities, or features that could be leveraged
   - Note relevant files, components, and patterns that need modification
   - Understand project conventions and structure

3. **Phase 1 - Generate parent tasks**:

   - Create 4-6 high-level tasks based on issue analysis
   - Focus on main implementation phases (e.g., data layer, API, UI, testing)
   - Present tasks in the specified format WITHOUT sub-tasks yet
   - Inform user: "I have generated the high-level tasks based on the Linear issue. Ready to generate the sub-tasks? Respond with 'Go' to proceed."

4. **Wait for user confirmation**:

   - Pause and wait for user to respond with "Go"
   - Do NOT proceed to sub-tasks without explicit confirmation

5. **Phase 2 - Generate detailed sub-tasks**:

   - Break down each parent task into actionable sub-tasks
   - Ensure sub-tasks are specific and implementable
   - Consider existing codebase patterns without being constrained by them
   - Include testing considerations for each implementation step

6. **Identify relevant files**:

   - List files that will need creation or modification
   - Include corresponding test files where applicable
   - Provide brief descriptions of each file's purpose

7. **Generate final task list**:

   - Use the required markdown structure:

     ```markdown
     ## Relevant Files

     - `path/to/file.ts` - Brief description
     - `path/to/file.test.ts` - Unit tests for file.ts

     ### Notes

     - Testing and execution instructions

     ## Tasks

     - [ ] 1.0 Parent Task Title
       - [ ] 1.1 Sub-task description
       - [ ] 1.2 Sub-task description
     - [ ] 2.0 Parent Task Title
       - [ ] 2.1 Sub-task description
     ```

8. **Save the task list**:
   - Create `/docs/features` directory if it doesn't exist
   - Create feature directory using issue ID: `/docs/features/[issue-id]/`
   - Save as `tasks.md` in the feature directory
   - Use Linear issue ID for feature folder (e.g., T-962 → `/docs/features/T-962/tasks.md`)
   - Include reference to source Linear issue in the file

Target audience is a **junior developer** who will implement the feature with awareness of the existing codebase context. Tasks should be clear, specific, and actionable.