---
allowed-tools: Read, Write, Glob, Grep, TodoWrite
argument-hint: feature name or path to PRD file (e.g., user-profile or /docs/features/user-profile/prd.md)
description: Generate a detailed task list from an existing PRD for implementation
---

## Context

<!-- Check current directory and available feature directories -->

## Your task

Based on an existing Product Requirements Document (PRD), create a detailed, step-by-step task list to guide a developer through implementation.

1. **Locate and analyze the PRD**:

   - If argument is a full path (contains `/`), read the specified PRD file directly
   - If argument is a feature name, look for `/docs/features/[feature-name]/prd.md`
   - If no argument provided, list available feature directories in `/docs/features/`
   - Analyze functional requirements, user stories, and technical considerations
   - Extract key implementation needs from the PRD

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
   - Save as `tasks.md` in the same feature directory as the PRD

Target audience is a **junior developer**. Tasks should be clear, specific, and focused on core implementation only.
