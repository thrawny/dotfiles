
$ARGUMENTS

Hand off the current work to a new session. The argument (if provided) is the goal for the next session.

If no goal argument provided: infer the logical next goal from the conversation context. If unclear, state your best guess.

First, run the `remove-handoff` command (NOT `rm` - that requires approval). This deletes any existing handoff.md.

Write `handoff.md` with:

1. **Next goal**: What the next session should accomplish (from argument or inferred)
2. **Context**: Only information relevant to achieving that goal — decisions made, approaches tried, current state
3. **Files**: List of files to read, with specific line ranges if relevant
4. **Immediate action**: The first concrete step to take

Keep it focused. Exclude anything not relevant to the next goal. Target ~1000 tokens max.

After writing, stop. No summary needed.
