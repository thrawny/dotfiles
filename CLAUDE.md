# Repository Guide (Agent Focus)

This repo manages cross-platform dotfiles using **Nix Home Manager** — declarative configuration in `nix/`. See `nix/CLAUDE.md` for nix structure and `.claude/rules/nix.md` for which files to edit.

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

**Prefer `just` over `cd`**: Always run `just` commands from the repo root instead of `cd`ing into subdirectories. If a needed command isn't available, add a `just` recipe rather than `cd`ing around.

## Agent Essentials

- Source of truth: edit files in-repo only.
- Primary areas to edit: `nix/`, `config/`, `skills/`, `bin/`, `rust/`.
- You generally do not need to run package managers (Homebrew/APT) or OS setup scripts to modify repo content.

## Paths: Source to Target

Nix Home Manager uses `mkOutOfStoreSymlink` to link config directories into the home directory:

- `config/nvim` -> `~/.config/nvim`
- `config/codex/` -> `~/.codex/`, `config/claude/` -> `~/.claude/`, `config/pi/` -> `~/.pi/agent/`
- Each folder in `skills/` -> `~/.claude/skills/<skill>`, `~/.pi/agent/skills/<skill>`, and `~/.codex/skills/<skill>` (except `skill-creator` for Codex)

Configs generated entirely by Nix (no files in `config/`): zsh, tmux, ghostty, direnv, starship.

### Claude Config Locations

| Location | Scope | Symlinked to |
|----------|-------|--------------|
| `config/claude/` | **Global** - applies to all projects | `~/.claude/` |
| `.claude/` | **Project-specific** - only for this dotfiles repo | (not symlinked) |

- Global commands/agents/settings -> `config/claude/`
- Shared skills -> `skills/`
- Dotfiles-repo-specific -> `.claude/`

### Settings Files with Example/Live Pairs

Some tools have both a tracked example file and a gitignored live file. When updating settings, update the example file first, then ask if the user also wants the live file updated.

| Tool   | Example (tracked)                           | Live (gitignored)                    |
|--------|---------------------------------------------|--------------------------------------|
| Claude | `config/claude/settings.example.json`       | `config/claude/settings.json`        |
| Codex  | `config/codex/config.example.toml`          | `config/codex/config.toml`           |
| Cursor | `config/cursor/settings.example.json`       | `config/cursor/settings.json`        |
| Pi     | `config/pi/settings.example.json`           | `config/pi/settings.json`            |

### LazyVim Setup

- Main entry: `config/nvim/init.lua`, config in `lua/config/`, plugin specs in `lua/plugins/`
- Leader key: comma
- Theme: monokai-nightasty
- Settings file: `config/nvim/lazyvim.json`

### Python

- `claude_tools/` module with CLI helpers. Entrypoint: `claude-loop` -> `claude_tools.simple_loop:cli_main`
- Uses `uv` + `direnv` (auto-activated via `.envrc`). Python >=3.12.
- `bin/notify` shows cross-platform visual notifications. `bin/notify-sound` plays a sound on macOS.
