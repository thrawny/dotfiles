# Maintained forks and reference repositories

Updated **2026-08-04**.

This file tracks repositories that are currently maintained, intentionally kept for source/documentation reference, or provide user-installed tools that are actively used. Own projects are included when their local build is part of the running system. Abandoned experiments, historical GitHub forks, and cleanup history are out of scope.

## Independent maintained projects

### `codediff.nvim`

`codediff.nvim` is an independent project, not a maintained fork. Its GitHub fork ancestry and `upstream` remote are historical implementation details; original-upstream divergence is not maintenance debt and must not trigger rebasing or fork-sync work.

Local `main` still tracks the original upstream and has 16 commits not yet on `origin/main`. After reviewing the outgoing commits, correct its own-project tracking separately from fork maintenance:

```bash
cd ~/code/codediff.nvim
git push origin main
git branch --set-upstream-to=origin/main main
```

## Maintained forks

| Repository | Upstream | Current state | Maintenance policy |
|---|---|---:|---|
| `nirius` | SourceHut `~tsdh/nirius` | 4 ahead / 0 behind | Continue following upstream and rebase only when upstream advances. |
| `pi-diff` | `buddingnewinsights/pi-diff` | 20 ahead / 0 behind | Continue following upstream. It is loaded directly by the live Pi configuration. |
| `zmx` | `neurosnap/zmx` | 3 ahead / 0 behind | Continue following upstream. |

All maintained forks are current. None needs rebasing or updating.

## Reference/source repositories

These checkouts are intentionally retained for reading source and documentation. Installed tools and services come from Nix or package inputs rather than these local clones.

| Repository | Reference purpose | Update policy |
|---|---|---|
| `acpx` | ACP CLI behavior, skills, and implementation reference | Fetch/pull only when investigating current behavior. |
| `openclaw` | OpenClaw source and integration reference | Update on demand. |
| `hermes-agent` | Hermes source and service integration reference | Update on demand. |
| `pi` | Pi source and documentation reference | Update on demand; the active Pi binary and docs come from the Nix-installed version. |

Behind counts on reference repositories are not maintenance debt.

## Active tools installed outside Nix

These tools are currently used from user-managed installations rather than the Nix profile. Local Cargo installation metadata confirms which repository each binary was built from.

| Tool | Active installation | Evidence of current use | Maintenance note |
|---|---|---|---|
| `agent-history` | `~/.cargo/bin/agent-history`, built from `~/code/agent-history` | Called by the Pi handoff extension | Installed binary predates repository `HEAD`; rebuild after reviewing the latest commit. |
| `agent-switch` | `~/.cargo/bin/agent-switch`, built from `~/code/agent-switch` | Running daemon/dev loop; used by Pi, Claude, Codex, Niri, and Waybar integrations | Repository is 5 commits ahead of origin. The installed release binary predates current source; active development is running `target/debug/agent-switch`. |
| `fastmail-cli` | `~/.cargo/bin/fastmail-cli`, built from `~/code/fastmail-cli` | Confirmed active CLI | Local source tracks upstream directly and is 22 commits behind. Update and rebuild when current upstream behavior is needed; the personal GitHub fork remains dormant. |
| `niri-cu` | `~/.cargo/bin/niri-cu`, built from `~/code/niri-cu` | Used for the active nested/sandboxed Niri work | The repository has no remote. Add one if the project needs off-machine protection. |
| `nirius` / `niriusd` | `~/.cargo/bin`, built from `~/code/nirius` | `niriusd` is running; Niri and helper scripts call `nirius` | Nix also installs `pkgs.nirius`, but the Cargo binaries win on the current `PATH`. Keep the Cargo build current while developing the fork, or remove it when returning to the Nix package. |
| `quotabar` | `~/.cargo/bin/quotabar`, built from `~/code/quotabar` | Waybar invokes this exact absolute path | Repository is 3 commits ahead of origin. Rebuild/restart Waybar after code changes and push retained work. |
| `wayvoice` | `~/.cargo/bin/wayvoice`, built from `~/code/wayvoice` | `wayvoice serve` and HUD are running; Niri keybindings invoke it | Repository is 4 commits ahead of origin with nine dirty paths. Protect/commit the work, rebuild, and restart the service when ready. |
| `glimpseui` | npm-global `glimpseui@0.8.1` | Runtime dependency of `bin/live-html` | Installed from npm, not the deleted source clone. `~/dotfiles/node_modules/glimpseui` links to the global package for Bun resolution. |

### Other active user-managed tools

These are not backed by repositories under `~/code`, but recent use shows they are part of the current toolset.

| Tool | Installation | Current use / ownership |
|---|---|---|
| `extract_otp_secrets` | Standalone binary in `~/.local/bin` | Used in late July. Its installation source is not recorded, so it is not currently reproducible. |
| `impeccable` | npm-global `impeccable@2.1.8` | CLI used in July. This is separate from Pi's skill-based `/impeccable` integration. |
| `pyinfra` | uv tool, `pyinfra@3.8.0` | Used in August. |
| `sonos` | `go install github.com/steipete/sonoscli/cmd/sonos@v0.3.4` | Used in August. |
| `migrate` | `go install github.com/golang-migrate/migrate/v4/cmd/migrate@v4.19.1` with PostgreSQL support | Used for database migration work. |
| `live-html` / `share-html` | Scripts run directly from `~/dotfiles/bin` | Local preview/publishing workflow; `live-html` depends on the npm-global `glimpseui` package above. |

### Updating local Cargo tools

For a tool intentionally built from its local checkout:

```bash
cd ~/code/<repo>
cargo install --path . --force
```

Then restart any daemon, HUD, or Waybar process that holds the old binary. A successful source build does not update `~/.cargo/bin` unless the install command is run.

## Review cadence

When reviewing this inventory:

1. Fetch the upstream remotes of the maintained forks.
2. Check ahead/behind state against upstream default branches.
3. Rebase only forks that are intentionally following upstream.
4. Treat `codediff.nvim` as independent unless that policy is explicitly changed.
5. Ignore reference-repository drift until current source is needed.
