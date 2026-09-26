# OpenClaw on Obelisk

OpenClaw uses Numtide's pinned package and a NixOS system service, running as
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

## Configuration and state

- The service reads `OPENCLAW_CONFIG_PATH` directly from the Nix store.
- `/srv/agents/openclaw/home/.openclaw` contains mutable state and credentials.
- `/srv/agents/openclaw/workspace` contains the existing agent workspace.
- `/srv/agents/openclaw/env` supplies the gateway and Telegram tokens. Discord
  uses the existing private JSON token file referenced by the Nix config.
- Credentials are required for configured channels. Startup no longer silently
  disables channels when credentials are missing.
- Use normal bundled plugin discovery, with an allowlist for Codex, OpenAI,
  Discord and Telegram. Do not add source-tree plugin paths or runtime installs.
- Chat defaults are Sol 6 with low reasoning. Recurring heartbeat and autonomous
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
