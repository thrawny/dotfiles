# Nightly M1 fleet maintenance

The M1 checks OpenClaw and T3 on both the M1 and Obelisk nightly at **02:00
Europe/Stockholm**, within one minute. A launchd heartbeat runs every 60 seconds;
the Python runner decides which Stockholm night is due. Login/wake catches a
missed night once, without replaying every missed day. DST's repeated hour gets
one attempt. Installation suppresses the current night, so installing or checking
the schedule does not start an upgrade.

```sh
just install-nightly-app-update
just nightly-app-update-status
just nightly-app-update-pause
just nightly-app-update-resume
```

Installation builds and loads only the updater's Home Manager-defined launch
agent. It does not activate Home Manager or restart app services. Future normal
Home Manager activation manages the same label. The module is
`nix/home/darwin/nightly-app-update.nix`; M1 opts in through its host configuration.

The deterministic runner clones committed `origin/main` into its private state
directory, advances only `nix-openclaw` and `thrawny-pkgs`, checks exact published
official release tags (OpenClaw stable, T3 nightly), and rejects downgrades,
unknown versions, different cross-host versions and unrelated root input changes.
It compares against the installed fleet, runs `just check`, and builds only app
packages, with Linux builds originating on M1's Linux VM. Package publication may
lag upstream releases: this job consumes the supported Nix package inputs and
does not modify their upstream repositories or use app self-updaters.

Release-specific scoped rollout and supported migrations run through a separate
noninteractive `codex exec` agent using the M1's existing Codex login/model
configuration. This consumes Codex usage. Its reviewed instructions are
`scripts/nightly-app-update-task.md`. The runner caps this step at 90 minutes and
32 MiB of private output. No model inference or live rollout runs when installing
or inspecting the schedule. The agent receives broad execution access for the
explicitly authorized maintenance; its operational constraints are instructions,
not a filesystem/network security sandbox.

Attached/ready provider sessions, active turns, pending work, terminals, node
commands or auth operations defer disruptive maintenance. The agent rechecks
before each operation and uses OpenClaw's cooperative suspension with terminals
preserved. Unknown schemas/statuses fail closed. This conservative policy can
defer updates for an idle but still attached provider session; close it normally
or wait for it to end. No session is killed merely to make an update happen.

Only app-specific launchd definitions or persistent systemd runtime drop-ins may
change. Full system/HM generations, provider runtimes and unrelated settings stay
outside the nightly rollout. Preserve the current scoped OpenClaw config/include
overrides, credentials, per-agent auth order, group/approver identifiers, live
Codex runtime, Sonos PATH/policies/node capability, and Hermes retirement masks.
Release-required app/plugin/UI changes must be isolated and recorded. Gateway
and node compatibility must be verified together. See the
[gateway operations contract](../nix/hosts/obelisk/openclaw.md).

Backups must be consistent with the stopped service and include matching runtime,
config and state provenance. Obelisk backups stream directly to private M1
storage; the job must not duplicate multi-gigabyte state on its nearly full root
filesystem. It reserves at least 2 GiB on Obelisk after closure copy and 5 GiB on
M1 after the state backup. Missing headroom defers before stopping anything.
Retained updater evidence/backups are capped at 32 GiB; reaching the cap defers
new work rather than deleting backups. Existing backups and GC roots are never
deleted automatically. The job sends no Telegram messages or other notifications;
results are retained locally.

State and private logs live in `~/.local/state/nightly-app-update/` (0700):

- `latest.json` and `events.jsonl`: durable phase/outcome and night.
- `runs/<Stockholm-date>/`: exact candidate manifest, release evidence, source,
  agent result/log, mutation intents/results, health and backup/restore evidence.
- `paused`: prevents new maintenance; it does not interrupt work already running.
- `lock`: an advisory lock held for the whole attempt; overlapping launches exit.

Unchanged source clones and clones deferred before live maintenance are disposable;
the runner deletes only those owned candidate directories. Evidence and backups
remain. Temporary preparation records are separate from live rollout receipts.

After maintenance reports success, the runner independently checks that each
changed service process command contains the exact built runtime store prefix.
It checks the candidate's source SHA and exact lockfile contents before creating
one lockfile-only commit and a normal fast-forward push to main, using existing
executor Git auth. It never stages the user's working files, force-pushes, rebases
a deployed candidate, opens a PR, or merges another change.

An ordinary busy/no-change/pre-mutation failure gets another opportunity next
night. A timeout, partial rollout, uncertain migration or pending/rejected push
holds subsequent attempts for operator reconciliation. Never clear that hold
without inspecting the retained intent/results and actual live state. For a
pending push, verify the exact retained commit against origin; push that commit
only if still a valid fast-forward, or reconcile source explicitly. Do not replay
the live upgrade to retry a push. After reconciliation, archive the receipt and
set `latest.json` to the verified terminal outcome with its original night.

Health includes exact live versions, HTTP/service readiness, config/plugin health,
auth readiness, node pairing and Telegram connection status, without delivery.
A model smoke may use a tools-disabled, no-delivery turn. Actual human Telegram
approval/conversation is not proven by these checks. A binary rollback cannot
undo SQLite migration: restore matching state/config/runtime while stopped and
verify integrity/count preservation. If safe restore is uncertain, retain the
failed state and report the actual service state and manual recovery boundary.

The schedule binding is testable without upgrades; a complete live upgrade and
restore are deliberately not part of schedule installation. Future nightly
receipts provide the actual version-specific rollout/migration evidence.
