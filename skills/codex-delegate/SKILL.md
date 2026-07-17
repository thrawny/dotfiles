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

When `SANDBOX=1`, default to `--approve-all` (yolo): the host sandbox is already the isolation boundary, and nested approval friction adds little protection. Outside the sandbox, match permissions to intent:

- implementation: `--approve-all` within a tightly scoped repository and brief
- consultation or review: `--approve-reads`, optionally `--no-terminal`

Consult the `acpx` skill for the full command, permission, session, and output reference.

## Brief Codex

Codex does not inherit the conversation. Include the two things it cannot discover: decisions already made, and repository conventions that are not readily discoverable. Leave committing outside the delegation, along with secrets, private account access, releases, pushes, and merges, unless the user explicitly assigns them.

## Review

Treat Codex's diff like a contributor PR. Its report is evidence, not the verdict.

## Session hygiene

Send corrections through the same named session so Codex retains context. When a session stops being productive, take over rather than preserving the delegation for its own sake. Close named sessions after the work is settled, and in the result distinguish Codex's contribution from the independent review.
