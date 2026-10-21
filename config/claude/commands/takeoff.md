---
allowed-tools: Read, Bash(cd:*), Glob, Grep, Bash(git status:*), Bash(git diff:*), Bash(git log:*)
description: Resume work from a handoff
---

Read the handoff at `$ARGUMENTS`, or `handoff.md` at the repo root when no path is given, and any files listed in it. If it names a working directory, `cd` there and work from there.

Understand the goal and context, then say in a line or two what you're picking up and the immediate action, and start on it right away.

Wait for confirmation first only when the handoff says to, or when the immediate action is one you'd need approval for anyway, such as a push, a merge or a post.
