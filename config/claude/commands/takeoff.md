---
allowed-tools: Read, Bash(cd:*), Glob, Grep, Bash(git status:*), Bash(git diff:*), Bash(git log:*)
description: Resume work from a handoff
---

Read the handoff at `$ARGUMENTS`, or `handoff.md` at the repo root when no path is given, and any files listed in it. If it names a working directory, `cd` there and work from there.

Understand the goal and context, then briefly confirm:
- What you're picking up
- The immediate action you'll take

Wait for confirmation before proceeding.
