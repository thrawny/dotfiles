# Ephemeral Nix Workers (Script-Driven) - Implementation Plan

## Overview

Provision short-lived Hetzner VMs, deploy a reusable headless NixOS profile, inject bootstrap credentials/config, do work, then delete the VM.

This plan intentionally avoids Terraform for worker lifecycle. Infrastructure is created/destroyed via scripts (`hcloud` + `nixos-anywhere`), while machine configuration remains declarative in the flake.

## Current State

- NixOS deployment script exists: `scripts/deploy-hetzner.sh`
- `attic-server` host exists (cache service + Tailscale bootstrap pattern)
- Build strategy supports local build + remote deployment (`--build-on local`)
- No dedicated reusable host/profile for disposable workers yet
- No create/destroy/prune worker scripts yet

## Desired End State

- One reusable flake host target for disposable workers (e.g. `ephemeral-worker`)
- Fast scripted lifecycle:
  - create VM
  - deploy flake target
  - inject bootstrap files/secrets
  - auto-join Tailscale
  - optional initial command
  - destroy VM when done
- No long-lived state system required for worker lifecycle
- Works with local prebuild + optional Attic cache acceleration

## What We're NOT Doing

- No Terraform state/backend for worker lifecycle
- No per-worker custom flake targets
- No persistent secrets committed to repository
- No complex orchestration layer

---

## Architecture

## 1) Reusable Host Target

Add a single host target:

- `nix/hosts/ephemeral-worker/default.nix`
- `nix/hosts/ephemeral-worker/disko.nix`
- `nix/hosts/ephemeral-worker/hardware-configuration.nix`

Properties:

- headless base (`modules/nixos/headless.nix`)
- lightweight defaults
- aggressive cleanup (small rollback window)
- Tailscale auto-connect support
- bootstrap one-shot service

## 2) Bootstrap Contract

Workers receive runtime bootstrap files via `nixos-anywhere --extra-files`:

- `/etc/bootstrap/gitconfig.local` (optional)
- `/etc/bootstrap/codex-auth.json` (optional)
- `/etc/bootstrap/claude-credentials.json` (optional)
- `/etc/bootstrap/start-command` (optional)
- `/etc/tailscale/auth-key` (optional)

One-shot systemd service on first boot:

1. Copies files to target user locations with strict permissions
2. Runs `tailscale up --auth-key ... --ssh` if key exists
3. Executes optional startup command
4. Deletes `/etc/bootstrap/*` and `/etc/tailscale/auth-key`

## 3) Script-Driven Lifecycle

Introduce scripts:

- `scripts/ephemeral-up.sh`
- `scripts/ephemeral-down.sh`
- `scripts/ephemeral-prune.sh` (optional)

`ephemeral-up.sh` responsibilities:

1. Create VM with `hcloud server create`
2. Label server (`role=ephemeral`, `owner=<user>`, `expires_at=<unix-ts>`)
3. Wait for SSH
4. Build temp bootstrap directory
5. Deploy with `scripts/deploy-hetzner.sh root@<ip> ephemeral-worker`
6. Output SSH/Tailscale connection details

`ephemeral-down.sh` responsibilities:

1. Resolve server by name or id
2. Confirm target
3. Delete via `hcloud server delete`

`ephemeral-prune.sh` responsibilities:

1. List `role=ephemeral`
2. Compare `expires_at` label to current time
3. Delete expired instances

## 4) Build/Deploy Speed Model

Primary mode:

- build on local Linux builder (`thrawny-desktop`)
- deploy closure to worker

Optional acceleration:

- prebuild `diskoScript` and `toplevel` once
- reuse with `nixos-anywhere --store-paths`
- allow workers to pull substitutes from Attic/cache.nixos.org

---

## Phase 0: Decisions

1. Confirm default VM class, region, and TTL
2. Confirm base packages on worker image
3. Confirm bootstrap secret sources (local files/env)

### Success Criteria

- [ ] Worker defaults agreed (size/region/ttl)
- [ ] Bootstrap file contract agreed

## Phase 1: Add `ephemeral-worker` Host

1. Add flake target in `nix/flake.nix`
2. Add host files under `nix/hosts/ephemeral-worker/`
3. Keep config minimal and headless
4. Add automatic GC/optimize and small boot generation limit

### Success Criteria

- [ ] `nix eval path:./nix#nixosConfigurations.ephemeral-worker.config.system.build.toplevel` succeeds

## Phase 2: Bootstrap Module

1. Add one-shot bootstrap service module (or inline host config)
2. Implement file copy + permissions
3. Implement Tailscale auth-key consumption
4. Implement secret cleanup at end

### Success Criteria

- [ ] First boot consumes bootstrap files and removes source secrets
- [ ] Tailscale joins automatically when key provided

## Phase 3: Worker Lifecycle Scripts

1. Implement `ephemeral-up.sh`
2. Implement `ephemeral-down.sh`
3. Optionally implement `ephemeral-prune.sh`
4. Add usage help and validation

### Success Criteria

- [ ] `ephemeral-up.sh` creates + deploys a working worker
- [ ] `ephemeral-down.sh` reliably deletes worker

## Phase 4: Optional Performance Enhancements

1. Add prebuild/reuse mode (`--store-paths`)
2. Add optional cache hints/output for Attic integration
3. Add script flag to skip build when store paths provided

### Success Criteria

- [ ] Second worker provision is meaningfully faster than first

## Phase 5: Documentation

1. Add quickstart doc (`docs/howto/ephemeral-workers.md`)
2. Document required tools (`hcloud`, `nixos-anywhere`)
3. Document bootstrap file format and security model

### Success Criteria

- [ ] End-to-end flow documented and reproducible

---

## Security Notes

- Never commit runtime secrets
- Provision secrets through temporary local directories only
- Use strict file modes for copied credentials
- Remove bootstrap artifacts after first-boot provisioning
- Prefer short-lived Tailscale auth keys where possible

## Operational Notes

- Keep workers disposable by design
- Prefer labels/TTL over manual tracking
- Treat failed workers as cattle: delete and recreate
- Keep host profile generic and avoid task-specific drift

## Open Questions

1. Should startup command run as root or worker user?
2. Which credential files are required vs optional?
3. Should worker hostname include timestamp or random suffix?
4. Should prune run manually or via local cron/job?

## Acceptance Criteria

- [ ] One command creates and deploys a worker VM
- [ ] Worker joins Tailscale when key provided
- [ ] Optional bootstrap credentials are installed and source files removed
- [ ] One command deletes the worker
- [ ] Worker deployment uses the same flake target repeatedly
