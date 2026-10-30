# Hermes retirement on Obelisk

Hermes is retired from the authoritative host configuration. Its agent,
dashboard, Tailscale Serve route, service account and package input are removed.
OpenClaw is managed separately; see [openclaw.md](openclaw.md).

Retirement must preserve private conversation history, credentials and workspace
source in a root-only rollback archive. Account UID 3102 must not be reused while
retained files still carry that ownership. Existing Nix generations can retain
Hermes packages; removing configuration alone does not reclaim their closures.
Do not prune unrelated generations or OpenClaw recovery snapshots.
