---
name: codex-delegate
description: Delegate coding work to Codex through acpx when the user explicitly asks to use or consult Codex.
---

# Codex Delegate

Use the lightest delegation shape that gives Codex enough context and keeps the result independently reviewable.

One-shot execution when the prompt is self-contained:

```bash
acpx --cwd <repo> codex exec '<prompt>'
```

A named session when the work may need follow-ups:

```bash
acpx --cwd <repo> codex sessions ensure --name <task>
acpx --cwd <repo> --approve-all codex -s <task> '<prompt>'
```

Default to a named session — the open session makes follow-ups ("fix X in the same context") free, which one-shots can't recover. Reserve one-shot exec for throwaway consultations that will never need a second prompt.

## Launch mechanics

- Always pass `--cwd <repo root>` explicitly; a session created from a subdirectory inherits that scope and must be recreated.
- Session names are unique per task (`round13`, `migrate-pkg-foo`), never reused across parallel delegations.
- For long-running prompts, make the acpx invocation itself the background task (the harness's run-in-background). Never shell-background with a trailing `&` — the prompt dies with the shell and the session is left created but idle.
- Codex writes into the working tree. Parallel writers are fine when each delegation is scoped to a disjoint area and the brief says so explicitly; scope the review to catch strays. Shared files (lockfiles, generated code, barrel exports) or unclear boundaries call for separate worktrees or serializing.

When `SANDBOX=1`, default to `--approve-all` (yolo): the host sandbox is already the isolation boundary, and nested approval friction adds little protection. Outside the sandbox, match permissions to intent:

- implementation: `--approve-all` within a tightly scoped repository and brief
- consultation or review: `--approve-reads`, optionally `--no-terminal`

Consult the `acpx` skill for the full command, permission, session, and output reference.

## Brief Codex

Codex does not inherit the conversation. Include the two things it cannot discover: decisions already made, and repository conventions that are not readily discoverable. Leave committing outside the delegation, along with secrets, private account access, releases, pushes, and merges, unless the user explicitly assigns them.

For multi-part work, split the brief into parts and review between prompts in the same session ("Part 1 is approved as-is. Now implement Part 2...") — the review findings shape the next prompt, and Codex keeps its context.

## Review

Treat Codex's diff like a contributor PR. Its report is evidence, not the verdict. Start by checking the diff exists and stays in scope — a delegation that reports success over an empty or out-of-scope diff has failed, whatever the report says. Codex occasionally fabricates plausible details (fields the API never served); verify claims against ground truth, and prefer fixing small review findings yourself over another delegation round-trip.

## Session hygiene

Send corrections through the same named session so Codex retains context. When a session stops being productive, take over rather than preserving the delegation for its own sake. Close a session once its work is settled (reviewed, gated, committed); leave it open after a failure so the follow-up still has context. In the result, distinguish Codex's contribution from the independent review.
