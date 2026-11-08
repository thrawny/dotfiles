This is the rollout safety contract for the native M1 T3 maintenance agent.
The legacy unattended runner is retired. You own release assessment, the decision,
execution, observation and final result; no caller has already validated a candidate.
Validate exact official release versions and supported package pins, limit source
changes to the intended app inputs, run repository checks, and build only affected
app packages off-host before a rollout. Keep per-target evidence and rollback paths.
Read current diagnostics, checking their timestamp; stale findings are not health.
Routine checks use supported doctor --lint --json, never bare Doctor or
--non-interactive. A warning is not permission for a blind repair.

Jonas explicitly authorizes nightly OpenClaw and T3 maintenance on BOTH M1 and
Obelisk, supported OpenClaw database migrations, and the agent's scoped dotfiles
commit/push. This is an agent-owned job: missing authority, access, disk headroom,
compatibility, an undocumented operation, or active work means defer with a durable
reason. Ask Jonas only for a concrete missing decision outside existing authority.
Never leave a started rollout unowned while waiting. Never send Telegram or other messages,
including test approval requests. No playback actions, credential copying, logins,
destructive resets/deletes, unrelated upgrades, or host generation activation.

Read repository AGENTS.md, nix/AGENTS.md, docs/t3code-mac.md,
docs/openclaw-node-mac.md, nix/hosts/obelisk/openclaw.md and the installed fleet
skill/inventory. Consult current official release/update/migration contracts for
the EXACT versions. Do not infer compatibility from a version number alone.
Use executor-owned existing auth; never copy credentials or print secrets.

Before any change:

1. Choose a fresh private evidence_directory beneath
   ~/.local/state/nightly-app-update/runs/agent-<UTC-timestamp>; never reuse a
   historical rollout directory. In its plan define the explicit approved target
   list (M1/OpenClaw, Obelisk/OpenClaw, M1/T3, Obelisk/T3 as applicable), selected
   versions and built runtime/config paths yourself; no caller injects these values.
   Record the plan with UTC timestamps, source SHA,
   old/new versions, actual process commands, launchd/systemd definitions, current
   system/HM generation, scoped overrides, GC roots, and rollback boundary. Never
   expose credential values. Record every mutating command's intent BEFORE running
   it and its result AFTER. If a prior intent lacks a result, stop uncertain; do
   not replay it. An unexpected parent death or timeout needs operator reconciliation.
2. Respect current operator pause/stop instructions for this native job. The old
   state's paused marker permanently retires the legacy automatic runner; leave
   it present. Preserve all historical uncertain/pending-push/no-replay receipts.
   Check origin/main is still the validated source SHA; concurrent changes defer.
3. Check live work immediately before EACH affected service operation. For T3,
   inspect real read-only statev2 SQLite orchestration run/provider session tables,
   pending work/requests, open terminals, descendants and independent agents/auth
   commands. Live attached/ready provider sessions, nonterminal runs, background
   commands, unknown execution or active login defer. Reconcile aggregate rows with
   fresh supported thread projections and native process evidence: a ready row is
   stale only when its run is terminal, the supported projection has no attached
   provider or unresolved requests, and no matching native execution remains.
   An unstarted historical fork with no target run is retained context, not an
   executing owner; preserve it without replay. Conflicting, missing or failed
   evidence defers. Recheck for late/new input immediately before stopping.
   Never edit/delete rows or repeat a rejected detach to manufacture idleness.
   Never rely only on PID existence or automatic restart continuation. No silent
   session termination. This native agent is itself an active M1 T3 session: never
   exclude it from the M1 T3 restart gate. Defer that self-update unless an existing
   independent supervisor has explicitly accepted ownership, can survive restart
   and will verify the actual result. Do not invent a dispatcher or assume automatic
   continuation. Scope activity checks to affected services, so a live M1 T3 worker
   alone does not prohibit a safe remote OpenClaw change. OpenClaw MUST use supported
   cooperative suspension with terminalPolicy preserve and drain=false. Only a
   ready lease with zero blockers/active work permits stopping; capture lease ID
   and expiry privately, stop before expiry, resume if abandoned. Busy means defer
   to next night. Do not activate the node while node commands/approvals are active.
