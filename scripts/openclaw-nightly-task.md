Run the nightly agent check for OpenClaw AND T3 on BOTH M1 and Obelisk, using
claudeAgent/claude-opus-5-5 with effort=medium. This visible T3 run owns the decision
and any rollout through verification. There is no independent recurring release
updater. Do not launch a parallel daily job or call the retired --scheduled runner.

Read AGENTS.md, nix/AGENTS.md, docs/nightly-app-updates.md,
scripts/nightly-app-update-task.md, nix/hosts/obelisk/openclaw.md,
docs/openclaw-node-mac.md and the installed fleet skill/inventory. Use the current
supported operations for the exact installed OpenClaw version. SSH defaults to
thrawny@obelisk with existing supported sudo/admin access. No Obelisk builds.

Inspect actual app versions/health, active work and retained evidence under
~/.local/state/nightly-app-update first. The legacy paused marker is permanent
retirement of the old automatic runner; KEEP it present. It does not pause this
native agent. Respect Jonas's current pause/stop instructions and native T3 task
settings. An active upgrade/maintenance owner means avoid conflicting work and
never interrupt it. Preserve uncertain/pending-push/migration no-replay fences:
read-only assessment may continue, but do not guess or replay held mutations.
Keep private evidence directories0700/files0600 and never retain raw credentials,
auth profiles, tokens or private channel/approver identifiers.

For EACH of M1/OpenClaw, Obelisk/OpenClaw, M1/T3 and Obelisk/T3, inspect supported
available releases, official release notes/migration requirements and relevant
known issues. Record source links/timestamps, installed/candidate versions and a
reasoned SKIP, DEFER or UPDATE decision. A newer release alone is not a reason to
update; weigh fixes, compatibility, regressions, current health and safe capacity.
No version change or a deferred update must still get current health diagnostics.
For T3 inspect actual service/HTTP readiness, config/provider/state binding and
bounded relevant T3/service logs; no unrelated application logs belong here.

Run ONE bounded read-only OpenClaw pass with
`just nightly-app-update-diagnose` from the root checkout. This invokes the
immutable on-demand helper installed at
~/.local/state/nightly-app-update/executor/bin/nightly-app-update --diagnose.
Verify its binding to the intended source. The retired launchd job must stay
absent/disabled. If the helper is unavailable, report the blocker rather than
reviving the legacy updater or treating old results as a current pass.
Read diagnostics/manual-latest.json, verifying its timestamp and helper identity.
Lock contention means no diagnostic ran; findings exit1 does not mean transport
failure or healthy status. The helper inspects the actual gateway runtime/env,
config validation, supported READ-ONLY doctor --lint --json, plugin/channel health,
UI HTTP, nodes, EACH agent's EFFECTIVE selected auth and expiry, and each memory
index's identity/provider/dirty/FTS state. It makes no model call or chat delivery.
Missing/unsupported/failed checks and timeouts remain explicit failures. Inspect
bounded relevant OpenClaw/service logs when useful; repeated messages are not
unique incidents. No unrelated application logs or systems belong in this run.

Own the chosen update/maintenance; use scripts/nightly-app-update-task.md as the
rollout safety contract, not as a separate unattended executor. Read-only candidate
preparation/build helpers may be used after the release decision. Apply scoped
source changes with repository checks and permitted direct-main commit/push,
preserving unrelated work and recording exact source/runtime identities.

Interpret findings before changing anything. Never use bare Doctor or
doctor --non-interactive for routine checks, or copy credentials. Do not blindly
run --fix, refresh auth, index, probe a model or restart just because a check warns;
justified supported maintenance must follow the safety contract below.
Routine supported maintenance is authorized only when current evidence justifies
it and affected sessions are idle/cooperatively suspended with terminals preserved.
Recheck active/unknown sessions immediately before every disruptive operation.
Use supported cooperative suspension; never kill a session to obtain idleness.
For any justified migration follow the full matching stopped-service backup,
runtime/config/state provenance and postcheck contract in the operations docs and
release-upgrade task. Stream backups to M1, measure fresh disk headroom and retain
existing provenance. Never duplicate multi-GB state on Obelisk or delete backups.
The schema24-to25 migration already happened; historical logs do not authorize
replaying it. Record mutation intent before execution and actual result after;
an uncertain result holds further mutations for reconciliation.

Preserve live scoped config/include/env overrides, keyword memory provider none,
per-agent selected auth/order, private groups/approvers, the pinned live Codex
runtime, M1 pairing and Sonos policies/capabilities, and Hermes retirement masks.
No unsolicited Telegram/other messages, test deliveries, paid model smokes, app
self-updaters, destructive cleanup or full system/Home Manager activation.
For M1 T3 self-update, your own session is an active blocker: DEFER unless an
existing independent supervisor explicitly accepts ownership, survives restart and
will verify it. Present that concrete handoff requirement; do not create a new
supervisor, bypass session gates or restart your own unowned worker.

If you change anything, stay with it: check exact installed version/config/store
binding, appropriate service/node/channel/auth/index health, and post-start logs
and restart/failure evidence. Observe stability for at least two minutes AFTER
initial readiness (longer if required by the release), then repeat checks. A
launch/deploy return is not success. On failure restore safely with the matching
backup or report the concrete uncertain state/blocker without abandoning it.
Never leave started work unowned; any handoff requires explicit acceptance by a
surviving existing owner.

Summarize actual checks, current findings, exact maintenance performed (or none),
postcheck results, evidence paths and remaining blockers in this T3 thread. Report
the night in Europe/Stockholm, runtime/source identity and whether the diagnostic
completed. Separate selected-auth validity from Codex runtime-route readiness,
and optional offline nodes from the paired M1. Never claim a deferred upgrade
updated anything or that a scheduled future run has succeeded. Do not wait for a
reply without purpose; defer safely when procedure, capacity or idleness is missing.
Ask Jonas only when a concrete missing decision falls outside existing authority.
