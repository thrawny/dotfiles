---
allowed-tools: Read, Write, Edit, MultiEdit, Glob, Grep, TodoWrite, Task,
argument-hint: feature name or task file path (e.g., user-profile, T-962, or /docs/features/user-profile/tasks.md)
description: Automatically process task list and create PR - fully autonomous implementation workflow
---

## Context

This command is for **autonomous agent workflows** without human supervision. It will work through an entire task list and produce a pull request.

## Your task

Based on a task file path or identifier, locate the corresponding task file and implement all tasks autonomously, culminating in a pull request.

1. **Initialize autonomous workflow**:

   - If argument looks like a path (`/docs/features/...`), use it directly
   - If argument is an identifier (e.g., `T-962`, `user-profile`), look for:
     - `/docs/features/{identifier}/tasks.md`
   - If task file doesn't exist, list available feature directories and ask user to specify
   - Extract feature/issue name from argument or task file path for branch naming
   - Create git branch using format: `feature/{identifier}` or `{identifier}`

2. **Load and parse task list**:

   - Read the complete task file
   - Parse all parent tasks and sub-tasks
   - Track progress by updating checkmarks directly in the task file

3. **Autonomous implementation loop**:

   - Work through each task systematically
   - For each task:
     - Mark as in progress in task file (change `- [ ]` to `- [WIP]`)
     - Implement the required changes using available tools
     - **MANDATORY quality gate - must pass ALL before proceeding:**
       1. Run all relevant tests - must pass
       2. Run linting commands - must pass with no errors
       3. Run type checking - must pass with no errors
       4. **MUST consult code-reviewer agent** - review all changes made in this task
       5. **Fix any issues found by code-reviewer** before proceeding
       6. Re-run tests/linting after fixes until everything is green
     - **Commit after each task** with descriptive message
     - Mark as completed in task file (change `- [WIP]` to `- [x]`) only after all quality gates pass
     - Move to next task
   - Handle errors gracefully - if a task fails critical quality gates, document and stop execution

4. **Code quality assurance**:

   - Quality gates are enforced after each individual task (see step 3)
   - Follow existing codebase patterns and conventions
   - Never proceed to next task unless current task passes all quality checks
   - Each task results in a clean, tested, reviewed commit

5. **Progress tracking**:

   - Track progress by updating checkmarks in the task file itself
   - Log any blockers or deviations from original plan in task file
   - Provide status updates as tasks are completed

6. **Completion and PR creation**:

   - Once all tasks completed, run final quality checks
   - Commit all changes with descriptive commit message
   - Push branch to remote repository
   - Create pull request with:
     - Title: Derived from task file name or feature description
     - Description: Summary of implemented changes
     - List of completed tasks
     - Reference to source task file

7. **Final summary**:
   - Provide completion report including:
     - Tasks completed vs total
     - Any issues encountered
     - PR URL and key details
     - Next steps for review/deployment

**Error handling**:

- If critical errors occur, document in commit message and stop execution
- For non-critical issues, log and continue with remaining tasks
- Always leave codebase in working state

**Safety measures**:

- Never commit broken code
- Always run tests before final commit
- Validate all changes compile/run correctly
- Create meaningful commit messages and PR descriptions

This command is designed for **fully autonomous execution** - no human intervention expected during the implementation process.
