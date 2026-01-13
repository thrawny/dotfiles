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
just nix-check    # Format, lint, and evaluate config (auto-detects NixOS vs Home Manager)
just switch       # Apply changes (auto-detects NixOS vs Home Manager)
just dry          # Full build without switching (NixOS only)
just diff         # Build and show changes (NixOS only)
```

## Structure

- `flake.nix` - Main flake configuration
- `hosts/` - Per-host configurations
- `modules/nixos/` - NixOS system modules
- `home/shared/` - Cross-platform Home Manager modules
- `home/nixos/` - NixOS-specific Home Manager modules
- `home/darwin/` - macOS-specific Home Manager modules
- `home/asahi/` - Asahi Linux Home Manager modules
