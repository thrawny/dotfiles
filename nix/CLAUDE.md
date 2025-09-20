# NixOS Configuration Guide

This flake-based NixOS configuration manages the system setup for the ThinkPad.

## Commands

### Rebuild System
```bash
make switch       # Rebuild and switch immediately
```

Or directly:
```bash
sudo nixos-rebuild switch --flake ./nix#thinkpad
```

### Format Nix Files
```bash
make fmt         # Uses treefmt to format all Nix files
```

## Configuration Structure

- `flake.nix` - Main flake configuration
- `modules/nixos/` - System-wide NixOS configuration
  - `system.nix` - Core system settings (timezone, keyd, packages)
  - `packages.nix` - Package definitions
- `modules/home-manager/` - User-specific configuration via Home Manager
  - `default.nix` - Main home configuration
  - `hyprland/` - Window manager configuration
  - `waybar.nix` - Status bar configuration
  - Other app-specific modules

## Key Features

### Keyboard Remapping (keyd)
System-wide key remapping configured in `modules/nixos/system.nix`:
- Caps Lock ↔ Escape swap
- Left Alt ↔ Left Meta swap (Mac-like)
- Right Alt → Right Meta
- ISO keyboard fixes (Shift+< → ~)

### Hyprland Window Manager
- Mod key set to ALT (works with physical Windows key due to keyd swap)
- Configuration in `modules/home-manager/hyprland/`

## Important Notes

- Hostname: `thinkpad` (must match flake configuration)
- Username: Set via `dotfiles.username` option
- Git tree warnings during rebuild are normal for uncommitted changes
- All config files use out-of-store symlinks for easy editing

## File Paths

After rebuild, configuration files are symlinked:
- Cursor keybindings: `~/.config/Cursor/User/keybindings.json` → `~/dotfiles/config/cursor/keybindings.json`
- Walker launcher: `~/.config/walker/` → `~/dotfiles/config/walker/`
- Shell config: `~/.zshrc` → `~/dotfiles/config/zsh/zshrc`