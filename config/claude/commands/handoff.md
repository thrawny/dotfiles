---
allowed-tools: Read, Write(handoff.md), Glob, Grep, Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git branch:*)
description: Hand off work to another session with goal-directed context extraction
---

$ARGUMENTS

Hand off the current work to a new session. The argument (if provided) is the goal for the next session.

If no goal argument provided: infer the logical next goal from the conversation context. If unclear, state your best guess.

If `handoff.md` exists, ignore it — it's from a previous session. Overwrite completely.

Write `handoff.md` with:

1. **Next goal**: What the next session should accomplish (from argument or inferred)
2. **Context**: Only information relevant to achieving that goal — decisions made, approaches tried, current state
3. **Files**: List of files to read, with specific line ranges if relevant
4. **Immediate action**: The first concrete step to take

Keep it focused. Exclude anything not relevant to the next goal. Target ~1000 tokens max.

After writing, stop. No summary needed.
