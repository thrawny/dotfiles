# v1 scope cut

Type: grilling
Status: open

## Question

What is inside the v1 blueprint's scope? Two axes:

- **Hosts** — local-only, or local + the NixOS EC2 (remote thread visibility and state sync) from day one?
- **Harnesses** — pi only, pi + claude, or pi + claude + codex?

The answer gates the registry's cross-host design ([04](04-registry-design.md)), whether the codex producer research ([05](05-codex-status-surface.md)) matters for v1, and which fog graduates next (hand-raise/ntfy, transcript sync).
