---
allowed-tools: Bash(gh pr checks:*), Bash(gh run view:*), Bash(gh run watch:*), Bash(sleep:*), Bash(notify:*)
argument-hint: instruction (e.g., "when CI passes", "when PR is merged")
description: Monitor a condition and notify when complete
---

## Context

- Current branch: `!git branch --show-current`
- PR status (if any): `!gh pr view --json state,statusCheckRollup --jq '{state: .state, checks: .statusCheckRollup}' 2>/dev/null || echo "No PR found"`

## Your task

Based on the user's instruction: **$ARGUMENTS**

1. **Parse the instruction**: Determine what condition to monitor
   - CI/build completion: watch GitHub Actions checks
   - PR merge: poll PR state
   - Custom condition: adapt monitoring approach

2. **Monitor the condition**:
   - Poll at reasonable intervals (30-60 seconds for CI, longer for merges)
   - Show brief progress updates
   - Handle failures gracefully

3. **Notify when complete**:
   - Use `notify "message"` to alert the user
   - Include relevant status (passed/failed/merged)

4. **Common patterns**:
   - "when CI passes" → `gh pr checks --watch` then notify
   - "when PR is merged" → poll `gh pr view --json state` until merged
   - "when build finishes" → watch the current run

If the condition fails (CI fails, PR closed), still notify with the failure status so the user knows to check.
