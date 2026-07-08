---
name: codex-delegate
description: Delegate a coding task to Codex CLI only when the user explicitly asks to use Codex, delegate to Codex, ask Codex, or have Codex take a pass. Use in Claude Code sessions for user-requested Codex implementation, refactoring, test-writing, CI-fix, or code-exploration work; Claude still writes the brief, scopes the task, reviews the diff, and verifies results.
---

# Codex Delegate

Use this skill only in Claude Code, and only when the user clearly asks for Codex involvement. Do not silently route ordinary coding work to Codex.

The intent is controlled delegation: Codex does the requested coding/exploration pass; Claude stays responsible for the brief, boundaries, final judgment, verification, and user-facing summary.

## When to delegate

Delegate immediately when the user says things like:

- "use Codex for this"
- "delegate this to Codex"
- "ask Codex to implement/review/explore"
- "have Codex take the first pass"

Good delegation targets:

- implementation from a clear spec
- refactors or mechanical migrations
- bug fixes with a known repro
- test writing and coverage fills
- CI/build/lint fixes
- broad codebase exploration where another model reading files is useful

Keep in Claude unless the user explicitly asks otherwise:

- design, architecture, naming, API shape, and UX judgment
- tasks where clarifying the spec is the main work
- tiny one-file edits where delegation overhead is not useful
- secrets, credentials, private account access, browser/MCP/computer-use work
- releases, pushes, PR merges, and other irreversible GitHub/git operations
- review of Codex's changes

For mixed tasks, Claude first resolves the design/spec enough to make a concrete work order, then sends Codex that work order.

## Invocation

Explicit user request is permission to run Codex immediately. Do not ask for a second confirmation just to spend Codex tokens.

Use a temp prompt file instead of fragile shell quoting:

```bash
PROMPT_FILE=$(mktemp)
cat >"$PROMPT_FILE" <<'EOF'
Goal:
<what Codex should accomplish>

Repository:
<absolute repo path>

Relevant paths:
- <path>

Constraints:
- <what must not change>
- <style, compatibility, dependency, or scope limits>

Non-goals:
- <work Codex should avoid>

Verification expected:
- <exact test/check command, or explain if none exists>

Output requested:
- Summarize files changed.
- Include test/check commands run and their results.
- Call out anything unfinished or risky.
EOF

command codex exec --yolo -C <repo> \
  -c model_reasoning_effort="high" \
  -o /tmp/codex-delegate-last.md - <"$PROMPT_FILE" 2>/dev/null
```

Notes:

- `--yolo` is the default for this skill because the user explicitly requested Codex delegation and wants Codex able to edit/run commands without repeated approval prompts.
- Keep the prompt scoped to the current repo and the relevant paths.
- Suppressing stderr keeps Codex reasoning noise out of Claude's context. If the command fails, rerun without `2>/dev/null` to debug.
- Read the `-o` output file for Codex's final report; do not ingest an entire event stream unless debugging requires it.
- For independent subtasks, separate runs with separate output files are fine.
- If the directory is not a git repo and that is expected, add `--skip-git-repo-check`.

## Follow-up fixes

Prefer `resume` for follow-up corrections so Codex keeps its working context. Run it from the repo directory and use the long bypass flag:

```bash
FOLLOWUP_FILE=$(mktemp)
cat >"$FOLLOWUP_FILE" <<'EOF'
<focused correction request, including what Claude found in review>
EOF

(
  cd <repo> &&
  command codex exec resume --last \
    --dangerously-bypass-approvals-and-sandbox \
    -o /tmp/codex-delegate-last.md - <"$FOLLOWUP_FILE" 2>/dev/null
)
```

After two unproductive Codex rounds, stop delegating and either fix the issue directly in Claude or ask the user how to proceed.

## Prompt quality bar

Codex starts without this chat's full context. Every delegation prompt should include:

1. the goal in plain language
2. the exact repo and relevant paths
3. constraints and non-goals
4. expected proof, preferably an exact command
5. the required output shape

Do not send vague prompts like "fix the tests" unless the repo state itself makes the task unambiguous. A precise brief is cheaper than a broad Codex exploration loop.

## Claude verification responsibilities

Codex output is a proposal, not the final answer. Claude must:

1. Run `git status -sb`.
2. Read the full diff for files Codex changed.
3. Judge the diff like a contributor PR: correctness, scope control, style, and unintended side effects.
4. Run focused tests/checks when practical, or explicitly report if verification was not run.
5. Summarize what Codex changed, what Claude verified, and any remaining risk.

Never delegate the final review of Codex's own output back to Codex.
