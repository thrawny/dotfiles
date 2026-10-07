---
allowed-tools: Read, Write(handoff.md), Write(/**/handoff.md), Glob, Grep, Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git branch:*), Bash(acpx * sessions*), TaskList, TaskStop
description: Hand off work to another session
argument-hint: "[goal] [--stay]"
---

$ARGUMENTS

Hand off the current work to a new session. A `Handoff file:` line in the arguments names where to write the handoff; the rest (if provided) is the authoritative goal for the next session. If no goal was provided, infer the logical next goal from the conversation; if unclear, state your best guess.

First, settle live async state so the next session doesn't inherit it blind: stop background tasks and teammate agents that are done or won't be needed; close finished acpx sessions. Anything deliberately left running belongs in the handoff.

Then extract the handoff from the current conversation and write it to the `Handoff file:` path exactly, even when the work happened in another repo or directory. The next session starts there. Without that line, write `handoff.md` at the root of the repo the session started in. It must contain:

1. **Working directory**: The absolute path the next session works in, such as another repo or a worktree, when it is not the handoff file's directory
2. **Next goal**: What the next session should accomplish
3. **Context**: Only information relevant to that goal — decisions made, approaches tried, current state
4. **Files**: Files to read, as absolute paths, with specific line ranges where useful
5. **Skills**: Skills the next session should invoke, if any
6. **Live state**: Anything intentionally left running and why — omit if none
7. **Immediate action**: The first concrete step to take

Don't duplicate content captured in plans, commits, diffs, or issues; reference those artifacts instead. Keep it focused and under roughly 1000 tokens.

After writing, stop. No summary needed.
