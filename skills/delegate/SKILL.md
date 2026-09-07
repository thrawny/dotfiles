---
name: delegate
description: Delegate work to another agent through acpx when the user asks to delegate or consult another agent.
---

# Delegate

Consult the `acpx` skill for command syntax, permissions, models, and session mechanics.

## Choose

Only delegate to these models:

- Codex: `gpt-6-astra` for Astra
- Codex: `gpt-5.6-sol` for Sol
- Claude Code: `claude-fable-5-1`
- Claude Code: `claude-opus-5`

Honor an explicit choice from this list. Default to Codex with `gpt-6-astra` when no model is specified, including requests for OpenAI or Codex. Astra is a model used through the `codex` agent, not a separate agent command.

Put global `acpx` options such as `--cwd`, `--model`, and permissions before the agent name. Always ensure the named session exists, then prompt it:

```bash
# Codex on GPT-6 Astra. Substitute gpt-5.6-sol when Sol is requested.
acpx --cwd <repo root> --model gpt-6-astra --approve-all codex sessions ensure --name <session-name>
acpx --cwd <repo root> --model gpt-6-astra --approve-all codex -s <session-name> '<work order>'

# Claude Code on Fable 5.1 (substitute claude-opus-5 for Opus 5)
acpx --cwd <repo root> --model claude-fable-5-1 --approve-all claude sessions ensure --name <session-name>
acpx --cwd <repo root> --model claude-fable-5-1 --approve-all claude -s <session-name> '<work order>'
```

Use a named session for delegated work so follow-up prompts can reuse context.

## Work orders

Delegate execution, not design authority. Give delegates concrete work orders with decisions and constraints for product behavior, UX, architecture, and file structure already settled.

## Review

You remain accountable for ensuring the delegated work matches the agreed plan and intended outcome. Review for solution quality, UX, and coherence; leave broad bug hunting to PR review.

## Footguns

- Always pass `--cwd <repo root>`; session scope is tied to the exact working directory.
- The delegate does not inherit this conversation. Brief it with prior decisions, acceptance criteria, and non-obvious constraints.
- When `SANDBOX=1`, use `--approve-all`; the host sandbox is already the isolation boundary. Outside it, use `--approve-all` for scoped implementation and `--approve-reads` for review.
- Run long delegations with the harness's `background=true`. A trailing shell `&` can kill the prompt and leave an idle session.
- Delegates share the working tree. Parallel writers need disjoint scopes; otherwise serialize them or use separate worktrees.
- Use unique session names per task, and send corrections through the same session.
