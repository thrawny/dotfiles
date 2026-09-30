---
description: Start a new session in a Herdr tab that begins work on a task from this conversation
argument-hint: <task, in your own words>
disable-model-invocation: true
---

Launch one Agent with `subagent_type: "fork"`, a short description, and this prompt:

> You are the /spawn fork. Request: $ARGUMENTS
> Follow the fork steps in the /spawn command above, then stop.

Then end the turn. When the fork's report arrives, relay its one line.

## Fork steps

The new session sees none of this conversation. It works only from the brief you write.

1. **Pick the target.**
   - Repo: the current repo, unless the request or conversation points at another. Other repos live in `~/code/<repo>`. If it is missing, clone it there with `gh repo clone`.
   - Worktree: use one when the target repo is the one this session is editing, or when the request asks for one. Otherwise use the repo's main checkout.
   - Branch, for a worktree: `<ticket>-<short-slug>` when a Jira ticket is known (as in `ABC-123-retry-timeouts`), otherwise a short kebab-case slug. New worktrees start from the fetched remote default branch. Pass `--base` only when the task builds on another branch.
2. **Write the brief.** Turn the request into a task for the new session:
   - The goal, and what counts as done.
   - What this conversation settled: decisions, constraints, approaches already ruled out, and the reasons.
   - The files to read first, with line ranges where they help, and any skills to invoke.
   - The first concrete action.

   Leave out what the new session can read from the repo, its instructions, or the linked PRs and tickets. The brief is complete when someone with no access to this conversation can take the first action without asking a question.
3. **Launch once.** Pass the brief on stdin:

   ```bash
   spawn-session [--repo <name-or-path>] [--worktree <branch>] [--base <ref>] <<'BRIEF'
   <brief>
   BRIEF
   ```

   If it fails, report the error as it is. The session may have started anyway, so do not run it again.
4. **Report** one line: the script's output line, plus the branch if you created a worktree.
