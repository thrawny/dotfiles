---
name: pr
description: Create or update a GitHub pull request for the current branch. Use when the user says `/pr`, asks to open a PR, wants the branch pushed, or needs a reviewer-ready PR title and description based on the current git state.
---

# pr

Create or update the pull request for the current branch.

## Workflow

1. Inspect the current git state:
   - `git status`
   - `git diff HEAD`
   - `git branch --show-current`
   - `git log --oneline -10`
   - `git diff main...HEAD --stat`
2. If the current branch is `main` or `master`, create a feature branch first.
3. Review the changes that will land in the PR.
4. If the branch is not pushed, push it.
5. If a PR already exists, update or report on it. Otherwise create one.
6. Write a concise imperative PR title and a body that explains why the change matters.
7. Include a short test plan or reviewer checklist.
8. If there is nothing worth opening a PR for, say so.
9. If the intended scope is unclear, ask before publishing.

## Guardrails

- Do not open a PR with an unclear or mixed scope.
- Prefer the GitHub app for PR creation when available; use `gh` as fallback.
- Keep the PR description high signal and reviewer-oriented.
