# Nightly fleet maintenance by the M1 T3 agent

One native T3 Code scheduled task runs at **04:00 Europe/Stockholm** on M1 with
`codex/gpt-6.1-sol`, explicitly `reasoningEffort=high`. Its visible T3 thread owns
assessment, decisions, any rollout and the final report for **OpenClaw and T3 on
both M1 and Obelisk**. It checks current health, available supported releases,
release notes, migrations and relevant known issues, then records a reasoned
skip/defer/update decision for each app/host. A newer version does not by itself
trigger an update. Diagnostics still run on no-change and deferred-update nights.

The authoritative prompt source is `scripts/openclaw-nightly-task.md`; the stored
native task contains a copy, so update that same task through supported T3 tools
when changing the prompt. Do not create another schedule. Native fixed-time
scheduling uses the server's local timezone. M1 must remain logged in, awake and
running T3; runs missed by more than ten minutes are skipped by the current native
scheduler. Recheck the binding if the local timezone changes. Installing a task
proves its binding, not the success of a future nightly execution.

## Agent decisions and rollout ownership

The agent uses `scripts/nightly-app-update-task.md` as its rollout safety contract.
It may perform justified supported maintenance and updates within existing
operator authority, with repository checks and scoped direct-main commit/push.
It records release evidence, source/runtime/config identities, mutation intent,
results, matching backup provenance and the recovery boundary privately. It asks
for input only when a concrete missing decision falls outside that authority.

The agent stays responsible after deployment: it checks exact installed versions
and config/store bindings, appropriate service/node/channel/auth/index health,
post-start logs and failure/restart evidence. It observes at least two minutes
of stability after initial readiness (longer when release requirements demand),
then repeats health checks. A deploy return, listener or reconnect is insufficient.
It restores safely with matching state/config/runtime or reports the concrete
uncertain state and blocker; started rollouts cannot be abandoned or silently
handed off. A handoff requires explicit acceptance by an existing surviving owner.

M1 T3 self-update would stop this agent's executor. It therefore **defers** unless
an existing independent supervisor explicitly accepts the rollout, survives the
restart and can verify it. There is no new dispatcher or babysitter service.
Live/unknown affected sessions, pending execution or auth operations defer disruptive
changes. The rollout contract explains how to reconcile stale aggregate provider
rows and unstarted historical context without replaying or deleting them.
OpenClaw uses supported cooperative suspension with terminals preserved;
never kill sessions or weaken idle gates to make an update happen.

Build Linux app packages from M1 using its Linux VM; never build on Obelisk.
For emulation failures, the rollout contract permits the unchanged derivation on
an existing approved native Linux host, with runtime checks and closure identity
verification preserved.
Backups must match the stopped service's runtime/config/state, preserve symlinks,
and be verified before replacement. Stream Obelisk backups to private M1 storage,
not another multi-gigabyte copy on its root filesystem. Measure current headroom;
retain at least 2 GiB on Obelisk after closure/UI copy and 5 GiB on M1 after backup.
Retained maintenance evidence/backups have a 32 GiB admission cap; defer rather
than deleting existing backups or GC roots. Preserve scoped config/include/env,
per-agent auth order/selection, private groups/approvers, pinned live Codex,
keyword memory, M1 pairing/Sonos policies and Hermes retirement masks. No full
system/Home Manager activation, app self-updaters or unsolicited Telegram sends.
See the [gateway operations contract](../nix/hosts/obelisk/openclaw.md).

## On-demand helpers and retired updater

```sh
just install-nightly-app-update
just nightly-app-update-diagnose
just prepare-nightly-app-update
just nightly-app-update-status
```

The installer now installs only immutable **on-demand helpers** and disables,
unloads and archives the exact old launchd label
`org.nix-community.home.nightly-app-update`. Nix declares that agent disabled and
publishes the helper package instead, so normal activation cannot restore the old
02:00 automatic updater. No helper starts a daily agent or rollout at installation.
The command is rooted at `~/.local/state/nightly-app-update/executor`; the wrapper
accepts only `--diagnose`, `--prepare` and `--verify`. It rejects `--scheduled`.
No recurring release-trigger service remains. `nightly-app-update-resume` refuses
to revive it; pause/enable the native task through T3's supported settings/tools.

`--diagnose` is a bounded read-only OpenClaw check. It runs in the live gateway's
owner/environment and verifies actual runtime/env identity, config validation,
`doctor --lint --json`, plugin/channel health, UI, nodes, EACH agent's effective
selected auth/expiry and each memory index's identity/provider/dirty/FTS status.
Doctor has 120 seconds, other CLI checks 60 seconds and the remote pass eight
minutes in an owned transient unit. Exit1/findings is not a clean-health claim;
missing/unsupported output or timeouts remain failures. Auth selection validity
and Codex runtime readiness are separate results. No bare Doctor,
`--non-interactive`, blind `--fix`, auth copying/refresh, indexing, model smoke,
upgrade, restart or chat delivery occurs in the diagnostic helper itself.

`--prepare` remains an on-demand candidate validation/build helper; inspect it
before use and run it only after an agent decision. It does not deploy. It checks
exact official release channels and versions, rejects downgrades/unknown versions,
unsupported cross-host combinations and unrelated input changes, runs `just check`
and builds affected app packages off-host. The agent independently interprets
release risk and owns any subsequent scoped rollout and source delivery. Other
packages sharing these input pins await separate normal activation.

Existing private state under `~/.local/state/nightly-app-update/` is preserved:
original `latest.json`, `events.jsonl`, `dispatch.json`, dated rollout evidence,
backups and all GC roots. `paused` permanently fences the retired automatic runner;
it is not a pause instruction for the native T3 agent. Do not remove it. Historical
install markers/deadlines and receipts are evidence, not a future release schedule.
`--verify` displays that legacy state only; T3 owns the actual next-run binding.
`retired-launchd/` holds the original plist; `executor` roots on-demand tools.
The existing advisory `lock` protects helper attempts/retirement. Lock contention
means no diagnostic ran, not success. Diagnostic `manual-*.json`/`manual-latest.json`
contain sanitized findings, exact runtime/config path and helper digest; no raw
tokens/profiles/private channel IDs. The T3 agent records its decisions and actual
outcomes in private evidence and its thread.

Uncertain mutations/migrations or pending/rejected pushes require explicit
reconciliation against retained intents/results and actual live state. Never replay
an upgrade to retry a push. A binary rollback does not undo a state migration;
restore matching state/config/runtime while stopped and verify integrity and data
preservation. Never infer a new migration from repeated historical log messages.
