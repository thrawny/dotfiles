# Repository Guide

Cross-platform dotfiles managed with Nix Home Manager (`nix/`). See `nix/AGENTS.md` for nix specifics.

- Task runner is `just`, always from the repo root — if a command is missing, add a recipe rather than `cd`ing into subdirectories.
- Scripts of 50+ lines go in `bin/` as standalone executables; Nix exposes or configures the script, it does not contain the implementation.

## Source → target

Two symlink styles, and the difference matters:

- **Mutable** (`mkOutOfStoreSymlink`, edit takes effect immediately): `config/claude/` → `~/.claude/`, `config/codex/` → `~/.codex/`, `config/pi/` → `~/.pi/agent/`.
- **Immutable** (store-backed, needs `just switch` to take effect): `config/nvim/lua` is copied into the nix-built Neovim package (`nix/lib/nvim-package.nix`); each folder in `skills/` → `~/.claude/skills/<skill>`, `~/.pi/agent/skills/<skill>`, `~/.codex/skills/<skill>` per the selection in `nix/lib/agent-skills.nix`; `config/codex/commands/` → `~/.codex/skills/` only.

Zsh, tmux, ghostty, direnv, starship etc. are generated entirely by Nix — no files in `config/`; edit the module in `nix/`.

## Theme

Colors live in one canonical document, `nix/themes/monokai.json` (semantic/syntax/terminal/diff roles plus per-app `applications` overrides). `nix/lib/theme.nix` loads and validates it; Home Manager passes it to modules as the `theme`/`themeLib` args and publishes a runtime copy at `~/.config/dotfiles/theme.json` for mutable consumers (Neovim fallback, the Pi status line). Never add `#RRGGBB` literals to themed consumers — edit the theme and run `just switch`; `just check-theme` enforces this.

`config/claude/` is the user's global `~/.claude/`; `.claude/` in this repo is project-specific and not symlinked anywhere.

## Example/live settings pairs

Claude (`config/claude/settings.example.json`), Codex (`config/codex/config.example.toml`), and Pi (`config/pi/settings.example.json`) each have a gitignored live counterpart without the `example` infix. Update the example first, then update the live file by default without asking. Only leave the live file unchanged when the user explicitly requests it.
