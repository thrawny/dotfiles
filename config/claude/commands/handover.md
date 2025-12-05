---
model: claude-haiku-4-5-20251001
allowed-tools: Read, Bash(archive-progress), Write(progress.md), Glob, Grep, Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git branch:*), Task
description: Prepare for a handover to another developer by documenting current progress and context.
---

Another developer will take over.

Steps:
1. CRITICAL: Run `archive-progress` in Bash. This script exists in PATH. Do NOT implement archiving manually - just execute the script.
2. Write everything we did so far to @progress.md, including:

- Which tool created this handover (e.g., "claude")
- The end goal
- The approach we're taking
- The steps we've done so far
- The current failure we're working on (if any)

Include a list of relevant files that should be read during takeover (e.g., modified files, configuration files, documentation).

File writing restrictions:

- Only write to progress.md - no other files
- Reset progress.md completely - don't append to existing content
- The file should contain only the current state, not a growing history
- Don't edit, create, or modify any other files in the codebase
- Document any needed code changes in progress.md for the next developer

After writing progress.md, stop immediately. Don't summarize the handover back to the user - the session is ending and any summary wastes tokens and time.
