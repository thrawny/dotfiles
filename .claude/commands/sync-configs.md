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
2. **For each diff reported**: Immediately use AskUserQuestion with options:
   - **Example → Live**: Update live file from example
   - **Live → Example**: Update example file from live
   - **Add to ignore**: Add the differing field(s) to the hook's jq/yq filter
   - **Skip**: Leave unchanged

3. **Apply chosen actions**

Do not output any analysis or explanation before using AskUserQuestion.
