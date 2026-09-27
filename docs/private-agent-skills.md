# Private agent skills

Private skills live in a separate private Forgejo repository, cloned to `~/code/private-agent-skills`. Do not put their contents in this public checkout or add the private repository as a Nix flake input.

## Host setup

The Home Manager option `dotfiles.privateAgentSkills.enable` defaults to false. It is enabled explicitly on `thrawny-z13`, `thrawny-desktop`, `thrawnym1`, and `obelisk`. The work Mac `jonaslergell` and container images do not opt in.

Each enabled machine needs Tailscale connectivity and Git credentials for Forgejo. The existing Git credential helper supplies authentication. Tailscale access alone does not grant access to the private repository. Keep credentials out of Nix and this repository.

After authentication is ready, run `just switch-hm`. Activation clones the repository if missing, otherwise fetches `main` and attempts a fast-forward update. A dirty checkout or another checked-out branch prevents updates. Diverged history needs a manual merge or rebase. Each Git operation has a 20-second timeout and does not prompt for credentials. Failures warn without failing activation; an existing checkout still supplies skills offline.

## Add and update skills

Create one top-level folder per skill in the private checkout:

```text
private-agent-skills/
└── fleet/
    ├── SKILL.md
    └── references/
        └── inventory.md
```

Commit and push there, not in dotfiles. On another enabled machine, activation picks up the changes, or run from the dotfiles root:

```bash
just private-skills-sync  # Fetch updates and refresh skill links
just private-skills-link # Refresh links without fetching
```

Each folder containing `SKILL.md` gets a symlink in `~/.claude/skills`, `~/.codex/skills`, and `~/.pi/agent/skills`. The helper skips hidden folders and symlinked skill folders or manifests. Public skill names are reserved. Existing unrelated files and symlinks are never overwritten. When a skill disappears from the checkout, the helper removes only its own matching links. A missing checkout does not trigger link cleanup.

Edits to existing skills are visible through their symlinks immediately. New or renamed folders need another link refresh. In Pi, run `/reload` after changes.

## Privacy

Only the helper and its configuration enter the Nix store. The checkout is private runtime state, not a Home Manager source. The helper refuses to run when `SANDBOX=1`; container configurations do not enable it.

Private Git hosting does not keep skill contents out of model requests or agent session logs. Do not put credentials in skills, and do not copy private inventory into public artifacts.

## Checks

Run `just test-private-skills` for local Git integration tests and `just check` for repository checks. Tests use temporary repositories and isolated Git configuration, without Forgejo credentials or network access.
