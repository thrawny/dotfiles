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

### NixOS
```bash
mise check        # Evaluate config (no build)
mise dry          # Full build without switching
mise switch       # Build and activate
mise diff         # Build and show changes
```

### Home Manager (standalone)
```bash
mise check-hm     # Evaluate config (no build)
mise switch-hm    # Switch configuration
```

### Code Quality
```bash
mise nix:check    # Format and lint Nix files
```

## Structure

- `flake.nix` - Main flake configuration
- `hosts/` - Per-host configurations
- `modules/nixos/` - NixOS system modules
- `home/shared/` - Cross-platform Home Manager modules
- `home/nixos/` - NixOS-specific Home Manager modules
- `home/darwin/` - macOS-specific Home Manager modules
- `home/asahi/` - Asahi Linux Home Manager modules
