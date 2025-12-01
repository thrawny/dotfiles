---
allowed-tools: Bash(gh pr view:*), Bash(gh pr checks:*), Bash(gh run view:*), Bash(sleep:*), Bash(notify:*)
argument-hint: instruction (e.g., "when CI passes", "when PR is merged")
description: Monitor a condition and notify when complete
---

## Context

- Current branch: `!git branch --show-current`
- PR status (if any): `!gh pr view --json state,statusCheckRollup --jq '{state: .state, checks: .statusCheckRollup}' 2>/dev/null || echo "No PR found"`

## Your task

Based on the user's instruction: **$ARGUMENTS**

**Use a simple check-sleep loop inside Claude Code** - do NOT write bash scripts.

### Loop pattern

```
1. Check the condition (one gh command)
2. If done → notify and exit
3. If not done → sleep 30s, go to 1
```

### Common conditions

| Instruction | Check command | Done when |
|-------------|---------------|-----------|
| "when CI passes" | `gh pr checks --json state,name` | all checks have `state: "SUCCESS"` |
| "when CI finishes" | `gh pr checks --json state,name` | no checks have `state: "PENDING"` |
| "when PR is merged" | `gh pr view --json state` | `state: "MERGED"` |
| "when build finishes" | `gh run view --json status` | `status` is not `in_progress` or `queued` |

### Rules

- Poll every 30-60 seconds
- Print a one-line status each iteration (e.g., "CI still running... 3/5 checks passed")
- Always notify at the end, even on failure: `notify "CI failed"` is still useful
- Keep it simple - no complex bash, just Claude doing check/sleep/repeat