4. Measure available bytes on both hosts, state sizes and missing candidate closure
   bytes BEFORE copying. Reserve at least 2 GiB free on Obelisk after copy and UI
   materialization. Never initiate builds on Obelisk; all Linux app/system builds
   originate on M1 using its Linux VM by default. If an emulated runtime/install
   check fails, retain its exact derivation/log and use an existing reachable,
   inventory-approved native Linux host of the matching platform. Check its load
   and capacity; transfer the unchanged derivation with `nix copy --derivation`,
   build it there with every check enabled, then copy the output back to M1 over
   authenticated SSH. Verify matching deriver and NAR hash before rollout. An
   unsigned own-build import may use `nix copy --no-check-sigs` only from that
   verified host; this does not waive runtime checks. Preserve failures and report
   the actual builder. No permanent builder registration, new host infrastructure
   or package workaround is required. No full system build or switch is needed.
   Never make a large duplicate backup on Obelisk's root filesystem. Stream any
   stopped-service Obelisk backup over SSH directly to private M1 storage beneath
   evidence_directory. Check M1 headroom for the uncompressed state PLUS 5 GiB
   reserve. Hold if projected retained updater evidence/backups would exceed
   32 GiB after this backup. Do not
   delete any existing backup, GC root, generation, log, user file or old release.

Scoped rollout, only for the approved targets explicitly recorded in your plan:

- Preserve the active service definition, environment, owner, HOME, working
  directory, PATH tools/providers, ports, Tailscale mappings and security policy.
  On M1 preserve Sonos package PATH priority and the node's advertised
  system.run.prepare, system.run, system.which, system.execApprovals.get commands.
  Do not activate a complete Home Manager generation: install only the affected
  launch agent/runtime, with a retained original and GC roots for old/new runtimes.
  Preserve the launch wrapper's existing credential-loading behavior. The running
  command MUST include the exact built package store prefix for verification.
- On Obelisk use root SSH to import ONLY the needed already-built closures and
  apply ONLY app-specific persistent systemd drop-ins. Never build or switch a
  NixOS generation there. Retain original drop-ins/service definitions and old/new
  runtime/config GC roots. Preserve the live OPENCLAW_CONFIG_PATH and
  OPENCLAW_INCLUDE_ROOTS override mechanism, private includes/env identifiers,
  live pinned Codex command, auth profiles and per-agent auth order, routes,
  verified group/approvers, node identity/pairing, Sonos policies, and workspace
  guidance. Preserve Hermes durable system.control masks and absence of its Serve
  endpoint. Do not reconcile scoped overrides to an unrelated system generation.
- OpenClaw's gateway package bundles the Codex runtime plugin. Its separately
  packaged official Discord plugin must match the new first-party package set.
  Build any required matching plugin/config artifacts off-host from these exact
  locked inputs, never install runtime plugins. Derive a new immutable scoped
  config from the LIVE scoped config, changing only release-required app/plugin/UI
  paths/schema fields. Keep Codex and every unrelated setting unchanged; compare
  normalized before/after JSON and retain the diff privately. Preserve private
  include roots when adding the new config root. Validate before activation. If
  release-required config changes cannot be isolated confidently, defer.
