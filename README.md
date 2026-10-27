# Dotfiles

My dotfiles and system configuration, declaratively managed with Nix.

Canonical repository: [thrawny/dotfiles on GitHub](https://github.com/thrawny/dotfiles). Use GitHub for fetches, pushes and pull requests.

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

For this M1 Air's nix-darwin migration, Tailscale SSH, and closed-lid use, follow the fleet guide at `fleet/references/mac-remote-access.md` in the [private skills checkout](docs/private-agent-skills.md).

On the desktop, Z13, and M1, `remote-mode on` keeps the machine awake for remote access across logouts and reboots. Use `remote-mode off` to restore normal sleep behavior, or `remote-mode status` to check it. See [remote mode](docs/remote-mode.md) for laptop precautions.

[Private agent skills](docs/private-agent-skills.md) sync from Forgejo on opted-in personal hosts, outside this public checkout and the Nix store.

Use `!fork-window` in Claude or Codex, or `/fork-window` in Pi, to fork the current conversation into a Herdr tab or a new Ghostty window on Hyprland without a model turn in the original session. The fork shares the checkout, acknowledges a fork notice, and waits for instructions. From a terminal, use `fork-window pi /path/to/session.jsonl`, `fork-window claude <session-uuid>`, or `fork-window codex <session-uuid>`. Container sandboxes are not supported.

Use `/spawn <task>` in Claude to start a new session in a Herdr tab that begins work on a task from the current conversation. A fork of the conversation writes the task brief and picks the repo and worktree, then runs `spawn-session`, which opens the tab and starts the agent.

Use `blueprint-serve ./lab` for a searchable Markdown/HTML library with live browser refresh, or `blueprint-html` to export a standalone page. See [Blueprint previews](docs/blueprint.md).

```bash
just switch   # Apply config (NixOS, nix-darwin, or Home Manager)
just check    # Format, lint, evaluate
```

Python tooling (uv, Ruff, and ty) is supplied by Nix. Run `just lint-python`, `just typecheck-python`, and `just test-python`; `nix develop ./nix` supplies the same tools before Home Manager is activated. Python test dependencies stay in `uv.lock`.
