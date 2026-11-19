# Dotfiles

My personal configuration for Linux and macOS, managed with Nix flakes, Home Manager, and nix-darwin.

## Stack

| Layer | Tool |
| --- | --- |
| Linux desktop | Hyprland |
| Terminal | Ghostty |
| Editor | Neovim (LazyVim) |
| Shell | Zsh + Starship |

## Start

On a new Apple Silicon Mac, install Apple's command line tools with `xcode-select --install`, then run the setup script:

```sh
git clone https://github.com/thrawny/dotfiles.git ~/dotfiles
cd ~/dotfiles
bin/bootstrap-mac
```

The script expects the checkout at `~/dotfiles` and walks you through installing Determinate Nix and the first switch. After that, run `just switch` from the repository root to apply changes.

## Structure

- `nix/`: system definitions, Home Manager modules, packages, and theme.
- `config/`: application configuration managed by Nix.
- `shell/`: custom desktop shell.
- `bin/`: runtime commands and utilities.
- `scripts/`: development and validation helpers.
- `skills/`: shared agent skills.
- `docs/`: component documentation and reference guides.
