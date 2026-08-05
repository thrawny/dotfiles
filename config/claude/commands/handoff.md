---
allowed-tools: Read, Write(handoff.md), Glob, Grep, Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git branch:*), Bash(remove-handoff), Bash(claude-handoff-promote), Bash(acpx * sessions*), TaskList, TaskStop
description: Hand off work to another session, reusing the auto-handoff when available
---

$ARGUMENTS

Hand off the current work to a new session. The argument (if provided) is the authoritative goal for the next session. If no goal was provided, infer the logical next goal from the conversation; if unclear, state your best guess.

First, run `remove-handoff` (NOT `rm`, which requires approval) to delete any existing repo handoff.

Then settle live async state so the next session doesn't inherit it blind: stop background tasks and teammate agents that are done or won't be needed; close finished acpx sessions. Anything deliberately left running belongs in the handoff.

Next, run exactly `claude-handoff-promote`. Its PostToolUse hook will report one of two outcomes:

- **Auto-handoff promoted:** Read `handoff.md` and use it as the draft. Do not reconstruct it from scratch. Apply the supplied goal as authoritative (or the inferred goal if none was supplied), and reconcile only meaningful changes since the snapshot was written — especially files touched, test/gate results, unresolved errors, and live state.
- **No auto-handoff:** Extract a fresh handoff from the current conversation.

The final `handoff.md` must contain:

1. **Next goal**: What the next session should accomplish
2. **Context**: Only information relevant to that goal — decisions made, approaches tried, current state
3. **Files**: Files to read, with specific line ranges where useful
4. **Skills**: Skills the next session should invoke, if any
5. **Live state**: Anything intentionally left running and why — omit if none
6. **Immediate action**: The first concrete step to take

Don't duplicate content captured in plans, commits, diffs, or issues; reference those artifacts instead. Keep it focused and under roughly 1000 tokens.

After writing, stop. No summary needed.
