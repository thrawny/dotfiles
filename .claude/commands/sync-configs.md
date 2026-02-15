---
allowed-tools: Read, Write, Edit, AskUserQuestion
description: Sync example and live config files (Claude, Codex, Cursor)
---

## Context

Pre-commit hook output: !`config/git/hooks/pre-commit`

Pre-commit hook source (defines ignore filters): @config/git/hooks/pre-commit

## Your task

Based on the hook output above:

1. **If no diffs reported**: Say "All configs in sync" and stop

2. **For each diff reported**: Parse the diff and summarize the specific changes, then use AskUserQuestion with:
   - A **question** that names the config and summarizes what changed (e.g., "Claude: hooks changed from session-tracker to agent-switch track, added steer feature")
   - **Three options**:
     - **Pull from repo** (apply example → live): The example file is the tracked source of truth, updated from other machines. This option catches up the local live file to match.
     - **Push to repo** (apply live → example): The local live file has intentional changes. This option updates the tracked example file so other machines get them too.
     - **Skip**: Leave both files as-is.
   - Option descriptions should explain the concrete effect (e.g., "Adopt agent-switch track hooks from repo" not just "Update live from example")

3. **Apply chosen actions**

Be specific about what will change - users should understand the effect of each option without needing to read the raw diff.
