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

Setting up a fresh Mac? Run `bin/bootstrap-mac` from the checkout for an interactive walkthrough, including adding a missing target. See the [new Mac bootstrap guide](docs/new-mac.md) for the initial clone and manual steps.

For this M1 Air's nix-darwin migration, Tailscale SSH, and closed-lid use, follow [Mac remote access](docs/mac-remote-access.md).

Use [`t3ctl`](docs/t3ctl.md) to control T3 Code on obelisk from agents or scripts.

```bash
just switch   # Apply config (NixOS, nix-darwin, or Home Manager)
just check    # Format, lint, evaluate
```
