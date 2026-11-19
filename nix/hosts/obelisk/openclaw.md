# OpenClaw on Obelisk

OpenClaw uses the pinned first-party `openclaw/nix-openclaw` gateway package and a NixOS system service, running as
`openclaw`, UID 3101. Settings live in `nix/modules/openclaw.nix`; service wiring
and the administrative wrapper live in `nix/modules/agents.nix`.

## Operations

Run these from the repository root:

```sh
just nix::check-openclaw
just nix::build-host obelisk
just nix::deploy obelisk
just nix::openclaw-health
```

From macOS, use `just nix::build-remote obelisk` to build on Linux over SSH.
This copies tracked working files into an isolated temporary directory, limits
build parallelism, and starts a persistent `dotfiles-build` zmx session. It does
not activate. Inspect the system diff and take the stopped-service backup below
before installing its `result` with NixOS activation on the server.

Allow startup to finish before the health check. It prints configuration warnings
and checks config validity, active plugin failures, channel operation and the local
UI. It does not send chat messages or invoke a model. Discovery warnings from an
unused bundled plugin are advisory; active plugin errors still fail the check.

Use the administrative wrapper on Obelisk, including for interactive commands:

```sh
ssh -t root@obelisk 'openclaw-admin health'
ssh -t root@obelisk 'openclaw-admin models auth login --provider openai --device-code'
```

`openclaw-admin` runs as the service user with its Nix mode, config path, tools and
systemd EnvironmentFile. It does not source that file as shell code. Model login
updates runtime credentials; do not pass `--set-default`, which changes config.
Model selection belongs in Nix. Keep the explicit Codex runtime, ChatGPT transport
and empty fallback list to avoid an unintended switch to API-key billing. New
model names can precede OpenClaw's static routing table; a healthy OAuth status
does not prove a model turn works. Test through the scheduler after changing
model routing.

The ChatGPT model list offers Sol 6.2 only to Codex 0.166.0 and newer; 0.164.0
does not get it. Update the Codex runtime together with the default model. The
pinned OpenClaw catalog predates Sol 6.2, so Nix declares the model entry.

## Configuration and state

The `shared` agent has a separate workspace at
`/srv/agents/openclaw/workspaces/shared` and its own default agent state directory.
Its Telegram binding reads `OPENCLAW_SHARED_GROUP_ID` from the service env file.
The group's sender allowlist lives in
`/srv/agents/openclaw/home/.openclaw/secrets/shared-telegram-groups.json`, as a
JSON object keyed by the exact group ID. Nix admits that directory through
`OPENCLAW_INCLUDE_ROOTS`; the include must exist before activation. Keep it
root-owned and readable by the `openclaw` group. This keeps personal chat and
participant identifiers outside the public source and store-generated config.
The private group requires a bot mention. Node pairing remains independent of
chat routing; the agent still runs on the gateway with the M1 available as a
command target. Do not copy OAuth credentials into the new agent's store.

The service env file pins `OPENCLAW_CONFIG_PATH` and `OPENCLAW_INCLUDE_ROOTS`;
both the gateway and administrative wrapper read those overrides, and they mask
the config of any later generation. Nightly maintenance rolls out scoped configs
through this pin, so keep the mechanism. Earlier pins were configs derived from
the generated Nix config with the older Codex runtime path retained; the last
one before November 18, 2026 was the nightly candidate config. That day the pin
moved to the unmodified `openclaw.json` of the system generation deployed then,
for Sol 6.2, and it carries that generation's Codex runtime. Read the pinned path
from the env file and the runtime from the config it names. The stopped-service
backup from before that switch is on M1.

Obelisk collects generations older than a day, and `obelisk-storage` also
collects under disk pressure, so every pinned config needs its own GC root under
`/nix/var/nix/gcroots`. A Nix-built config's root also keeps the Codex runtime it
names. A derived config has no store references, so its root does not: keep a
separate root for that runtime. Deployment provenance, the config GC roots and
recovery state are retained privately on the host.

A persistent drop-in,
`/etc/systemd/system.control/openclaw.service.d/90-nightly-maintenance.conf`,
also overrides the unit. It pins `ExecStart` to a gateway path and clears
`ExecStartPre`, so the Forgejo bootstrap does not run on start, and it survives
deploys. The pinned config already contains the shared route and its private
include. When intentionally deploying a complete generation, reconcile the env
overrides and that drop-in so they do not mask the new generation.

- The service reads `OPENCLAW_CONFIG_PATH` directly from the Nix store.
- `/srv/agents/openclaw/home/.openclaw` contains mutable state and credentials.
- `/srv/agents/openclaw/workspace` contains the existing agent workspace.
- `/srv/agents/openclaw/env` supplies the gateway and Telegram tokens, other
  provider and GitHub API keys, the `OPENCLAW_CONFIG_PATH` and
  `OPENCLAW_INCLUDE_ROOTS` overrides, and private group and approver
  identifiers. Edit single lines; never regenerate it from this list. Discord
  uses the existing private JSON token file referenced by the Nix config.
- Credentials are required for configured channels. Startup no longer silently
  disables channels when credentials are missing.
