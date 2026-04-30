---
name: pi-reload-runtime
description: Reload Pi's extension/runtime from inside an agent turn using delayed wtype input. Use when the human asks for agent-driven development of Pi itself, Pi extension changes, or other Pi configuration work that needs /reload before the agent can test or continue in the updated runtime.
---

# Pi Reload Runtime

Use a delayed `wtype` sequence when agent-driven Pi development requires reloading the active Pi TUI after the current turn finishes. Do not type `/reload` immediately during a running turn; it can land in the editor or fail to execute.

## Workflow

1. Queue a delayed background command with `sleep` before typing into Pi.
2. Let the current assistant turn finish.
3. The delayed command types `/reload` and presses Enter while Pi is idle.
4. After a short delay, type a continuation prompt and press Enter.
5. Do no meaningful follow-up work after scheduling the delayed command in the same turn.

## Command

Prefer this pattern:

```bash
(sleep 5; wtype '/reload'; wtype -k Return; sleep 3; wtype 'continue'; wtype -k Return) &
```


Customize the continuation text when needed:

```bash
(sleep 5; wtype '/reload'; wtype -k Return; sleep 3; wtype 'Continue the previous task after reload.'; wtype -k Return) &
```

## Notes

- This is focus-dependent: Pi must be focused when `wtype` runs.
- Keep the initial sleep long enough for the current turn to finish; use a larger value for long final messages.
- Use this when the human asks for agent-driven Pi development work that needs reloading before validation can continue.
- If the user says “try reload with wtype” or “reload and continue”, use this delayed pattern.
