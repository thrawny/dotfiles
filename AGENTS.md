# Repository Guide

Cross-platform dotfiles managed with Nix Home Manager (`nix/`). See `nix/AGENTS.md` for nix specifics.

- Task runner is `just`, always from the repo root — if a command is missing, add a recipe rather than `cd`ing into subdirectories.
- Scripts of 50+ lines go in `bin/` as standalone executables; Nix exposes or configures the script, it does not contain the implementation.

## Source → target

Two symlink styles, and the difference matters:

- **Mutable** (`mkOutOfStoreSymlink`, edit takes effect immediately): `config/nvim` → `~/.config/nvim`, `config/claude/` → `~/.claude/`, `config/codex/` → `~/.codex/`, `config/pi/` → `~/.pi/agent/`.
- **Immutable** (store-backed, needs `just switch` to take effect): each folder in `skills/` → `~/.claude/skills/<skill>`, `~/.pi/agent/skills/<skill>`, `~/.codex/skills/<skill>` per the selection in `nix/lib/agent-skills.nix`; `config/codex/commands/` → `~/.codex/skills/` only.

Zsh, tmux, ghostty, direnv, starship etc. are generated entirely by Nix — no files in `config/`; edit the module in `nix/`.

`config/claude/` is the user's global `~/.claude/`; `.claude/` in this repo is project-specific and not symlinked anywhere.

## Example/live settings pairs

Claude (`config/claude/settings.example.json`), Codex (`config/codex/config.example.toml`), and Pi (`config/pi/settings.example.json`) each have a gitignored live counterpart without the `example` infix. Update the example first, then ask whether to also update the live file.
