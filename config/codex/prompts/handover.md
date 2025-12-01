Another developer will take over.

First, run `archive-progress` to save the existing progress.md (if it exists).

Then write everything we did so far to progress.md. Include:
- Which model/tool created this handover (e.g., "Codex CLI with gpt-5.1-codex")
- The end goal
- The approach we're taking
- The steps we've done so far
- The current failure we're working on (if any)

Include a list of relevant files that should be read during takeover (e.g., modified files, configuration files, documentation).

IMPORTANT: When updating progress.md, RESET it completely - do not append to existing content. The file should contain only the current state, not a growing history.

CRITICAL: After writing progress.md, stop immediately. DO NOT summarize the handover back to the user. The session is ending and any summary wastes tokens and time.
