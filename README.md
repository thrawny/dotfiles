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

Use `!fork-window` in Claude or Codex, or `/fork-window` in Pi, to fork the current conversation into a Herdr tab or a new Ghostty window on Hyprland without a model turn in the original session. The fork shares the checkout, acknowledges a fork notice, and waits for instructions. Restart or resume Claude once to load its session-ID hook. From a terminal, use `fork-window pi /path/to/session.jsonl`, `fork-window claude <session-uuid>`, or `fork-window codex <session-uuid>`. Container sandboxes are not supported.

```bash
just switch   # Apply config (NixOS, nix-darwin, or Home Manager)
just check    # Format, lint, evaluate
```
