# v1 scope cut

Type: grilling
Status: resolved

## Question

What is inside the v1 blueprint's scope? Two axes:

- **Hosts** — local-only, or local + the NixOS EC2 (remote thread visibility and state sync) from day one?
- **Harnesses** — pi only, pi + claude, or pi + claude + codex?

The answer gates the registry's cross-host design ([04](04-registry-design.md)), whether the codex producer research ([05](05-codex-status-surface.md)) matters for v1, and which fog graduates next (hand-raise/ntfy, transcript sync).

## Answer

Resolved 2026-08-03.

- **Hosts: local implementation, remote-shaped schema.** v1 implements local-only, but the registry schema assumes nothing about producer and reader sharing a machine: `host` field on every thread from day one. Sync/transport is designed-for but deferred to v2; the EC2 keeps being used manually meanwhile.
- **Harnesses: pi + claude + codex.** The user chose "pi + claude, codex conditional on the research finding an equally cheap surface." [Codex status surface](05-codex-status-surface.md) resolved the conditional in favor of inclusion: Codex ships a Claude-compatible hooks engine (11 events incl. `PermissionRequest`, fires headless), and `config/codex/hooks.agent-switch.json` already wires three of them. Harness stays an open enum in the registry — adding one later is a producer, not a schema change.
- **Consequences:** hand-raise/ntfy and transcript sync stay fog (remote-phase, not v1). No fog graduates from this answer.
