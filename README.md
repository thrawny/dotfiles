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
config/   # Configs for things not managed by nix
bin/      # Scripts and utilities
rust/     # Custom Rust tools
```

## Usage

```bash
just switch   # Apply config (auto-detects NixOS vs Home Manager)
just check    # Format, lint, evaluate
```