- Bundle the separately packaged official Codex plugin into the gateway so its
  reserved harness hooks share the gateway SDK and registry. Load Discord through
  its Nix store path; OpenAI, Telegram and memory-core remain bundled. Update them together;
  do not use runtime plugin installs.
- Chat defaults are Sol 6.2 with low reasoning. Recurring heartbeat and autonomous
  skill reviews are disabled. Memory dreaming uses Luna 6; its model override is
  restricted to that model.
- Operator cron jobs live in the runtime SQLite store, not the Nix config. Use
  `openclaw-admin cron` or the Gateway API to manage them. Use workspace-relative
  state paths and explicit delivery routes for notification jobs. `command`
  payload jobs run no model and need no profile.
- The gateway package's `docs/cli/cron.md` and `docs/automation/cron-jobs/` pages
  describe the scheduler. Two rules matter on this host. An older agent-turn job
  fails with "Automation has no recorded inference account" until it is bound to a
  stored profile (`troubleshooting.md`). A login also replaces the account behind
  its profile, so after any `models auth login` every job bound to that profile
  fails with "Automation inference account was replaced"; only the built
  `inference-binding` runtime documents this. In both cases, list the owning
  agent's profiles with `openclaw-admin models status --agent <agent>` and bind
  each job to one marked `ok` that belongs to the subscription account:
  `openclaw-admin cron edit <id> --model openai/<model>@<profileId> --thinking
  low`. Pick the model from `modelPolicy.allow` in `nix/modules/openclaw.nix`, and
  keep the job's fallbacks empty.
- Recurring jobs auto-disable after 10 consecutive errors (`delivery.md`) and stay
  disabled after the cause is fixed. `openclaw-admin cron list --all` shows them,
  and `openclaw-admin cron get <id>` records the reason in `state.autoDisabled`
  and `state.lastError`. Fix the cause, then run the job once with `openclaw-admin
  cron run <id> --wait --wait-timeout 20m`. It exits 0 only for `completionStatus:
  succeeded`, which a silent `NO_REPLY` run also reaches; check `delivery` in its
  output when a message was expected. Then run `openclaw-admin cron enable <id>`.
- Systemd tmpfiles copies the prebuilt UI into a package-specific, root-owned
  directory under `/var/lib/openclaw-ui`. This avoids runtime asset retention and
  the custom-UI handler's rejection of hardlinked Nix store files. The service
  cannot write there. New packages get new directories; old copies can be removed
  after retiring their rollback generations.

Do not use runtime config setters, plugin installers or self-update commands.
Change Nix and deploy instead. Nix mode does not make agent memory immutable.

The September 26, 2026 cron cleanup archived job definitions, recent run history,
validation results and a copy of workspace memory at
`/srv/backups/openclaw/cron-repair-20260926T163922Z/`. This is a cron-repair snapshot,
not a full service backup. Recreate archived jobs through the scheduler API rather
than replacing SQLite files.

## Release-specific caveat

In 2026.8.2, backup recovery bypasses the Nix-mode write guard and can replace a
config symlink with an older snapshot. Reading the store path directly prevents
this. The gateway logs an `EROFS` warning when attempting to write a `.last-good`
sidecar beside that path. Nix generations and state backups provide recovery;
do not make the store writable to suppress the warning.

## State migrations and recovery

Take a consistent backup of the entire `/srv/agents/openclaw` tree with the service
stopped. Record and retain its NixOS generation too. Preserve symlinks without
following them when copying or verifying the backup.

For an upgrade requiring `doctor --fix`, keep the gateway stopped. Give Doctor a
private, writable copy of the active config and the existing state/workspace
paths. Run it as `openclaw` in a one-off service using the same credential
EnvironmentFile, with Nix mode disabled only for that migration. Translate any
required configuration changes back into Nix; never install Doctor's mutable
output as the authoritative configuration. Archive the temporary config securely
because it may contain credentials.

The September 7, 2026 migration fixed a startup failure caused by unmigrated
workspace setup/attestation files. Doctor also migrated legacy auth, memory events
and transcripts into SQLite. The pre-migration backup is on Obelisk at:

```text
/srv/backups/openclaw/20260907T110240Z/
```

It contains `state/`, a verified copy of the complete agent tree, and
`system-generation`. Stop OpenClaw before restoring. Restore the matching state
and Nix generation together; rolling back only the executable does not undo
SQLite migrations.

The October 18, 2026 upgrade to the official 2026.10.4 package migrated both
agent databases from schema v21 to v24. Its verified pre-upgrade state and system
generation are retained at `/srv/backups/openclaw/official-nix-20261017T220143Z/`.
Doctor's private configuration and log are archived there under `doctor-success/`;
its temporary optional-plugin installs are archived under `doctor-installs/`.
The Nix configuration remains authoritative. Doctor can install optional plugins
while Nix mode is disabled, so reconcile those side effects after a migration.

Shared-agent node command approvals are sent to the operator's Telegram DM.
Set `OPENCLAW_TELEGRAM_EXEC_APPROVER` in the private service EnvironmentFile to
the verified numeric operator ID. The public config filters requests to agent
`shared`; existing command ownership and other agents remain unchanged. A
successful config/recipient check does not verify delivery or the operator's
button click. Complete that check with a real Telegram-origin read-only command.
