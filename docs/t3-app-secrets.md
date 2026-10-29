# App credentials in T3 worktrees

A factory project can use a different clone from your interactive app checkout.
Worktrees share Git history, but neither Git nor T3 copies ignored environment
files from another clone. Inspect the project's `workspaceRoot` and run
`git rev-parse --git-common-dir` in the worktree before provisioning anything.

For thechalkboard, the committed `.envrc` loads `.env`, then the **primary
checkout's** `.env.local` and `.secrets`, then worktree-local overrides. Find that
primary checkout with `git worktree list --porcelain` (the first entry).
On the M1, the factory clone is `~/code/factory-repos/thechalkboard`, separate
from `~/code/thechalkboard`. Provision the factory clone, not each worktree.

Nix already enables direnv and trusts `~/.t3/worktrees` on the M1. The factory
project needs no T3 worktree-create script. Commands without an interactive
shell hook should use `direnv exec <worktree> <command>`. Existing shells reload
on the next direnv evaluation; existing processes retain their old environment.
No T3 restart is needed. New worktrees inherit the primary checkout's credentials
when their committed `.envrc` is evaluated. Worktree-local overrides still win.

## Provisioning

Use only credentials already authorized for this app and executor account.
For backend evidence access, the M1 factory clone uses `CONVEX_DEPLOY_KEY` and
`WORKER_SECRET` in its ignored `.secrets`, owned by the executor user with mode
`0600`. The Convex key grants production deployment access as well as reads;
keep actual investigation commands read-only unless deployment is authorized.
The worker secret permits app worker authentication. Other workflows may need
separately authorized credentials; this setup does not provision them.

Do not copy whole environment files. In particular, controller credentials,
executor/provider login state and PostHog personal authentication must never
be transferred to a worker. Keep app credentials out of Nix, Git, logs, notes,
prompts and command arguments. If an app credential is unavailable, ask the
driver to invoke the private secret tool; never request its value in chat.

When provisioning another clone, evaluate the authorized source checkout's
app environment privately, select only the approved names, and create the
primary checkout's ignored `.secrets` exclusively with mode `0600`. Refuse to
overwrite an existing file; reconcile it privately first. Verify ownership,
permissions and `git check-ignore .secrets`. Retain a single primary file so
rotation applies to existing and future worktrees on their next direnv reload.
Do not link a worker to an operator's broad environment file.

## Verification

Clear inherited app credentials before each probe so the check proves direnv
loaded the primary checkout's file. Before each probe, confirm that
`git rev-parse --git-common-dir` resolves to the factory clone's `.git`. Check
both the existing incident worktree (the `factory-66326365376435642d...`
worktree for incident `f2ce7d5d-4dd8-4e58-a355-4afecc23804b`) and a fresh
detached worktree from that clone. Other repair worktrees may belong to the
interactive clone and do not verify factory provisioning. Run an authenticated Convex
`run --prod --inline-query` that reads only the intended incident job and returns
booleans for access and existence. Capture subprocess output privately and
report only the boolean outcome; do not print raw job contents or CLI errors.
Remove the temporary worktree after the probe.

A successful read verifies credential provisioning, not an incident repair.
It neither resumes a stopped investigation nor authorizes an extraction replay.
