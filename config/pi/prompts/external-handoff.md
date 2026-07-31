---
description: Write a focused handoff.md for another agent harness
argument-hint: "[next goal]"
---
User-supplied next goal (if any): $ARGUMENTS

Write `handoff.md` for another coding agent running in a different harness, then stop. Do not open a new Pi session or use Pi's automatic handoff flow.

Use the user's supplied next goal when present. Otherwise infer the logical next goal from the conversation; if it is unclear, state your best guess.

Before writing, settle live asynchronous state so the next agent does not inherit it blindly: stop background tasks and agents that are finished or will not be needed, and close finished agent sessions. Record anything deliberately left running.

Overwrite `handoff.md` completely with these headings:

## Next goal
## Current state
## Decisions and rationale
## Files and artifacts
## Verification
## Constraints and preferences
## Live state
## Immediate action

Rules:
- Assume the next agent has no access to this conversation or Pi's parent-session history.
- Include only facts relevant to achieving the next goal.
- Preserve exact paths, symbols, commands, errors, and test results when useful.
- Reference plans, commits, diffs, issues, and other durable artifacts instead of duplicating them.
- Record rejected approaches only when doing so prevents repeated work.
- If a section has nothing relevant, write `(none)`.
- Keep the handoff under roughly 1000 tokens.
- After writing the file, stop without a separate summary.
