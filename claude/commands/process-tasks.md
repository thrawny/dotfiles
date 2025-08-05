---
allowed-tools: Read, Write, Edit, MultiEdit, Glob, Grep, TodoWrite
argument-hint: path to task list file (e.g., /docs/tasks/tasks-feature-name.md)
description: Execute tasks from a task list with proper workflow management
---

## Context

Use Glob to check for existing task files and directory structure. Check git status if needed.

## Your task

Execute tasks from a task list markdown file following proper development workflow with testing, staging, and committing.

1. **Load and analyze task list**:
   - Read the specified task list file (provided as argument)
   - If no argument provided, look for task files in `/docs/tasks/` directory
   - Identify the next pending sub-task to work on
   - Review relevant files section for context

2. **Single sub-task execution protocol**:
   - **Work on ONE sub-task at a time only**
   - Do NOT start the next sub-task until user gives permission
   - Ask user: "Ready to work on the next sub-task? (y/n)"
   - Wait for explicit "yes", "y", or "go" before proceeding

3. **Sub-task implementation workflow**:
   - Clearly identify which sub-task is being worked on
   - Implement the required changes following existing code patterns
   - Test changes locally if possible
   - Mark the sub-task as completed `[x]` in the task list file

4. **Parent task completion protocol**:
   When ALL sub-tasks under a parent task are marked `[x]`:
   - **First**: Run the appropriate test suite:
     - `npm test` for Node.js projects
     - `pytest` for Python projects
     - `bin/rails test` for Rails projects
     - Or project-specific test command
   - **Only if all tests pass**: Stage changes with `git add .`
   - **Clean up**: Remove any temporary files or temporary code
   - **Commit**: Create descriptive commit using conventional format:
     ```bash
     git commit -m "feat: brief description of parent task" \
                -m "- Key change 1" \
                -m "- Key change 2" \
                -m "Related to [task-number] in PRD"
     ```
   - Mark the parent task as completed `[x]`

5. **Task list maintenance**:
   - Update the task list file after each sub-task completion
   - Add newly discovered tasks as they emerge during implementation
   - Update the "Relevant Files" section with any new files created/modified
   - Keep file descriptions accurate and current

6. **Error handling and blocking issues**:
   - If tests fail, do NOT commit changes
   - Report test failures to user and ask for guidance
   - If implementation is blocked, document the blocker as a new task
   - Never mark a task as completed if it's not fully functional

7. **Progress reporting**:
   - After each sub-task, show current progress
   - Report which parent tasks are completed
   - Indicate next sub-task to be worked on
   - Provide clear status updates

8. **Completion workflow**:
   - When all tasks are completed, run final test suite
   - Ensure all changes are properly committed
   - Provide summary of what was accomplished
   - Suggest next steps (e.g., creating PR, deployment)

The process enforces strict discipline: **one sub-task at a time**, user permission between tasks, proper testing before commits, and comprehensive progress tracking.