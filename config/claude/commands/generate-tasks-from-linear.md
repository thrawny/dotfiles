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

2. **Generate task list**:

   - Create 2-4 high-level tasks with minimal sub-tasks (1-2 each if needed)
   - Focus on core implementation only, skip obvious setup/boilerplate
   - Include testing tasks only for complex logic, not every file change
   - Use simple markdown structure:

     ```markdown
     ## Tasks

     - [ ] 1. Parent Task Title
       - [ ] 1.1 Sub-task (if needed)
     - [ ] 2. Parent Task Title
     ```

3. **Save the task list**:
   - Save as `tasks.md` in `/docs/features/[issue-id]/` directory
   - Include reference to source Linear issue in the file

Target audience is a **junior developer**. Tasks should be clear, specific, and focused on core implementation only.