---
name: delegate
description: Delegate work to another agent through acpx when the user asks to delegate or consult another agent.
---

# Delegate

Consult the `acpx` skill for command syntax, permissions, models, and session mechanics.

## Choose

Honor an explicitly requested agent or model. Otherwise, default implementation work to Codex with `gpt-5.6-sol`.

Use a named session.

## Footguns

- Always pass `--cwd <repo root>`; session scope is tied to the exact working directory.
- The delegate does not inherit this conversation. Brief it with prior decisions, acceptance criteria, and non-obvious constraints.
- When `SANDBOX=1`, use `--approve-all`; the host sandbox is already the isolation boundary. Outside it, use `--approve-all` for scoped implementation and `--approve-reads` for review.
- Run long delegations with the harness's `background=true`, never a shell trailing `&`, which can kill the prompt and leave an idle session.
- Delegates share the working tree. Parallel writers need disjoint scopes; otherwise serialize them or use separate worktrees.
- Use unique session names per task, and send corrections through the same session.

## Review

You remain accountable for ensuring the delegated work matches the agreed plan and intended outcome. Focus your efforts on quality, ux and coherence of the solution as opposed to doing a bug hunter review - leave that for the PR review.
