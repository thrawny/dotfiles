# Nix Configuration Guide

This flake-based configuration manages both NixOS systems and Darwin (macOS) via Home Manager.

## Commands

All commands are managed via [mise](https://mise.jdx.dev/), a modern task runner and tool manager.

### NixOS: Rebuild System
```bash
mise switch       # Rebuild and switch immediately (auto-detects hostname)
mise dry          # Dry-run rebuild without switching
```

Or directly:
```bash
sudo nixos-rebuild switch --flake ./nix#thinkpad
```

### Darwin/macOS: Switch Home Manager
```bash
mise switch-darwin       # Switch Home Manager configuration for macOS
```

Or directly:
```bash
home-manager switch --flake ./nix#thrawny-darwin
```

### Development Tasks

#### Format Code
```bash
mise fmt              # Run all formatters (Python, Lua, Nix)
mise fmt:python       # Format Python with Ruff
mise fmt:lua          # Format Neovim Lua config with Stylua
mise fmt:nix          # Format Nix files with nixfmt/treefmt
```

#### Lint Code
```bash
mise lint             # Run all linters
mise lint:python      # Lint Python with Ruff
mise lint:lua         # Lint Lua with Selene
mise lint:nix         # Lint Nix with statix
```

#### Type Checking
```bash
mise typecheck        # Run all type checkers
mise typecheck:python # Typecheck Python with basedpyright
```

#### Tests
```bash
mise test             # Run all tests
mise test:nvim        # Run Neovim config tests
```

#### CI Pipeline
```bash
mise ci               # Run full CI pipeline (fmt, lint, typecheck, test)
```

#### Build ISO
```bash
mise iso              # Build desktop installer ISO with network drivers
```

View all available tasks:
```bash
mise tasks ls         # List all tasks with descriptions
```

## Configuration Structure

### General
- `flake.nix` - Main flake configuration (defines both NixOS and Darwin configurations)
- `home/shared/` - Shared Home Manager modules (work on both NixOS and Darwin)
  - `default.nix` - Main shared home configuration
  - `git.nix`, `zsh.nix`, `tmux.nix`, etc. - Cross-platform app configs

### NixOS-Specific
- `modules/nixos/` - System-wide NixOS configuration
  - `system.nix` - Core system settings (timezone, keyd, packages)
  - `packages.nix` - Package definitions
- `home/nixos/` - NixOS-specific Home Manager modules
  - `hyprland/` - Window manager configuration
  - `waybar.nix` - Status bar configuration
  - Other Linux-specific modules

### Darwin/macOS-Specific
- `home/darwin/` - Darwin-specific Home Manager modules
  - `default.nix` - Main Darwin home configuration
  - `cursor.nix` - Cursor editor configuration (Library/Application Support paths)
  - `lazygit.nix` - Lazygit configuration (Library/Application Support paths)
  - `aerospace.nix` - Aerospace window manager configuration
  - `defaults.nix` - macOS system defaults (via `defaults write`)

## Key Features

### NixOS Features

#### Keyboard Remapping (keyd)
System-wide key remapping configured in `modules/nixos/system.nix`:
- Caps Lock ↔ Escape swap
- Left Alt ↔ Left Meta swap (Mac-like)
- Right Alt → Right Meta
- ISO keyboard fixes (Shift+< → ~)

#### Hyprland Window Manager
- Mod key set to ALT (works with physical Windows key due to keyd swap)
- Configuration in `modules/home-manager/hyprland/`

### Darwin/macOS Features

#### Home Manager Standalone
- Uses Home Manager without nix-darwin for simpler setup
- Manages dotfiles, packages, and configurations
- macOS system defaults configured via `home.activation` scripts

#### macOS Defaults
Configured in `home/darwin/defaults.nix`:
- Finder: Show hidden files, extensions, path bar
- Keyboard: Fast key repeat, disable press-and-hold
- Dock: Minimize to application, disable recents, auto-hide
- Screenshots: PNG format, saved to ~/Screenshots
- And more...

#### Plugin Managers
- **Zinit**: Zsh plugin manager (installed via activation script)
- **TPM**: Tmux Plugin Manager (installed via activation script)
- Both work with existing configuration files

## Code Quality

**IMPORTANT**: After making any changes to Nix files, always run:
```bash
mise fmt:nix    # Format Nix code with nixfmt
mise lint:nix   # Lint Nix code with statix
```

This ensures code follows Nix best practices:
- No repeated attribute keys (combine into single attribute sets)
- Use `inherit` instead of assignments like `x = x;`
- Replace empty patterns `{ ... }:` with `_:`
- Consistent formatting and style

## Important Notes

### NixOS
- Hostname: `thinkpad` (must match flake configuration)
- Username: Set via `dotfiles.username` option
- Git tree warnings during rebuild are normal for uncommitted changes

### Darwin/macOS
- Configuration: `thrawny-darwin` (hardcoded in flake.nix)
- Username: `jonas` (configured in flake.nix extraSpecialArgs)
- First run: Installs Zinit and TPM automatically via activation scripts
- macOS defaults: Run `killall Finder Dock` after first switch to see changes

### Both Platforms
- All config files use out-of-store symlinks for easy editing
- Shared modules work on both NixOS and Darwin
- Edit files in `~/dotfiles/config/` and changes reflect immediately

## File Paths

### Shared (NixOS and Darwin)
- Shell config: `~/.zshrc` → `~/dotfiles/config/zsh/zshrc`
- Git config: `~/.gitconfig` → `~/dotfiles/config/git/gitconfig`
- Tmux config: `~/.tmux.conf` → `~/dotfiles/config/tmux/tmux.conf`
- Neovim config: `~/.config/nvim` → `~/dotfiles/config/nvim`
- Codex config: `~/.codex` → `~/dotfiles/config/codex`
- Claude config: `~/.claude/commands` → `~/dotfiles/config/claude/commands`

### NixOS-Specific
- Cursor settings: `~/.config/Cursor/User/settings.json` → `~/dotfiles/config/cursor/settings.json`
- Walker launcher: `~/.config/walker/` → `~/dotfiles/config/walker/`
- Lazygit config: `~/.config/lazygit` → `~/dotfiles/config/lazygit`

### Darwin/macOS-Specific
- Cursor settings: `~/Library/Application Support/Cursor/User/` → `~/dotfiles/config/cursor/`
- Lazygit config: `~/Library/Application Support/lazygit` → `~/dotfiles/config/lazygit`
- Aerospace config: `~/.aerospace.toml` → `~/dotfiles/config/aerospace/aerospace.toml`