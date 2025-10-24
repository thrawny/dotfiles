---
allowed-tools: Read, Write(progress.md), Glob, Grep, Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git branch:*), Task
description: Pick up work from another developer by reading progress.md and understanding the current state
---

Another developer did some work outside of this conversation, you are picking up from where they left off.

Read @progress.md to get the current state.

Also read any relevant files mentioned in progress.md to understand the context and changes made.

After reading, summarize the current state of the project and what has been done, then wait for further instructions.

CRITICAL FILE WRITING RESTRICTIONS:
- You are ONLY permitted to write to progress.md - NO OTHER FILES
- When updating progress.md, RESET it completely - do not append to existing content
- The file should contain only the current state, not a growing history
- DO NOT edit, create, or modify any other files in the codebase
- Document any needed code changes in progress.md for the next developer
