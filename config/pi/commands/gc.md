---
description: Create a git commit
thinking: off
---

## Context

### Git status

!`git status`

### Diff (staged and unstaged)

!`git diff HEAD`

### Recent commits

!`git log --oneline -10`

## Your task

{{#if ARGUMENTS}}User commit instruction: $ARGUMENTS

{{/if}}Create a single git commit for only the changes you have been working on in this session.

Do not stage unrelated worktree changes, even if they appear in the status or diff. Use the conversation context to identify your changes. If the user supplied explicit commit instructions, follow them instead; for example, `all`, `--all`, or `-a` means include every changed file, and explicit paths/scopes mean include matching files.

You have the capability to call multiple tools in a single response. Stage the selected files and create the commit using a single message. Do not use any other tools or do anything else. Do not send any other text or messages besides these tool calls.
