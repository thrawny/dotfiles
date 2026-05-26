# Dotfiles

My dotfiles and system configuration, declaratively managed with Nix.

## Stack

| Layer    | Tool                      |
| -------- | ------------------------- |
| Config   | Nix Flakes + Home Manager |
| WM       | Niri                      |
| Terminal | Ghostty                   |
| Editor   | Neovim (LazyVim)          |
| Shell    | Zsh + Starship            |

## Structure

```
nix/      # NixOS & Home Manager modules
config/   # Tool configs linked or seeded by Nix
bin/      # Scripts and utilities added to PATH
skills/   # Local agent skills linked into Claude, Pi, and Codex
```

## Usage

```bash
just switch   # Apply config (auto-detects NixOS vs Home Manager)
just check    # Format, lint, evaluate
```
