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
```

**Prefer `just` over `cd`**: Always run `just` commands from the repo root instead of `cd`ing into subdirectories. If a needed command isn't available, add a `just` recipe rather than `cd`ing around.

## Paths: Source to Target

Nix Home Manager uses `mkOutOfStoreSymlink` to link tracked config into the home directory:

- `config/nvim` -> `~/.config/nvim`
- `config/codex/` -> tracked files under `~/.codex/`, `config/claude/` -> `~/.claude/`, `config/pi/` -> `~/.pi/agent/`
- Each folder in `skills/` -> `~/.claude/skills/<skill>`, `~/.pi/agent/skills/<skill>`, and `~/.codex/skills/<skill>` (except `skill-creator` for Codex)
- Each folder in `config/codex/skills/` -> `~/.codex/skills/<skill>` only

Configs generated entirely by Nix (no files in `config/`): zsh, tmux, ghostty, direnv, starship etc.

### Claude Config Locations

| Location | Scope | Symlinked to |
|----------|-------|--------------|
| `config/claude/` | **Global** - applies to all projects | `~/.claude/` |
| `.claude/` | **Project-specific** - only for this dotfiles repo | (not symlinked) |

- Global commands/agents/settings -> `config/claude/`
- Shared skills -> `skills/`
- Codex-only skills -> `config/codex/skills/`
- Dotfiles-repo-specific -> `.claude/`

### Settings Files with Example/Live Pairs

Some tools have both a tracked example file and a gitignored live file. When updating settings, update the example file first, then ask if the user also wants the live file updated.

| Tool   | Example (tracked)                           | Live (gitignored)                    |
|--------|---------------------------------------------|--------------------------------------|
| Claude | `config/claude/settings.example.json`       | `config/claude/settings.json`        |
| Codex  | `config/codex/config.example.toml`          | `config/codex/config.toml`           |
| Pi     | `config/pi/settings.example.json`           | `config/pi/settings.json`            |
