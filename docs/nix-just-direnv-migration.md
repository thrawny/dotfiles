# Migration Plan: mise → nix + just + direnv

## Overview

Replace mise with a cleaner separation of concerns:
- **nix** → tools and dependencies (via flake devshells)
- **direnv + nix-direnv** → environment activation (caching, GC roots)
- **just** → task runner (simple, good monorepo support)

## Motivation

- mise fights nix for tool management; the `mise-nix` plugin is flaky
- nix-direnv has 1k+ commits of battle-tested caching and edge case handling
- just is simple, focused, and has native monorepo support via modules
- Clear separation: each tool does one thing well

## Current State

```
mise.toml (root)
├── tasks: switch, dry, diff, fmt:*, lint:*, nix:*
├── tools: nix:nixfmt, nix:stylua, etc. (via mise-nix plugin)
└── monorepo: experimental_monorepo_root = true

rust/niri-switcher/mise.toml
├── tasks: build, run, nix, install
└── env: wraps commands with nix develop
```

## Target State

```
Justfile (root)
├── recipes: switch, dry, diff, fmt, lint, clean
└── modules: mod niri "rust/niri-switcher"

rust/niri-switcher/
├── Justfile: build, run, nix, install
└── .envrc: use flake ../../nix#niri-switcher-dev

nix/
├── devShells: niri-switcher-dev (existing)
└── packages: tools via home.packages or system packages
```

## Migration Steps

### Phase 1: Add just and direnv infrastructure

1. Add `just` to nix packages
2. Enable `programs.direnv` with `nix-direnv.enable = true` in Home Manager
3. Create root `Justfile` with basic recipes

### Phase 2: Migrate root tasks

Convert mise tasks to just recipes:

```just
# Justfile (root)

# Default recipe
default:
    @just --list

# === Nix workflows ===

# Switch configuration (auto-detects NixOS vs Home Manager)
switch:
    #!/usr/bin/env bash
    host=$(hostname | sed 's/\.local$//')
    if [ -f /etc/NIXOS ]; then
        sudo nixos-rebuild switch --flake "./nix#$host"
    else
        home-manager switch --flake "./nix#$host"
    fi

# Dry-run NixOS rebuild
dry:
    sudo nixos-rebuild dry-run --flake "./nix#$(hostname)"

# Build and show diff
diff:
    sudo nixos-rebuild build --flake "./nix#$(hostname)" && nvd diff /run/current-system result

# Evaluate config without building
eval:
    #!/usr/bin/env bash
    host=$(hostname | sed 's/\.local$//')
    if [ -f /etc/NIXOS ]; then
        nix eval "./nix#nixosConfigurations.$host.config.system.build.toplevel" --no-write-lock-file > /dev/null
    else
        nix eval "./nix#homeConfigurations.$host.activationPackage" --no-write-lock-file > /dev/null
    fi
    echo "Config is valid"

# Clean old generations and optimize store
clean:
    nix-env --delete-generations +6
    sudo nix-env -p /nix/var/nix/profiles/system --delete-generations +6 || true
    nix-collect-garbage
    nix store optimise

# === Formatters ===

# Format all
fmt: fmt-nix fmt-lua fmt-python

# Format Nix files
fmt-nix:
    nix fmt ./nix

# Format Lua files
fmt-lua:
    stylua config/nvim

# Format Python files
fmt-python:
    uv run ruff check --fix && uv run ruff format .

# === Linters ===

# Lint all
lint: lint-nix lint-lua lint-python

lint-nix:
    statix check

lint-lua:
    selene config/nvim

lint-python:
    uv run ruff check .

# === Combined ===

# Format, lint, and evaluate
check: fmt lint eval
```

### Phase 3: Migrate niri-switcher

1. Create `.envrc` (with graceful fallback for non-nix systems):
```bash
# Only activate flake devshell if nix-direnv is available
if has use_flake; then
  use flake ../../nix#niri-switcher-dev
fi
```

2. Create `Justfile`:
```just
# rust/niri-switcher/Justfile

# Build with cargo (incremental)
build:
    cargo build --release

# Build and run
run: build
    ../target/release/niri-switcher

# Build with nix (clean build)
nix:
    nix build path:../../nix#niri-switcher

# Build and symlink to result
install:
    nix build path:../../nix#niri-switcher -o result
```

3. Add module to root Justfile:
```just
mod niri "rust/niri-switcher"
```

### Phase 4: Update nix packages

Add tools to `nix/home/shared/packages.nix`:
```nix
just
treefmt        # optional: unified formatter
nixfmt-rfc-style
nvd
selene
statix
stylua
```

Or keep them in devshells where appropriate.

### Phase 5: Remove mise

1. Delete `mise.toml` files
2. Remove `config/mise/` directory
3. Remove mise from zshrc activation (if any)
4. Remove mise symlinks from ansible
5. Update documentation

### Phase 6: Update documentation

- Update `CLAUDE.md` to reference `just` commands
- Update `nix/CLAUDE.md`
- Add Justfile comments for discoverability

## File Changes Summary

### New files
- `Justfile` (root)
- `rust/niri-switcher/Justfile`
- `rust/niri-switcher/.envrc`
- `treefmt.toml` (optional)

### Modified files
- `nix/home/shared/packages.nix` - add just, remove mise-managed tools
- `nix/home/shared/direnv.nix` - enable nix-direnv
- `CLAUDE.md` - update task commands
- `nix/CLAUDE.md` - update task commands

### Deleted files
- `mise.toml` (root)
- `rust/niri-switcher/mise.toml`
- `config/mise/config.toml`
- `nix/home/shared/mise.nix` (if exists)

## Command Mapping

| mise                  | just                    |
|-----------------------|-------------------------|
| `mise switch`         | `just switch`           |
| `mise dry`            | `just dry`              |
| `mise diff`           | `just diff`             |
| `mise fmt`            | `just fmt`              |
| `mise lint`           | `just lint`             |
| `mise nix:check`      | `just check`            |
| `mise nix:clean`      | `just clean`            |
| `mise run build`      | `just niri::build`      |
| `mise run nix`        | `just niri::nix`        |

## Rollback Plan

Keep the `direnv-nix-devshell` branch as intermediate state.
The `claude/replace-mise-with-nix-5sFtP` branch has a working implementation to reference.

## Cross-Platform Considerations

`.envrc` files committed to the repo must not break on non-nix systems:

```bash
# Pattern for .envrc files
if has use_flake; then
  use flake path/to/flake#devshell
fi
```

The `has use_flake` check returns false when nix-direnv isn't installed, so the file silently does nothing on macOS/ansible-managed systems.

## Open Questions

1. Keep mise globally for non-nix systems (macOS via ansible)?
2. Use treefmt for unified formatting or keep separate commands?
3. Add CI checks via `just ci` recipe?

## References

- [just manual](https://just.systems/man/en/)
- [nix-direnv](https://github.com/nix-community/nix-direnv)
- Branch: `claude/replace-mise-with-nix-5sFtP` - existing implementation
- Branch: `direnv-nix-devshell` - hybrid approach (mise + direnv)
