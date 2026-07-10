---
name: codex-delegate
description: Delegate a coding pass to Codex when the user explicitly asks to use or consult Codex. Use in Claude Code for requested implementation, refactoring, test-writing, CI fixes, or code exploration; Claude retains scoping, review, and verification.
---

# Codex Delegate

Codex performs the requested pass; Claude owns the brief, boundaries, final judgment, verification, and user-facing result. Explicit user delegation is sufficient permission to start without asking again.

## 1. Write a bounded work order

Codex does not inherit the conversation. Create a run directory and put the work order in its prompt file:

```bash
RUN_DIR=$(mktemp -d)
PROMPT_FILE="$RUN_DIR/prompt.md"
```

```md
Goal:
<concrete outcome>

Repository:
<absolute path>

Relevant paths:
- <path>

Constraints:
- <scope, style, compatibility, and dependency limits>

Non-goals:
- <work to avoid>

Verification:
- <exact checks, or why none exists>

Report:
- Summarize files changed and checks run.
- Call out unfinished work and risks.
```

Resolve design, naming, API, and UX decisions before delegation. Keep secrets, private account access, browser work, releases, pushes, merges, and review of Codex's own output with Claude.

This step is complete when Codex can execute without guessing the contract or scope.

## 2. Run Codex in a workspace sandbox

```bash
REPORT_FILE="$RUN_DIR/report.md"
EVENTS_FILE="$RUN_DIR/events.jsonl"
THREAD_FILE="$RUN_DIR/thread-id"

command codex exec \
  --sandbox workspace-write \
  --json \
  -C <repo> \
  -c model_reasoning_effort="high" \
  -o "$REPORT_FILE" \
  - <"$PROMPT_FILE" >"$EVENTS_FILE" 2>/dev/null

jq -r 'select(.type == "thread.started") | .thread_id' "$EVENTS_FILE" \
  | head -n 1 >"$THREAD_FILE"
test -s "$THREAD_FILE"
```

The workspace-write sandbox lets Codex edit the repository without granting unrestricted host access. The event stream records the exact thread for follow-ups while the `-o` file contains the concise final report. If execution or thread capture fails, inspect the event file and rerun without stderr suppression to diagnose it.

Give every independent task its own run directory so reports, events, and thread IDs cannot collide. Add `--skip-git-repo-check` only when a non-git workspace is expected.

## 3. Review the proposal

Treat Codex's work like a contributor PR:

1. Inspect `git status -sb` and the complete diff for changed files.
2. Verify correctness, scope, repository style, and unintended effects.
3. Run focused checks when practical.
4. Correct issues directly or send one focused follow-up.

For a follow-up, resume the captured thread explicitly:

```bash
CODEX_THREAD_ID=$(<"$THREAD_FILE")
command codex exec resume "$CODEX_THREAD_ID" \
  -o "$REPORT_FILE" \
  - <"$FOLLOWUP_FILE" 2>/dev/null
```

Never use `resume --last`: another delegation or interactive Codex session may be newer. After two unproductive Codex rounds, take over or ask the user how to proceed.

The delegation is complete when Claude has reviewed the diff, run or accounted for relevant checks, and can summarize what changed and any remaining risk.
