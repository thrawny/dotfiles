---
name: codex-delegate
description: Delegate coding work to Codex through acpx when the user explicitly asks to use or consult Codex, while retaining scope, review, verification, and final judgment.
---

# Codex Delegate

Use the lightest delegation shape that gives Codex enough context and keeps the result independently reviewable.

## Choose the lightest useful acpx shape

Use one-shot execution when the prompt is self-contained:

```bash
acpx --cwd <repo> codex exec '<prompt>'
```

Use a named session when the work may need follow-ups:

```bash
acpx --cwd <repo> codex sessions ensure --name <task>
acpx --cwd <repo> --approve-all codex -s <task> '<prompt>'
```

Pass `--file <path>` instead of inline text when the brief is long or worth preserving. Use the agent harness's background execution facility for long tasks; foreground is simpler when waiting is cheap. Keep the background task ID and acpx session name available so progress, follow-ups, and cancellation remain unambiguous.

Let the configured Codex model stand unless the user wants an override. When `SANDBOX=1`, default to `--approve-all` (yolo): the host sandbox is already the isolation boundary, and nested approval friction adds little protection. Outside the sandbox, match permissions to intent:

- implementation: `--approve-all` within a tightly scoped repository and brief
- consultation or review: `--approve-reads`, optionally `--no-terminal`

Consult the `acpx` skill for the full command, permission, session, and output reference.

## Give Codex the missing context

Codex does not inherit the conversation. Supply enough of the following to remove consequential guessing, without turning every delegation into a template-filling exercise:

- the concrete outcome
- relevant context and paths
- decisions already made
- scope boundaries and meaningful non-goals
- repository conventions that are not readily discoverable
- checks or runtime evidence expected

For implementation work, normally ask Codex to summarize changes, checks, assumptions, and remaining risks, and leave committing outside the delegation. Keep secrets, private account access, releases, pushes, and merges outside the delegation unless the user explicitly assigns them.

## Keep judgment outside the delegation

Read Codex's report and treat its diff like a contributor PR. Inspect the complete change, compare it with the brief, and independently run or account for the checks that matter. Codex's report is evidence, not the verdict.

Choose verification that exercises the behavior being claimed. Static checks suit static claims; runtime changes need evidence from the relevant runtime boundary. Verification may be delegated when useful, while failure triage and final judgment remain independent of Codex.

## Continue or stop explicitly

Send focused corrections through the same named session so Codex retains context:

```bash
acpx --cwd <repo> --approve-all codex -s <task> --file <follow-up.md>
```

When a session stops being productive, take over rather than preserving the delegation for its own sake.

If the user says stop, cancel the active turn and close the session:

```bash
acpx --cwd <repo> codex cancel -s <task>
acpx --cwd <repo> codex sessions close <task>
```

Close named sessions after the work is settled. In the user-facing result, distinguish Codex's contribution from the independent review and state what was verified, what was committed, and what risk remains.
