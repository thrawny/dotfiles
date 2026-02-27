# Nix Configuration Guide

Flake-based configuration for NixOS systems and standalone Home Manager.

## Flake Targets

**NixOS systems:**
- `thinkpad` - ThinkPad T14 Gen 1 (i5-10310U, 16GB RAM, 256GB NVMe, FHD) (x86_64-linux)
- `z13` - ThinkPad Z13 Gen 2 (Ryzen 7 PRO 7840U, 64GB RAM, 2TB NVMe, 2.8K OLED, 4G) (x86_64-linux)
- `thrawny-desktop` - Desktop (x86_64-linux)
- `thrawny-server` - Headless server (x86_64-linux)
- `attic-server` - Headless Attic cache server (x86_64-linux)

**Home Manager standalone:**
- `thrawnym1` - MacBook M1 (aarch64-darwin)
- `jonas-kanel` - Work MacBook Pro M3 (aarch64-darwin)
- `thrawny-asahi-air` - Asahi Linux on MacBook Air (aarch64-linux)

## Structure

- `flake.nix` - Main flake configuration
- `hosts/` - Per-host configurations (variables in `default.nix`, host-specific packages in `home.nix`)
- `modules/nixos/` - NixOS system modules (desktop imports `default.nix`, headless imports `headless.nix`)
- `home/shared/` - Cross-platform Home Manager modules (packages, zsh, git, tmux, etc.)
- `home/darwin/` - macOS-specific Home Manager modules
- `home/nixos/` - NixOS-specific Home Manager modules
- `home/linux/` - Linux/Wayland Home Manager modules (Niri config in `niri/`)

## Host-Specific Packages

Global packages go in `home/shared/packages.nix`. Host-specific packages go in `hosts/<hostname>/home.nix` and are wired into `flake.nix` via the `modules` list. See `hosts/jonas-kanel/home.nix` for an example.
