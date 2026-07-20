---
allowed-tools: Read, Write(handoff.md), Glob, Grep, Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git branch:*), Bash(remove-handoff), Bash(acpx * sessions*), TaskList, TaskStop
description: Hand off work to another session with goal-directed context extraction
---

$ARGUMENTS

Hand off the current work to a new session. The argument (if provided) is the goal for the next session.

If no goal argument provided: infer the logical next goal from the conversation context. If unclear, state your best guess.

First, run the `remove-handoff` command (NOT `rm` - that requires approval). This deletes any existing handoff.md.

Then settle live async state so the next session doesn't inherit it blind: stop background tasks and teammate agents that are done or won't be needed; close finished acpx sessions. Anything deliberately left running goes in the handoff.

Write `handoff.md` with:

1. **Next goal**: What the next session should accomplish (from argument or inferred)
2. **Context**: Only information relevant to achieving that goal — decisions made, approaches tried, current state
3. **Files**: List of files to read, with specific line ranges if relevant
4. **Skills**: Skills the next session should invoke, if any (e.g. zmx for dev servers)
5. **Live state**: Anything intentionally left running (dev servers, teammates, open acpx sessions) and why — omit if none
6. **Immediate action**: The first concrete step to take

Don't duplicate content already captured in other artifacts (plans, commits, diffs, issues) — reference them by path or URL instead.

Keep it focused. Exclude anything not relevant to the next goal. Target ~1000 tokens max.

After writing, stop. No summary needed.
