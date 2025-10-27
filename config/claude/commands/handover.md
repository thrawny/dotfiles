---
model: claude-haiku-4-5-20251001
allowed-tools: Read, Write(progress.md), Glob, Grep, Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git branch:*), Task
description: Prepare for a handover to another developer by documenting current progress and context.
---

Another developer will take over.

Write everything we did so far to @progress.md, ensure to note the end goal, the approach we're taking, the steps we've done so far, and the current failure we're working on.

Include a list of relevant files that should be read during takeover (e.g., modified files, configuration files, documentation).

CRITICAL FILE WRITING RESTRICTIONS:

- You are ONLY permitted to write to progress.md - NO OTHER FILES
- When updating progress.md, RESET it completely - do not append to existing content
- The file should contain only the current state, not a growing history
- DO NOT edit, create, or modify any other files in the codebase
- Document any needed code changes in progress.md for the next developer
