---
name: prcheck
description: Monitor the current branch pull request, address CI and review issues, and keep iterating until the PR is ready. Use when the user says `/prcheck`, asks to check a PR, monitor a PR, fix PR checks, address review feedback, or keep a PR green.
---

# prcheck

Monitor the pull request associated with the current branch and address issues until it is ready to merge, while respecting any narrower instructions from the user.

## Workflow

1. Identify the current branch and its pull request.
   - If there is no pull request for the current branch, tell the user and stop unless they asked you to create one.
   - If multiple pull requests match, choose the active one that best matches the current branch and explain the choice.
2. Inspect the pull request state.
   - Check mergeability, review decision, branch status, CI/check status, and recent comments.
   - Read enough detail to understand failures before changing code.
3. Monitor pending work as needed.
   - Do not use a fixed wait-time argument or require the user to choose a polling interval.
   - Watch, poll, or re-check using whatever cadence fits the situation and the available tools.
   - Keep the user informed with concise status updates during long waits.
4. Address actionable issues.
   - Fix failing checks by reading logs, identifying root causes, editing code, and running appropriate local validation.
   - Address review comments and requested changes that apply to the PR.
   - Resolve merge conflicts when it is safe and within the user's requested scope.
   - Push fixes when the PR branch needs remote updates.
5. Repeat until the PR is ready or blocked.
   - Continue checking after each fix because CI and reviewers may produce new feedback.
   - Stop only when checks are passing, the PR is mergeable, and there are no outstanding actionable review issues, or when a real blocker requires user input.

## Codex Review Monitoring

When Codex has reacted to the pull request with eyes, treat that as an active Codex review in progress.

- Monitor the pull request until Codex posts its review result.
- If Codex reports issues, address them, push fixes, resolve or mark the fixed Codex issues as handled when the platform supports it, and continue monitoring.
- Repeat the review/fix/monitor cycle until Codex gives a thumbs up or otherwise indicates there are no remaining issues.
- This is the default behavior for `prcheck`, but explicit user instructions still win. If the user asks for a narrower check, a status-only pass, or no code changes, follow that instead.

## Guardrails

- Prefer existing project commands and repository guidance for validation.
- Keep fixes scoped to the pull request issues being addressed.
- Do not make unrelated refactors while chasing checks.
- If a failure is flaky, external, permission-related, or requires a decision from the user, explain the evidence and the next manual step.
- In the final response, summarize the final PR state, what was changed, what was verified, and anything still pending.
