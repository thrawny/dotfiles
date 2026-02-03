# Repository Guide (Agent Focus)

This guide distills what an agent needs to know to make safe, precise code changes in this dotfiles repo. It emphasizes source-of-truth locations; system setup steps are included only when necessary for verification.

## Overview

This repository manages cross-platform dotfiles using **Nix Home Manager** — declarative configuration in `nix/`. See `nix/CLAUDE.md` for details and `.claude/rules/nix.md` for guidance on which files to edit.

## Task Runner

Uses `just` for common tasks. Run `just` to see all available recipes:

```bash
just              # List all recipes
just switch       # Apply Nix config (auto-detects NixOS vs Home Manager)
just check        # Format, lint, and evaluate config
just fmt          # Format all (nix, lua, python)
just lint         # Lint all
just rust build   # Build all rust packages (or specific: just rust build bash-validator)
just rust test    # Run all rust tests
```

**Prefer `just` over `cd`**: Always run `just` commands from the repo root instead of `cd`ing into subdirectories. This avoids confusion about working directory. If a needed command isn't available, add a `just` recipe rather than `cd`ing around.

## Agent Essentials

- Source of truth: edit files in-repo only.
- Primary areas to edit: `nix/`, `config/`, `bin/`, `rust/`.
- You generally do not need to run package managers (Homebrew/APT) or OS setup scripts to modify repo content.

## Paths: Source → Target

Nix Home Manager uses `mkOutOfStoreSymlink` to link config directories into the home directory:

- Editors: `config/nvim` → `~/.config/nvim`
- Git: `config/git/gitconfig` → `~/.gitconfig`, `config/git/gitignoreglobal` → `~/.gitignoreglobal`
- Apps: `config/k9s` → `~/.config/k9s`, `config/npm/default-packages` → `~/.default-npm-packages`
- Codex/Claude: `config/codex/` → `~/.codex/`, `config/claude/` → `~/.claude/`

Configs generated entirely by Nix (no files in `config/`): zsh, tmux, ghostty, direnv, starship.

### Claude Config Locations

Two different locations exist for Claude configuration in this repo:

| Location | Scope | Symlinked to |
|----------|-------|--------------|
| `config/claude/` | **Global** - applies to all projects | `~/.claude/` |
| `.claude/` | **Project-specific** - only for this dotfiles repo | (not symlinked) |

When adding Claude commands, agents, skills, or settings:
- Put in `config/claude/` if it should be available globally across all projects
- Put in `.claude/` if it's specific to working on this dotfiles repo

## Nix Configuration

Flake-based NixOS and Home Manager config in `nix/`. See `nix/CLAUDE.md` for details.

## Common Agent Tasks

- Update an existing dotfile: edit its source file in this repo (see Paths section).
- Modify shell aliases/functions: edit `nix/home/shared/zsh.nix`.
- Update Neovim config: edit files in `config/nvim`.

### Settings Files with Example/Live Pairs

Some tools have both a tracked example file and a gitignored live file. When updating settings for these tools, always offer to update both:

| Tool   | Example (tracked)                           | Live (gitignored)                    |
|--------|---------------------------------------------|--------------------------------------|
| Claude | `config/claude/settings.example.json`       | `config/claude/settings.json`        |
| Codex  | `config/codex/config.example.toml`          | `config/codex/config.toml`           |
| Cursor | `config/cursor/settings.example.json`       | `config/cursor/settings.json`        |

When asked to modify settings, update the example file first, then ask if the user also wants the live file updated.

### LazyVim Setup

- Neovim has been migrated to **LazyVim**, a modern Neovim distribution.
- Main entry: `config/nvim/init.lua`
- Configuration files in `lua/config/`:
  - `keymaps.lua`: Custom keybindings (leader key set to comma)
  - `options.lua`: Editor options
  - `autocmds.lua`: Autocommands
  - `lazy.lua`: Lazy.nvim plugin manager setup
- Plugin specs in `lua/plugins/`: `theme.lua` (monokai-nightasty), `ui.lua` (bufferline disabled, buffer navigation configured)
- Settings file: `lazyvim.json`
- When editing LazyVim config, restart Neovim to reload plugins.

## Verification (optional)

- Python env: `uv sync` installs dependencies locally; `.envrc` activates it via direnv.
- Apply Nix config: `just switch`.

## Python Setup

- Tooling: uses `uv` for dependency management and `direnv` for auto-activation.
  - Entering this directory activates the environment via `.envrc` (`layout uv`).
  - If direnv is not enabled, run `uv sync` and then use `uv run …` or activate `.venv` manually.
- Requirements: Python `>=3.12` (managed by `uv`).
- Install dependencies: `uv sync` (add `--dev` to include dev tools like ruff/pyright).
- Add/remove deps: `uv add <pkg>`, `uv remove <pkg>`.
- Project package: `claude_tools/` (module with small CLIs and helpers). Entrypoints are defined in `pyproject.toml`:
  - `claude-loop` → `claude_tools.simple_loop:cli_main`
- Run scripts (without activating venv explicitly):
  - `uv run claude-loop "fix type errors" -d 30m -w 30s`
  - Or module form: `uv run -m claude_tools.simple_loop --help`
- Notes:
  - `bin/notify-sound` is used by Codex notifications: plays a sound on macOS; no-op on Linux.
  - `bin/notify` shows cross-platform visual notifications (macOS/Linux).
  - These tools expect Claude/Codex to be installed/configured; they orchestrate workflows but are optional for editing files.

## Notes

- Repo directories of interest: `nix/`, `config/`, `bin/`, `rust/`, `claude_tools/`.
- Shell convenience commands, package managers, and desktop apps are not required for typical agent edits, so are intentionally omitted here.
