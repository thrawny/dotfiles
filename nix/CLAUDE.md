# Nix Configuration Guide

Flake-based configuration for NixOS systems and standalone Home Manager.

## Flake Targets

**NixOS systems:**
- `thrawny-z13` - ThinkPad Z13 Gen 2 (Ryzen 7 PRO 7840U, 64GB RAM, 2TB NVMe, 2.8K OLED, 4G) (x86_64-linux)
- `thrawny-desktop` - Desktop (x86_64-linux)
- `obelisk` - Headless service server (Forgejo, PostgreSQL) (x86_64-linux)
- `headless` / `headless-docker` - Incus image with nested Docker (x86_64-linux)
- `headless-podman` - Incus image with rootless Podman and Docker CLI compatibility (x86_64-linux)

**Home Manager standalone:**
- `thrawnym1` - MacBook M1 (aarch64-darwin)

## Structure

- `flake.nix` - Main flake configuration
- `hosts/` - Per-host configurations (variables in `default.nix`, host-specific packages in `home.nix`)
- `modules/nixos/` - NixOS system modules (desktop imports `default.nix`, headless imports `headless.nix`)
- `home/shared/` - Cross-platform Home Manager modules (packages, zsh, git, tmux, etc.)
- `home/darwin/` - macOS-specific Home Manager modules
- `home/nixos/` - NixOS-specific Home Manager modules
- `home/linux/` - Linux/Wayland Home Manager modules (Niri config in `niri/`)

## Host-Specific Packages

Global packages go in `home/shared/packages/core.nix`, `workstation.nix`, `cloud.nix`, and `ai.nix`. Host-specific packages are wired into `flake.nix` via each host's Home Manager modules.

## After Changes

- Run `nixfmt` on edited Nix files.
- For non-trivial Nix changes, run `just check` from the repo root to format, lint, and evaluate.
- After larger NixOS changes on a NixOS host, run `just -f nix/Justfile diff` from the repo root to compare the build against `/run/current-system` with `nvd`.
