---
name: handoff
description: Write a clean `handoff.md` for the next session. Use when the user says `/handoff`, asks to hand work off to a future Codex session, or wants the current task state summarized into a short next-session brief with files and immediate next action.
---

# handoff

Write `handoff.md` for the next session and stop.

## Workflow

1. Use the user's stated next goal when provided.
2. If no goal is provided, infer the most logical next goal from the current task.
3. Ignore any existing `handoff.md` contents and overwrite the file completely.
4. Keep only information that helps the next session achieve the next goal.

## Required structure

Write these sections in `handoff.md`:

1. `Next goal`
2. `Context`
3. `Files`
4. `Immediate action`

## Guardrails

- Keep the handoff focused and under roughly 1000 tokens.
- Exclude stale context, abandoned directions, and low-signal detail.
- Include specific file paths and line references when they matter.
- After writing the handoff, stop. Do not add a separate summary.
