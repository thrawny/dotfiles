---
allowed-tools: Read, Write, Edit, MultiEdit, Glob, Grep, TodoWrite, Task, Bash(git:*), Bash(gh:*), Bash(mkdir:*)
argument-hint: <issue-number> or <issue-path>
description: Intelligently work on an issue with step-by-step analysis and implementation
---

## Your task

Default issue root path: docs/issues

Work on an existing issue intelligently, providing thoughtful analysis and step-by-step implementation. Follow these guidelines:

1. **Parse and locate the issue**:

   - Accept issue number format: `/work 001` or `/work 3`
   - Accept full path format: `/work issues/feature/003-auth.md`
   - Search for issue files by number if only number provided
   - Handle missing or invalid issues gracefully with helpful error messages

2. **Analyze the issue thoroughly**:

   - Read the entire issue file carefully
   - Understand the description, context, and business value
   - Analyze the technical implementation requirements
   - Identify dependencies, constraints, and potential challenges
   - Consider the current codebase context and existing patterns

3. **Create a thoughtful work plan**:

   - Use TodoWrite to break down the work into specific, actionable tasks
   - Prioritize tasks logically based on dependencies
   - Consider testing, documentation, and deployment requirements
   - Include validation and review steps

4. **Execute implementation with reasoning**:

   - Work through tasks systematically, marking progress in TodoWrite
   - Explain your thinking and decision-making process
   - Follow existing code patterns and conventions
   - Write clean, well-documented code
   - Handle edge cases and error scenarios

5. **Track progress and update issue**:

   - Mark completed items in the Definition of Done checklist
   - Update the issue file with implementation notes and progress
   - Add any discovered requirements or considerations to the issue
   - Update status appropriately (In Progress, Completed, etc.)

6. **Create git branch and commit work**:

   - Create a new feature branch based on issue number/name
   - Stage all relevant changes for the issue
   - Create a meaningful commit message referencing the issue
   - Push the branch to remote repository

7. **Create pull request**:

   - Generate PR title from issue title
   - Create comprehensive PR description with:
     - Link to the original issue
     - Summary of changes implemented
     - Test plan and validation steps
     - Any breaking changes or considerations
   - Include Claude Code signature in PR description

8. **Provide comprehensive feedback**:
   - Explain what was implemented and why
   - Display the created branch name and PR URL
   - Highlight any decisions made or trade-offs considered
   - Note any remaining work or follow-up issues needed
   - Suggest next steps for review and deployment

### Intelligent Analysis Process

When working on an issue:

- **Understand before implementing**: Read the entire issue and related context
- **Think step-by-step**: Break complex problems into manageable pieces
- **Consider the bigger picture**: How does this fit into the overall system?
- **Follow best practices**: Code quality, testing, documentation, security
- **Be thorough**: Don't skip validation, error handling, or edge cases

### Error Handling

- If issue file not found, list available issues and suggest correct format
- If issue is incomplete or unclear, ask for clarification before proceeding
- If dependencies are missing, identify and request them
- If implementation hits blockers, document them and suggest solutions

### Git Workflow

After completing implementation:

- **Branch naming**: Use format `issue-{number}-{short-description}` (e.g., `issue-001-user-auth`)
- **Commit message**: Reference issue number and provide clear description
- **PR title**: Use format "Issue #{number}: {issue title}"
- **PR description template**:

  ```markdown
  ## Summary

  Implements [brief description of changes]

  Closes #{issue-number}

  ## Changes

  - [List of main changes made]

  ## Test Plan

  - [Testing steps performed]
  - [Manual verification completed]

  ## Considerations

  - [Any breaking changes or deployment notes]

  🤖 Generated with [Claude Code](https://claude.ai/code)
  ```

### Implementation Types

Adapt approach based on issue type:

- **Features**: Focus on user value, UX, and integration
- **Bugs**: Root cause analysis, testing, and verification
- **Refactoring**: Code quality, performance, and maintainability
- **Documentation**: Clarity, completeness, and accuracy
- **Configuration**: Environment setup, deployment, and operations

If no argument provided, list available issues. If multiple issues match a number pattern, ask for clarification. Always provide thoughtful analysis and clear reasoning throughout the implementation process.
