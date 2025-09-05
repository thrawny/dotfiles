## Context

- Current git status: `git status`
- Current git diff (staged and unstaged changes): `git diff HEAD`
- Current branch: `git branch --show-current`
- Recent commits on current branch: `git log --oneline -10`
- Branch comparison with main: `git diff main...HEAD --stat`

## Your task

Based on the above git context, create a pull request or push the current branch if a pull request exists already. Guidelines:

1. Check current branch: If you're on the main/master branch, create a new branch first.
2. Analyze the changes: Review all commits and changes that will be included in the PR.
3. Ensure branch is pushed: Push the current branch to remote if needed.
4. Create a meaningful PR title and description that:
   - Uses imperative mood (e.g., "Add feature" not "Added feature").
   - Is concise but descriptive.
   - Follows existing PR conventions.
   - Explains the "why" and impact, not just the "what".
5. Include a brief test plan or checklist for reviewers.

If there are no changes to create a PR for, say so. If you need clarification about what should be included, ask before proceeding.

