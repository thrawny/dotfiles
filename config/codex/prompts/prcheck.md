## Context

- `gh pr view <PR> --json state,mergeable,reviewDecision,title` — structured status info
- `gh api repos/<org>/<repo>/pulls/<PR>/comments` — review comments on the PR
- `gh pr view <PR> --comments` — recent comments and review feedback
- `gh pr checks <PR>` — CI/CD check status and any failures

## Your task

Monitor the PR associated with the current branch and address any issues found.

1. Find the PR: Use the current branch to identify the associated pull request.
   - If no PR exists for the current branch, inform the user and suggest creating one.
   - If multiple PRs exist, use the most recent one.
2. Accept a wait time parameter (default 120s) and start by waiting, then do the first round of checks.
3. Enter a monitoring loop:
   - Wait for the specified period.
   - Check PR status using the commands above.
   - Display clear status updates with timestamps.
   - If checks are still pending, wait and retry.
4. Address issues when found:
   - Failing CI/CD checks: analyze failure logs, identify root causes, and fix code issues.
   - Review comments: read feedback and implement requested changes.
   - Merge conflicts: resolve conflicts and update the branch.
   - Build/test failures: fix compilation errors, test failures, or dependency issues.
5. Continue until success conditions:
   - All checks passing (not pending or failing), PR mergeable, no outstanding review comments requiring action.
6. Provide clear feedback: summarize actions taken and display final status when ready to merge.

If you encounter issues that cannot be automatically resolved, explain what needs manual intervention and suggest next steps.

