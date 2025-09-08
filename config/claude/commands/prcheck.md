---
allowed-tools: Bash(gh pr list:*), Bash(gh pr view:*), Bash(gh pr checks:*), Bash(gh api:*), Bash(git branch:*), Bash(sleep:*)
argument-hint: wait time
description: Monitor current branch's PR status with wait periods, identify and fix issues until ready to merge
---

## Context

- `gh pr view <PR> --json state,mergeable,reviewDecision,title` - Get structured status info
- `gh api repos/<org>/<repo>/pulls/<PR>/comments` - Get review comments on the PR
- `gh pr view <PR> --comments` - Show recent comments and review feedback
- `gh pr checks <PR>` - Show CI/CD check status and any failures

## Your task

Based on the above context, monitor the PR associated with the current branch and address any issues found. Follow these guidelines:

1. **Find the PR**: Use the current branch to identify the associated pull request

   - If no PR exists for the current branch, inform the user and suggest creating one
   - If multiple PRs exist, use the most recent one

2. **Accept wait time parameter**:

   - Default to 120 seconds if no argument provided
   - Allow user to specify custom wait time in seconds (e.g., `/prcheck 120`)
   - Start by waiting the specified time, then do the first round of checks

3. **Enter monitoring loop**:

   - Wait for the specified time period
   - Check PR status using these commands:
     - `gh api repos/<org>/<repo>/pulls/<PR>/comments` - Get review comments on the PR
     - `gh pr view <PR> --comments` - Show recent comments and review feedback
     - `gh pr checks <PR>` - Show CI/CD check status and any failures
     - `gh pr view <PR> --json state,mergeable,reviewDecision,title` - Get structured status info
   - Display clear status updates with timestamps
   - If checks are still pending, wait a bit longer

4. **Address issues when found**:

   - **Failing CI/CD checks**: Analyze failure logs, identify root causes, and fix code issues
   - **Review comments**: Read reviewer feedback and implement requested changes
   - **Merge conflicts**: Resolve conflicts and update the branch
   - **Build/test failures**: Fix compilation errors, test failures, or dependency issues

5. **Continue until success conditions met**:

   - All checks are passing (not pending or failing)
   - PR is mergeable
   - No outstanding review comments requiring action

6. **Provide clear feedback**:
   - Show progress during each check cycle
   - Summarize actions taken to resolve issues
   - Display final status when PR is ready to merge

If you encounter issues that cannot be automatically resolved, explain what needs manual intervention and provide guidance on next steps.
