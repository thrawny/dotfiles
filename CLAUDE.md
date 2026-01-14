# Repository Guide (Agent Focus)

This guide distills what an agent needs to know to make safe, precise code changes in this dotfiles repo. It emphasizes source-of-truth locations and symlink rules; system setup steps are included only when necessary for verification.

## Overview

This repository manages cross-platform dotfiles with Ansible. Source files live inside this repo; Ansible symlinks them into the home directory on target machines.

## Agent Essentials

- Source of truth: edit files in-repo only; Ansible handles symlinks on install.
- Primary areas to edit: `shell/`, `git/`, `config/`, `ansible/`, `osx/`.
- When adding a new config, create it under `config/` (or relevant dir) and add a symlink task in `ansible/all_config.yml` if it should appear in `$HOME`.
- You generally do not need to run package managers (Homebrew/APT) or OS setup scripts to modify repo content.

## Paths: Source → Target

- Shell: `config/zsh/zshrc` → `~/.zshrc`, `config/tmux/tmux.conf` → `~/.tmux.conf`
- Editors: `config/vim` → `~/.vim`, `config/nvim` → `~/.config/nvim`
- Git: `config/git/gitconfig` → `~/.gitconfig`, `config/git/gitignoreglobal` → `~/.gitignoreglobal`
- Apps: `config/ghostty` → `~/.config/ghostty`, `config/direnv` → `~/.config/direnv`
- Extras: `config/starship/starship.toml` → `~/.config/starship.toml`, `config/k9s` → `~/.config/k9s`, `config/npm/default-packages` → `~/.default-npm-packages`
- Codex/Claude: `config/codex/config.toml` → `~/.codex/config.toml`, `config/codex/prompts` → `~/.codex/prompts`, `config/claude/commands` → `~/.claude/commands`, `config/claude/settings.json` → `~/.claude/settings.json`, `config/claude/agents` → `~/.claude/agents`, `config/claude/skills` → `~/.claude/skills`, `config/claude/CLAUDE-GLOBAL.md` → `~/.claude/CLAUDE.md`

Refer to `ansible/all_config.yml` for the authoritative symlink list.

## Ansible Structure

- `ansible/main.yml` orchestrates all tasks.
- Cross-platform: `ansible/all_config.yml`, `ansible/all_software.yml`.
- Linux-wide: `ansible/linux_software.yml` (when `ansible_system == 'Linux'`).
- macOS-only: `ansible/osx_software.yml`, `ansible/osx_config.yml` (when `ansible_distribution == 'MacOSX'`).

## Nix Configuration

Flake-based NixOS and Home Manager config in `nix/`. See `nix/CLAUDE.md` for details.

## Common Agent Tasks

- Update an existing dotfile: edit its source file in this repo (see Paths section). No immediate action is needed unless you want to re-run symlinks on a machine.
- Add a new config file: place it under `config/` (or relevant dir) and add a corresponding `file` task in `ansible/all_config.yml` to create the symlink.
- Modify shell aliases/functions: edit `config/zsh/zshrc`.
- Update Neovim/Vim configs: edit `config/nvim` or `config/vim`.

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

- Python env: `uv sync` installs Ansible locally; `.envrc` activates it via direnv.
- Apply symlinks on a machine: `ansible-playbook ansible/main.yml`.
  - OS-specific tasks are selected via Ansible facts (`when:` conditions); no tags are required.

## Python Setup

- Tooling: uses `uv` for dependency management and `direnv` for auto-activation.
  - Entering this directory activates the environment via `.envrc` (`layout uv`).
  - If direnv is not enabled, run `uv sync` and then use `uv run …` or activate `.venv` manually.
- Requirements: Python `>=3.12` (managed by `uv`).
- Install dependencies: `uv sync` (add `--dev` to include dev tools like ruff/pyright/ansible-lint).
- Add/remove deps: `uv add <pkg>`, `uv remove <pkg>`.
- Project package: `claude_tools/` (module with small CLIs and helpers). Entrypoints are defined in `pyproject.toml`:
  - `claude-work-timer` → `claude_tools.work_timer:cli_main`
  - `claude-loop` → `claude_tools.simple_loop:cli_main`
- Run scripts (without activating venv explicitly):
  - `uv run claude-work-timer "refactor X" -d 1h`
  - `uv run claude-loop "fix type errors" -d 30m -w 30s`
  - Or module form: `uv run -m claude_tools.work_timer --help`
- Notes:
  - `bin/notify-sound` is used by Codex notifications: plays a sound on macOS; no-op on Linux.
  - `bin/notify` shows cross-platform visual notifications (macOS/Linux).
  - These tools expect Claude/Codex to be installed/configured; they orchestrate workflows but are optional for editing files.

## Notes

- Repo directories of interest: `config/`, `ansible/`, `nix/`, `osx/`, `claude_tools/`, `bin/`.
- Shell convenience commands, package managers, and desktop apps are not required for typical agent edits, so are intentionally omitted here.