- Before stopping, record preflight/integrity/count baselines. With the service
  stopped, capture a consistent complete state/credentials/workspace backup,
  preserving symlinks without following them, service metadata and config refs.
  Verify archive integrity and exact restore procedure BEFORE replacing runtime.
  Protect all backups/evidence (directories0700/files0600). Never print auth data.
  If a full stopped stream exceeds the admission window, measure traversal,
  source-read and compression costs while services run. GNU tar's
  `--listed-incremental` supports a full live pre-stage and live catch-up followed
  by a stopped final delta over the SAME complete scope. Keep each archive and
  its matching snapshot privately, record the exact parent chain and timestamps,
  and keep only small snapshot metadata on the source; stream archive data to M1.
  Preserve
  numeric ownership, modes, symlinks, hardlinks, ACLs, xattrs and sparse files.
  Do not reset source timestamps or the clock between captures. Live captures,
  partial archives and incomplete chains are not recovery backups. Record actual
  tar/compressor exits and changed-file warnings; missing/unreadable data or an
  uncertain capture must be reconciled before using its snapshot as a parent.
  Rehearse the real catch-up duration before requesting another stopped window.
  While stopped, require a successful final delta and a separate full capture of
  the app's database/WAL family, credentials and settings, so those files are
  demonstrably from one quiescent point. Verify each archive's complete read and
  integrity, chain identities and restored database integrity/counts against the
  stopped baseline before activation. Prove the tool's restore semantics with
  deletions, renames, timestamp-preserving writes and Linux metadata. GNU tar
  restores the full archive and each delta in order with
  `--listed-incremental=/dev/null`; apply the stopped critical-state capture last.
  Restore into an empty isolated tree, preserving failed/newer state, and account
  for restore capacity and the matching runtime/config boundary. A live pre-stage
  becomes a usable backup only with that verified stopped chain. Set an abort
  deadline that leaves time to restart and observe the old service without
  changing runtime when capture or verification cannot finish.
- For required OpenClaw migrations use documented Doctor mechanisms as the owning
  user, stopped gateway, writable PRIVATE config copy, same state/workspace and
  credential env, Nix mode disabled ONLY for that operation. Retain config/logs
  privately; translate required config changes to immutable scoped config.
  Do not migrate simply because a previous job once required it. Schema25 migration
  already completed once on 2026-10-30. No replay of a settled/uncertain migration.
  Check actual SQLite integrity and data/count preservation after migration;
  an exit code alone is insufficient. Reconcile documented Doctor side effects.
- Coordinate OpenClaw gateway/node version compatibility, updating the pair within
  this maintenance window, and verify paired/connected after both. Do not leave
  incompatible roles running. A client-protocol incompatibility or unsupported
  staged transition means defer before any mutation.
- Bound initial startup/readiness to 120 seconds per service, with an explicit
  release-documented larger migration deadline only if recorded BEFORE mutation.
  This startup deadline is separate from the post-readiness stability window below.
  T3 needs the exact live version/command, healthy local HTTP, intact state and
  provider configuration; listener/reconnect alone does not prove successful
  startup. OpenClaw needs config validity, gateway health, no active plugin errors,
  UI HTTP, auth selection/expiry readiness, M1 paired/connected, and Telegram
  configured/running/connected without sending. A no-delivery shared model smoke
  may be used ONLY through the documented agent API with tools disabled and no
  delivery; preserve its dedicated workspace and Codex harness/Sol route. It can
  consume subscription tokens. Never claim a real human Telegram test occurred.
- On failure stop the affected new service safely, restore original runtime AND
  matching state/config from the verified backup where necessary, then verify old
  health. Binary-only rollback does not reverse SQLite migrations. Do not overwrite
  newer writes, replay uncertain commands, or delete failed state. If safe matching
  restore cannot be proven, leave a durable uncertain receipt with exact paths,
  actual service state and operator recovery steps; do not claim rollback success.

After every rollout, retain ownership through a bounded observation window chosen
BEFORE mutation (at least two minutes after initial readiness, longer when the
release contract requires it). Inspect post-start logs, restart/failure counts and
service/node/channel/auth/index health appropriate to the changed component.
Repeat readiness checks at the end and compare exact running version/config/store
binding with the chosen candidate. A launch/deploy return, listener or reconnect
alone is not success. If observation fails, handle/restore safely under the matching
backup contract above or record the concrete uncertain state and recovery blocker.
Do not finish, detach or hand off a started rollout without an explicitly accepted
surviving owner and verification responsibility.

Summarize per-target skip/defer/update decisions, evidence and actual final state
in this T3 thread. Updated requires exact chosen runtime/config, health/state
checks and stable observation passed. Deferred means no live mutation on that
target; any partial mutation or rollback must be reported honestly and retained
for reconciliation. Preserve mutation intent/results and never replay to retry a
push. Before a scoped direct-main commit/push, verify exact running bindings,
source/lockfile scope and repo gates; never stage unrelated user work, force-push,
or claim source delivery if rejected. If origin advanced, reconcile explicitly
without replaying live work. Questions are for concrete missing decisions only.
