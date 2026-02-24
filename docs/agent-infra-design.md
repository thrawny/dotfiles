# Agent Infrastructure Design

Research and decisions from exploring how to give AI agents safe, scoped access to git repositories and build out supporting infrastructure.

## Problem

Agents need to push code and create PRs, but giving them full git credentials is dangerous — a compromised agent could wipe a repo, force-push to main, or exfiltrate tokens. GitHub Free lacks the access controls needed to prevent this (no branch protection on private repos, no operation-level token scoping).

## Options Evaluated

### GitHub Fine-Grained PATs

- Scoped by resource category (contents, pull requests, issues, etc.) and per-repo
- **Limitation**: no operation-level granularity within a category — `contents: write` means push, force-push, delete branches, everything
- Not sufficient for safe agent access

### Daytona

- "Agent outside sandbox" model — credentials held by orchestration code, not the sandbox
- Git operations go through a Toolbox API proxy, credentials passed per-call (transient)
- Supports custom proxy for adding your own ACL rules
- **Limitation**: no branch-level or operation-level restrictions at the platform layer — delegated to the git token

### Sprites.dev (Fly.io)

- "Give full access, make recovery cheap" philosophy
- Agent runs in a Firecracker microVM with direct git access
- DNS-based network policies (allow/deny domains) are the only network control
- Safety via checkpoint/restore (300ms snapshot), not prevention
- **Limitation**: no credential isolation, no proxy, no operation-level restrictions

### Self-Hosted Forgejo (chosen approach)

Forgejo provides the server-side controls that GitHub Free lacks:

- **Branch protection on all repos** (including private): push whitelists, force-push prevention, merge whitelists, required approvals, status checks
- **Repository permission levels**: Write access (push, create PRs) without Admin (no settings changes, no repo deletion)
- **Scoped API tokens**: `write:repository`, `read:issue`, etc. (but not per-repo — mitigated by only granting the agent user access to specific repos)
- **Protected tags**: prevent agent from creating releases
- **Server-side pre-receive hooks**: restrict agent to specific branch patterns

#### Agent lockdown configuration

1. Dedicated `ai-agent` user with Write collaborator access on target repos only
2. Branch protection on `main`: push whitelist (humans only), force-push disabled, merge whitelist (humans only), require 1 approval
3. Scoped API token: `write:repository` only
4. Tag protection: only human accounts
5. Pre-receive hook restricting agent to `agent/*` branches

#### Pre-receive hook

Place at `<repo>.git/hooks/pre-receive.d/01-restrict-agent`:

```bash
#!/usr/bin/env bash
RESTRICTED_USER="bot-agent"
ALLOWED_PATTERN="^refs/heads/agent/"

if [[ "$GITEA_PUSHER_NAME" != "$RESTRICTED_USER" ]]; then
    exit 0
fi

rejected=0
while read -r old_sha new_sha refname; do
    if [[ ! "$refname" =~ $ALLOWED_PATTERN ]]; then
        echo "*** DENIED: User '$RESTRICTED_USER' may only push to 'agent/*' branches." >&2
        echo "*** Rejected ref: $refname" >&2
        rejected=1
    fi
done

exit $rejected
```

Forgejo passes `GITEA_PUSHER_NAME`, `GITEA_PUSHER_ID`, `GITEA_REPO_NAME` etc. as environment variables. Hooks are reliable for SSH/HTTPS pushes. Web editor/API pushes may bypass custom hooks — branch protection covers those.

`DISABLE_GIT_HOOKS = true` (default) only disables the web UI for editing hooks. Scripts on the filesystem always execute.

#### Known gaps

| Gap | Workaround |
|---|---|
| No per-repo token scoping | Only grant agent user access to specific repos |
| No "create PR but not merge" scope | Merge whitelist in branch protection |
| Deploy keys are SSH-only | Combine deploy key (git push) + API token (PR creation) |
| OAuth2 tokens have no scopes | Use personal access tokens, not OAuth2 |
| No global hooks directory | Deploy hooks per-repo or script deployment |

## Infrastructure Architecture

```
Agent microVMs (Hetzner, ephemeral)
    │
    │ push branches, create PRs
    ▼
NixOS VPS (Hetzner CX22, always-on)
├── Forgejo (git hosting, policy enforcement)
├── Attic (Nix binary cache)
├── Tailscale (networking + TLS)
    │
    │ mirror/sync
    ▼
GitHub (public/community repos)
```

### Why NixOS over k8s

- Handful of services, not dozens — k8s orchestration overhead isn't justified
- All config is declarative Nix in the dotfiles repo
- Tailscale provides service mesh / connectivity
- Agent VMs are separate Hetzner instances via API, not pods needing orchestration
- k8s would make sense at ~10+ services or if agent scheduling becomes complex

### Hosting: Forgejo

- Single Go binary, ~150 MB RAM idle
- SQLite with WAL mode (no separate database server)
- NixOS `services.forgejo` module handles everything
- Registration disabled, users created via CLI

### Hosting: Attic

- Rust binary, ~50-100 MB RAM idle
- S3 backend for store path storage (Hetzner Object Storage)

### Networking: Tailscale Serve

No nginx or Caddy needed. Tailscale Serve handles TLS and routing declaratively:

```nix
services.tailscale.serve = {
  enable = true;
  services = {
    forgejo.endpoints."tcp:443" = "http://localhost:3000";
    attic.endpoints."tcp:443" = "http://localhost:8080";
  };
};
```

Each service gets its own `*.ts.net` hostname with automatic TLS. Only accessible within the tailnet. Git SSH works directly over Tailscale connectivity.

Tailscale free plan: 100 devices, 3 users.

### Backups

- `services.forgejo.dump` for automatic daily Forgejo backups
- Restic to Hetzner Storage Box for offsite backup
- SQLite online backup: `sqlite3 forgejo.db ".backup /backup/forgejo.db"`

### Cost

| Component | Specs | EUR/mo (ex. VAT) |
|---|---|---|
| CX22 VPS | 2 vCPU, 4 GB RAM, 40 GB disk | 3.79 |
| Object Storage | 1 TB storage + 1 TB egress | 4.99 |
| **Total** | | **8.78** |

Object storage can be deferred until local disk fills up (start at 3.79/mo). Agent VMs billed hourly when running (~0.006/hr for CX22).
