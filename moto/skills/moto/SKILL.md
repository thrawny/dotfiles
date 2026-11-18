---
name: moto
description: How a worker session runs moto. Load before any `moto` command, such as spawning a worker, reporting to the driver, or telling, listing or closing workers you started.
---

# moto for workers

A driver session started you with `moto spawn`. moto tracks each worker as a task and carries reports between workers and the driver. Who decides what, who owns a task, and what a report means are in [MODEL.md](../../MODEL.md). Read it once. This skill is only the worker's commands. The driver's commands, such as `moto ask`, `snooze` and `watch`, are not yours to run.

## Report

End a turn with `moto report done|question|blocked "<one line>"` when the task changed state and its owner must act. Put the PR URL in a `done` line. The report goes to the task's owner.

- `--to-driver` sends the report to the driver at once, whoever owns the task. Use it when the report asks the driver to act, such as creating a ticket, and when the user asks you to pass something on.
- `wrap` and `snooze` belong to the moto-wrap and moto-snooze skills. Use those skills, not a bare report.

## The user owns the task

A message without a `[driver]` or parent tag is the user typing, and the user now owns the task. moto records this itself. Until the user gives the task back:

- Answer and ask in the pane. Send no `question` or `blocked` report.
- A `done` reaches nobody. Report only with `--to-driver`, or through moto-wrap or moto-snooze.
- If a flow your brief names still runs, it pauses. Add one line to your first reply: Flow paused. Name the flow to resume. If no flow runs, never mention a flow or a pause.

When the user names a flow or says "back to the driver", run `moto handback "<flow>"`, then run that flow from where the work stands. After the hand-back, your reports reach the driver again.

## Phase boundaries

A phase boundary is where one kind of work ends and the next starts, such as implementation to shipping a PR. First write down what the next phase needs, such as the PR description. Then run `moto report phase "<next phase>"` and do what its reply says.

The reply tells you to carry on in the same turn, or to end your turn so moto hands you off to a fresh session. moto never hands off a task the user owns. The driver does not hear of phases.

## Spawn a worker

Spawn when part of the task belongs in another session: work in another repo, or a long test run you want out of your own context.

- **A helper you supervise**: plain `moto spawn`. You own it. Its `done`, `question` and `blocked` reports arrive in your pane after your turn ends, tagged as in `[widgets-fix done]`. Answer with `moto tell <agent> "<answer>"`, and close it with `moto close <agent>` when it is done. `moto handoff <agent> "<goal>"` moves an idle helper to a fresh session, with an optional brief on stdin. A helper's phase report reaches you as `[helper phase] <next phase>`: answer with `moto handoff` or `moto tell <helper> "carry on"`.
- **A separate task for the driver**: `moto spawn --to-driver`. The driver owns it. You cannot `moto tell` it.
- **A task the user owns from the start**, such as a review session: `moto spawn --user`. The driver hears only its wrap, snooze, `--to-driver` reports and closed pane.

```bash
moto spawn --repo widgets --worktree fix-login-redirect \
  --title "ABC-123 login redirect" <<'EOF'
Fix the login redirect loop in widgets. ...
EOF
```

- `--repo` (required): a repo name under `~/code`, or a path with a `/` or a leading `~`. It must be a git checkout.
- `--title` (required): one to three words separated by single spaces. Each word is lowercase letters, digits and hyphens. A ticket key such as `ABC-123` keeps its capitals. `"fix login"` passes, `"Fix login"` and `"fix: login"` fail.
- The brief goes on stdin and must not be empty. Write it for a session that knows nothing: the goal, the flow, where to look. moto adds the tag and the report rules.
- `--worktree <branch>` gives the worker its own linked worktree. Read the target repo's `AGENTS.md` first: leave it out when the repo commits on main. `--base <ref>` picks the new branch's start, by default the remote's default branch.
- `--name <agent>`: the Herdr agent name, `[a-z][a-z0-9_-]{0,31}`. Default: the branch name, or the repo name.
- `--model` and `--effort low|medium|high|xhigh|max`: set them only when the brief or the user asks. Defaults: `opus` and `medium`.

Spawn fails inside the sandbox (`SANDBOX=1`), outside Herdr, or on a bad flag. It can take a minute or more. If it ends with "Launch ... was not confirmed", run `moto list` before you retry, because the worker may already exist.

## See your workers

`moto list` shows every task with its live state, owner, PR and last report. Yours show "started by <you>" (you own and close them) or "requested by <you>" (the driver owns and closes them).
