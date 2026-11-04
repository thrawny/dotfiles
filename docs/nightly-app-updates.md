# Nightly M1 OpenClaw maintenance and fleet upgrades

The independent release upgrader checks OpenClaw and T3 on both the M1 and
Obelisk nightly at **02:00 Europe/Stockholm**, within one minute. A launchd heartbeat runs every 60 seconds;
the Python runner decides which Stockholm night is due. Login/wake catches a
missed night once, without replaying every missed day. DST's repeated hour gets
one attempt. Installation suppresses the current night, so installing or checking
the schedule does not start an upgrade.

```sh
just install-nightly-app-update
just nightly-app-update-status
just nightly-app-update-diagnose
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
These inputs also contain packages used elsewhere in dotfiles. Their source pins
advance together, but the nightly rollout applies only these app runtimes; other
packages remain pending a separately authorized normal generation activation.

Release-specific scoped rollout and supported migrations run through a separate
noninteractive `codex exec` agent using the M1's existing Codex login/model
configuration, explicitly selecting `gpt-6.1-sol` with high reasoning. This
consumes Codex usage. Its instructions are
`scripts/nightly-app-update-task.md`. The runner caps this step at 90 minutes and
32 MiB of private output. No model inference or live rollout runs when installing
or inspecting the schedule. The agent receives broad execution access for the
explicitly authorized maintenance; its operational constraints are instructions,
not a filesystem/network security sandbox.

A separate **native T3 Code scheduled task on M1 at 04:00 local time** owns the
nightly OpenClaw diagnostic/maintenance run. M1's local timezone is
Europe/Stockholm; native fixed-time schedules use the server's local timezone.
The stored task explicitly selects `codex/gpt-6.1-sol` with
`reasoningEffort=high` and opens its work in T3. Its prompt is
`scripts/openclaw-nightly-task.md`. It runs the diagnostic helper, interprets current
evidence and performs supported routine maintenance only when justified and safe.
It consumes Codex usage even on no-version-change days. The release heartbeat
performs no daily diagnostic pass, so there is exactly one diagnostic schedule.
The two-hour separation avoids starting our T3 worker alongside the 02:00 upgrade
idle check; either worker must still respect an actual overlapping attempt.

Native scheduling requires the M1 logged in, awake and T3 running. The current
native fixed-time scheduler skips runs missed by more than ten minutes, rather
than catching them up on wake. Its next-run time follows the M1's local timezone;
recheck the binding after timezone changes. Installation verifies the schedule,
not future maintenance success. Its stored prompt is copied from the source file when configured; update the
stored task through the supported T3 tools when changing that prompt.
Inspect it with T3's scheduled-task tools/settings;
do not create another launchd or Moto diagnostic job.

`just nightly-app-update-diagnose` runs only a bounded read-only pass immediately,
without consuming a scheduled night or starting an upgrade. The native T3 worker
uses the same `--diagnose` entrypoint from the installed immutable source bundle.
The release-upgrade scheduler remains independent so it can safely update T3 when
no T3 sessions are attached; the nightly T3 worker never restarts its own executor
or bypasses the upgrade idle gate. Both-app/both-host upgrades remain its duty.

The checks run as the live gateway owner with its actual service environment and
scoped config override. They inspect config validity, `doctor --lint --json`,
plugins/channels, every configured agent's **effective** auth selection and expiry,
and each memory index's identity, provider, dirty state and FTS availability.
The running process command must match the loaded runtime, and a digest compares
the diagnostic environment with the running gateway's service/config/credential
environment before checks. A pending runtime or environment replacement fails
closed rather than diagnosing it as the live gateway. No credential values enter
the receipt or transient unit arguments.
The installed lint exit code is retained: JSON alone does not establish health.
Warnings, missing fields, unsupported schemas, timeouts and model-runtime readiness
failures remain findings/failures; a healthy unselected credential is insufficient.
No bare Doctor, `--non-interactive`, `--fix`, indexing, auth refresh, model smoke,
upgrade, restart or chat delivery is part of this pass. Doctor has a 120-second
deadline and other CLI checks have 60 seconds; an owned transient systemd unit
bounds the whole remote pass to eight minutes and cleans up diagnostic children after disconnection. It does
not stop the gateway. The helper itself makes no model inference; the native T3
worker interprets it.

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
results are retained privately and summarized in the native T3 thread.

State and private logs live in `~/.local/state/nightly-app-update/` (0700):

- `latest.json` and `events.jsonl`: durable phase/outcome and night.
- `diagnostics/manual-*.json` and `diagnostics/manual-latest.json`: explicit
  read-only results, exact runtime/config path and helper digest. Only check
  IDs/severities, counts, readiness/status fields and hashed auth identities are
  retained; raw tokens, profiles, CLI output and private channel identifiers are
  excluded. `checking` without completion records an interrupted pass; inspect it
  before retrying. The T3 worker records the night and interpreted outcome in its
  private evidence and thread. Historical dated receipts are retained unchanged.
- `runs/<Stockholm-date>/`: exact candidate manifest, release evidence, source,
  agent result/log, mutation intents/results, health and backup/restore evidence.
  `steps.jsonl` records static subprocess step labels, start/completion/failure,
  exit codes or timeout/OS error numbers. Failure receipts also include the phase
  and failing step when available. Commands, environment values and captured
  stdout/stderr are excluded; an old receipt containing only an exception type
  cannot establish which command failed.
- `paused`: prevents new maintenance; it does not interrupt work already running.
- `dispatch.json`: installation's next-night deadline, independent of older receipts.
- `installing`: a failed/interrupted schedule replacement holds dispatch until a
  successful explicit reinstall; it never starts maintenance to repair itself.
- `lock`: an advisory lock held for the whole attempt; overlapping launches exit.
- `gcroots/`: retains the installed scheduler and its runtime closure independently
  of Home Manager generations; previous roots are preserved during replacement.

Unchanged source clones and clones deferred before live maintenance are disposable;
the runner deletes only those owned candidate directories. Evidence and backups
remain. Temporary preparation records are separate from live rollout receipts.
Their subprocess diagnostics live in `preparation-steps.jsonl`. Validation tools
are declared in the Nix dev shell so `just check` also runs with launchd's minimal
PATH, without an interactive login profile.

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
Pause and wait for an active attempt to finish before manually activating a whole
Home Manager generation; the scoped installer refuses to interrupt a running job.

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
