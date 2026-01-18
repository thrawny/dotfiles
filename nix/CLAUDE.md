# Nix Configuration Guide

Flake-based configuration for NixOS systems and standalone Home Manager.

## Flake Targets

**NixOS systems:**
- `thinkpad` - ThinkPad T14 (x86_64-linux)
- `thrawny-desktop` - Desktop (x86_64-linux)

**Home Manager standalone:**
- `thrawnym1` - MacBook M1 (aarch64-darwin)
- `thrawny-asahi-air` - Asahi Linux on MacBook Air (aarch64-linux)

## Commands

```bash
mise nix:check    # Format, lint, and evaluate config (auto-detects NixOS vs Home Manager)
mise switch       # Apply changes (auto-detects NixOS vs Home Manager)
mise dry          # Full build without switching (NixOS only)
mise diff         # Build and show changes (NixOS only)
```

## Structure

- `flake.nix` - Main flake configuration
- `hosts/` - Per-host configurations
- `modules/nixos/` - NixOS system modules
- `home/shared/` - Cross-platform Home Manager modules
- `home/nixos/` - NixOS-specific Home Manager modules
- `home/darwin/` - macOS-specific Home Manager modules
- `home/asahi/` - Asahi Linux Home Manager modules

## Notes

- Niri configuration lives under `home/linux/niri/` and is imported explicitly where needed.
- Niri is the daily driver; Hyprland remains available and can be selected in tuigreet when desired.
