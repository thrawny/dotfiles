---
name: takeoff
description: Resume work from `handoff.md` without charging ahead. Use when the user says `/takeoff`, asks to pick up a previous handoff, or wants Codex to read the saved next-session context, summarize what it is picking up, and wait for confirmation before proceeding.
---

# takeoff

Resume from `handoff.md`, confirm understanding, and wait.

## Workflow

1. Read `handoff.md`.
2. Read every file listed in the handoff completely.
3. Understand the next goal, current state, and immediate action.
4. Reply briefly with:
   - what you are picking up
   - the immediate action you will take next
5. Wait for user confirmation before continuing.

## Guardrails

- Do not continue implementation after the confirmation message.
- If the handoff is missing or incomplete, say so clearly.
- Treat the handoff as context for the next step, not as a command to start editing immediately.
