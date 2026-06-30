---
name: prcheck
description: Create, update, monitor, and fix the current branch pull request until it is ready. Use when the user says `/prcheck` or `/pr`, asks to open/create/update/check/monitor a PR, fix PR checks, address review feedback, or keep a PR green.
---

# prcheck

Create or monitor the pull request associated with the current branch and address issues until it is ready to merge, while respecting any narrower instructions from the user.

## Workflow

1. Inspect the current git state and identify the branch.
   - Understand the commits and diff that will land in the pull request.
   - If the branch is `main` or `master` and the user asked to create a PR, create an appropriately scoped branch first when safe. Ask if the intended scope is unclear.
2. Identify the current branch pull request.
   - If there is no pull request and the user asked to create, open, publish, or update one, create it.
   - If there is no pull request and the user only asked to monitor or check one, tell the user and stop unless they want one created.
   - If multiple pull requests match, choose the active one that best matches the current branch and explain the choice.
3. For a new pull request, write a reviewer-oriented title and description.
   - Use a concise imperative title.
   - Explain why the change matters, not just what files changed.
   - Include the required reviewer guidance described below.
4. Inspect the pull request state.
   - Check mergeability, review decision, branch status, CI/check status, and recent comments.
   - Read enough detail to understand failures before changing code.
5. Monitor pending work as needed.
   - Do not use a fixed wait-time argument or require the user to choose a polling interval.
   - Watch, poll, or re-check using whatever cadence fits the situation and the available tools.
   - Keep the user informed with concise status updates during long waits.
6. Address actionable issues.
   - Fix failing checks by reading logs, identifying root causes, editing code, and running appropriate local validation.
   - Address review comments and requested changes that apply to the PR.
   - Resolve merge conflicts when it is safe and within the user's requested scope.
   - Push fixes when the PR branch needs remote updates.
7. Repeat until the PR is ready or blocked.
   - Continue checking after each fix because CI and reviewers may produce new feedback.
   - Stop only when checks are passing, the PR is mergeable, and there are no outstanding actionable review issues, or when a real blocker requires user input.

## Initial PR Description

When creating the initial pull request, include explicit instructions for reviewers. The description should help human and agent reviewers focus on the intended risks and avoid relitigating deliberate choices.

Include:

- **Original goal:** the user-facing or engineering goal that motivated the change.
- **Reviewer focus:** the kinds of issues reviewers should look for, similar to a gauntlet/code-review pass: bugs, regressions, missing tests, security or data-loss risks, unclear behavior, and mismatches with the original goal.
- **Deliberate choices reviewers should not flag:** intentional tradeoffs, accepted limitations, compatibility decisions, scope boundaries, or follow-up work that should not be treated as defects in this PR.
- **Validation:** commands run, checks performed, or the reason validation was not run.

If updating an existing pull request whose description lacks this context, add or revise the reviewer guidance when that is within the user's requested scope.

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
