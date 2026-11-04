Run nightly OpenClaw diagnosis and justified routine maintenance from M1, using
codex/gpt-6.1-sol with reasoningEffort=high. This native T3 thread is the report.
This prompt owns daily diagnostics; the independent 02:00 release upgrader still
owns OpenClaw AND T3 upgrades on BOTH M1 and Obelisk. Do not duplicate its rollout,
change schedules, start a parallel worker, or restart your own T3 executor.

Read AGENTS.md, nix/AGENTS.md, docs/nightly-app-updates.md,
scripts/nightly-app-update-task.md, nix/hosts/obelisk/openclaw.md,
docs/openclaw-node-mac.md and the installed fleet skill/inventory. Use the current
supported operations for the exact installed OpenClaw version. SSH defaults to
thrawny@obelisk with existing supported sudo/admin access. No Obelisk builds.

Inspect ~/.local/state/nightly-app-update/latest.json, dispatch.json, pause/install
markers and actual updater activity first. Preserve original receipts and all
uncertain/pending-push/migration no-replay fences. If an upgrade or another nightly
maintenance run is active, avoid conflicting work; never interrupt it or bypass
its lock. A pause or incomplete installation means report deferred. An uncertain
upgrade does not prohibit read-only diagnosis, but prohibits guessing/replaying
the upgrade. Keep private evidence directories0700/files0600; never retain raw
credentials, tokens, auth profiles or private channel/approver identifiers.

Run ONE bounded read-only pass through the installed updater source's supported
`--diagnose --state-dir "$HOME/.local/state/nightly-app-update"` CLI. Resolve its
immutable source and Python/environment from the loaded existing
org.nix-community.home.nightly-app-update launch agent and wrapper; verify that
openclaw-diagnostics.py sits beside it. Do not invoke the wrapper itself to
diagnose: that wrapper runs --scheduled (release upgrades). If the binding cannot
be proved, report the blocker rather than silently using an unrelated source.
Read diagnostics/manual-latest.json, verifying its timestamp and helper identity.
Lock contention means no diagnostic ran; findings exit1 does not mean transport
failure or healthy status. The helper inspects the actual gateway runtime/env,
config validation, supported READ-ONLY doctor --lint --json, plugin/channel health,
UI HTTP, nodes, EACH agent's EFFECTIVE selected auth and expiry, and each memory
index's identity/provider/dirty/FTS state. It makes no model call or chat delivery.
Missing/unsupported/failed checks and timeouts remain explicit failures. Inspect
bounded relevant OpenClaw/service logs when useful; repeated messages are not
unique incidents. No unrelated application logs or systems belong in this run.

Interpret findings before changing anything. No blind daily --fix, bare Doctor,
doctor --non-interactive, auth copying/refresh, indexing, model smoke or restart.
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
Version upgrades belong to the independent guarded release updater. If its
attached-session gate prevents an update, report that limitation; do not weaken it.

Summarize actual checks, current findings, exact maintenance performed (or none),
postcheck results, evidence paths and remaining blockers in this T3 thread. Report
the night in Europe/Stockholm, runtime/source identity and whether the diagnostic
completed. Separate selected-auth validity from Codex runtime-route readiness,
and optional offline nodes from the paired M1. Never claim a deferred upgrade
updated anything or that a scheduled future run has succeeded. Do not wait for a
reply; defer safely when authority, supported procedure or idleness is missing.
