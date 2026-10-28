# Dotfiles

My personal configuration for Linux and macOS, managed with Nix flakes, Home Manager, and nix-darwin.

## Stack

| Layer | Tool |
| --- | --- |
| Linux desktop | Hyprland |
| Terminal | Ghostty |
| Editor | Neovim (LazyVim) |
| Shell | Zsh + Starship |

## Structure

- `nix/` — system definitions, Home Manager modules, packages, and theme.
- `config/` — application configuration managed by Nix.
- `shell/` — custom desktop shell.
- `bin/` — runtime commands and utilities.
- `scripts/` — development and validation helpers.
- `skills/` — shared agent skills.
- `docs/` — component documentation and reference guides.
