---
name: moto
description: How a worker session runs moto. Load before any `moto` command, such as spawning a worker, reporting to the driver, or telling, listing or closing workers you started.
---

# moto for workers

A driver session started you with `moto spawn`. moto tracks each worker as a task, with a Herdr agent name, and carries reports between workers and the driver. Everything below is the worker's side. The driver's commands, such as `moto ask`, `snooze` and `watch`, are not yours to run.

## Spawn a worker

Spawn when part of the task belongs in another session: work in another repo, or a long test run you want out of your own context.

- **A helper you supervise**: plain `moto spawn`. Its `done`, `question` and `blocked` reports arrive in your pane after your turn ends, tagged as in `[widgets-fix done]`. Answer a question with `moto tell <agent> "<answer>"`. When it is done, close it with `moto close <agent>`. To move an idle helper to a fresh session in the same pane, run `moto handoff <agent> "<goal>"`, with a brief for the new session on stdin if it needs one.
- **A separate task for the driver**: `moto spawn --to-driver`, for example research that splits into implementation tasks. The driver watches it and takes its reports. You cannot `moto tell` it. Pass anything on with `moto report`.

### The call

```bash
moto spawn --repo widgets --worktree fix-login-redirect \
  --title "ABC-123 login redirect" <<'EOF'
Fix the login redirect loop in widgets. ...
EOF
```

- `--repo` (required): a repo name under `~/code`, or a path (anything with a `/` or a leading `~`). It must be a git checkout.
- `--title` (required): one to three words separated by single spaces. Each word is lowercase letters, digits and hyphens, starting with a letter or digit. A ticket key such as `ABC-123` keeps its capitals. No underscores, colons or other punctuation. `"fix login"` passes, `"Fix login"` and `"fix: login"` fail.
- The brief goes on stdin, and an empty brief fails. Write it for a session that knows nothing: the goal, where to look, what done means. moto adds the `[driver]` or `[<you>]` tag and the report rules, so leave those out.
- `--worktree <branch>`: see below. `--base <ref>` picks the start of a new worktree's branch. It defaults to the remote's default branch, fetched, and is ignored when the branch's worktree already exists.
- `--name <agent>`: the Herdr agent name, matching `[a-z][a-z0-9_-]{0,31}`. It defaults to the branch name, or the repo name without `--worktree`.
- `--model <alias or full name>` and `--effort low|medium|high|xhigh|max`: set them only when the brief or the user asks. A flag left out defaults to `opus` and `medium`.

The call fails when stdin is empty, `--repo` or `--title` is missing or invalid, the repo is not found, or the session runs inside the sandbox (`SANDBOX=1`) or outside Herdr. Spawn waits for the worktree and the new session, so it can take a minute or more. If it ends with "Launch ... was not confirmed", run `moto list` before you retry, because the worker may already exist.

### Worktree or main checkout

Read the target repo's own `AGENTS.md` or `CLAUDE.md` before you choose:

- If the repo works on branches and pull requests, pass `--worktree <branch>`, so the worker gets its own linked worktree.
- If the repo's instructions say to commit on main, leave `--worktree` out. The worker opens in a new tab of the main checkout.

## Report

End a turn with `moto report done|question|blocked "<one line>"` when the task is finished, needs an answer only the user has, or is blocked. Put the PR URL in a `done` line. The report goes to whoever started you: the driver, or the worker that spawned you.

While the user typed in your pane in the last 30 minutes (a setting), you are with the user. The driver leaves you alone and moto types nothing into your pane: no handoff, no carry on, no `/compact`. The window never makes you stop.

When you need an answer only the user has, ask the user in the pane and also run `moto report question "<one line>"`, so the sidebar shows it. Do the same for `blocked`. moto settles the report on the user's next prompt in the pane, and a report you make after that prompt stays open until the one after it. While you are with the user, `question` and `blocked` reports reach only the sidebar, never the driver. A `done` report reaches the driver without the flag. Once 30 minutes pass with no new prompt from the user, the driver takes you back. It hears from moto only if you need action: your last report is an unsettled `question` or `blocked`, your last turn ended without a report, or you wait at an approval or question prompt.

Add `--to-driver` whenever the report asks the driver to act, such as creating a ticket or starting a worker, and whenever the user asks you to pass something on. With it, the report reaches the driver at once, even while you are with the user or another worker started you.

### Takeover

Any message from the user in your pane, one with no `[driver]` or parent tag, pauses the flow your brief names. Follow the user until the user names a flow again, then restart that flow from where the work stands. In your first reply after the takeover, say so in one line, such as: Flow paused. Name the flow to resume.

### Phase boundaries

A phase boundary is where one kind of work ends and the next starts: grilling to implementation, implementation to shipping a PR, shipping to babysitting it. At a boundary, first write down what the next phase needs, such as the ticket or the PR description. Then run `moto report phase "<next phase>"` and do what its reply says.

moto reads your context size when you report. Under the handoff limit, or when it cannot read the size, the reply tells you to carry on with the next phase in the same turn. Over the limit, with the user not in your pane, the reply tells you to end your turn, and the watch hands you off to a fresh session with the next phase as its goal. Over the limit, with the user in your pane, moto does not hand you off. The reply tells you to carry on and to tell the user in one line that `/handoff` would start a fresh session. The driver hears of the phase once in every case.

A helper's phase report reaches you as `[helper phase] <next phase>`. Answer with `moto handoff <helper> "<next phase>"` for a fresh session, or `moto tell <helper> "carry on"`.

The report kinds `wrap` and `snooze` belong to the moto-wrap and moto-snooze skills. Use those skills, not a bare report.

## See your workers

`moto list` shows every task with its live state, PR and last report. Yours show "started by <you>" (you supervise and close them) or "requested by <you>" (the driver watches and closes them).
