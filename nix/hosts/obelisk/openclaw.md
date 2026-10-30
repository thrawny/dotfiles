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

Sol 6.1 was verified with Codex 0.159.2. Codex 0.157.1 rejects that model with
the same ChatGPT account, so keep the runtime update with the default change.
The pinned OpenClaw catalog also needs the explicit Sol 6.1 model entry in Nix.

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

The initial shared-chat deployment retains the running Codex runtime instead of
activating unrelated pending system updates. Its immutable config is derived
from the generated Nix config with only that runtime path retained. The service
env file pins `OPENCLAW_CONFIG_PATH` and `OPENCLAW_INCLUDE_ROOTS`; both the gateway
and administrative wrapper read those overrides. Deployment provenance, the
baseline config GC root and recovery state are retained privately on the host.
When intentionally deploying a complete generation, reconcile those env overrides
so they do not mask the new generation's config. Do not remove them before the
generation includes the shared route and its private include.

- The service reads `OPENCLAW_CONFIG_PATH` directly from the Nix store.
- `/srv/agents/openclaw/home/.openclaw` contains mutable state and credentials.
- `/srv/agents/openclaw/workspace` contains the existing agent workspace.
- `/srv/agents/openclaw/env` supplies the gateway and Telegram tokens. Discord
  uses the existing private JSON token file referenced by the Nix config.
- Credentials are required for configured channels. Startup no longer silently
  disables channels when credentials are missing.
- Bundle the separately packaged official Codex plugin into the gateway so its
  reserved harness hooks share the gateway SDK and registry. Load Discord through
  its Nix store path; OpenAI, Telegram and memory-core remain bundled. Update them together;
  do not use runtime plugin installs.
- Chat defaults are Sol 6.1 with low reasoning. Recurring heartbeat and autonomous
  skill reviews are disabled. Memory dreaming uses Luna 6; its model override is
  restricted to that model.
- Operator cron jobs live in the runtime SQLite store, not the Nix config. Use
  `openclaw-admin cron` or the Gateway API to manage them. Keep their model set to
  `openai/gpt-6-luna`, thinking low, and fallbacks empty. Use workspace-relative
  state paths and explicit delivery routes for notification jobs.
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
