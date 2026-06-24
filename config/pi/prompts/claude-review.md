---
description: Run a code review via headless `claude -p` and fix the major findings
---

Run a code review of the current changes using a headless Claude, then fix the clear major issues yourself.

## Scope

If the user names a scope (a branch, a commit range, specific files), review that. With no instructions, default to the previous commit (`HEAD~1..HEAD`).

## Run the review

Use `claude -p` — it prints the review to stdout and exits on its own, so there's no session, polling, or `zmx` to manage.

```bash
claude -p --permission-mode auto \
  "/code-review review only the diff HEAD~1..HEAD. Report findings only: do NOT edit files, post comments, run fixes, or commit. Focus on real correctness bugs and clear issues; skip nitpicks, style, and likely false positives."
```

- Edit the scope phrase in the prompt to match what the user asked for.
- `--permission-mode auto` lets the inner review read files and run `git`/`grep` unattended; it stays read-only and won't touch the working tree.
- For a deeper pass, ask `/code-review` for higher effort (e.g. add `high` or `max` to the prompt).

## After the review

Read the printed findings and fix only the clear major issues (P1-level correctness bugs) in this repo — the review run doesn't edit anything. Leave nitpicks, style, and uncertain findings alone unless the user asks for more.
