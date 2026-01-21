# Codex Individual Symlinks Migration Plan

Migrate from symlinking the entire `~/.codex` directory to individual file symlinks, now that upstream has fixed the symlink overwrite issue.

## Background

Previously, Codex CLI (v0.58.0+) would overwrite `config.toml` symlinks with regular files on startup/update. The workaround was to symlink the entire `config/codex/` directory to `~/.codex`.

**Issue:** [#6646 - Honor config.toml symlinks when creating or updating config](https://github.com/openai/codex/issues/6646)

**Fix:** [PR #9445](https://github.com/openai/codex/pull/9445) merged Jan 19, 2026. Codex now follows symlink chains and writes to the final target file instead of replacing the symlink.

**Required version:** 0.88.0+ (fix landed after 0.87.0 release on Jan 16)

## Current State

### Directory structure
```
config/codex/
├── config.example.toml   # Tracked
├── config.toml           # Gitignored (live)
├── prompts/              # Tracked
├── auth.json             # Gitignored
├── history.jsonl         # Gitignored
├── sessions/             # Gitignored
├── skills/               # Gitignored (TODO: track?)
└── ...
```

### Current symlink approach
```nix
# nix/home/shared/default.nix
home.file.".codex".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/codex";
```

This symlinks the entire directory, which means all Codex state (sessions, history, auth) lives in the dotfiles repo (gitignored).

## Proposed State

Symlink only the files we want to manage, letting Codex own the rest in `~/.codex`:

```nix
home.file = {
  ".codex/config.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/codex/config.toml";
  ".codex/prompts".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/codex/prompts";
  # Optionally:
  # ".codex/skills".source = ...
};
```

### Benefits
- Codex manages its own state (`~/.codex/auth.json`, `sessions/`, `history.jsonl`) outside the dotfiles repo
- Cleaner separation between tracked config and runtime state
- Matches how Claude config is structured (individual symlinks for `commands/`, `settings.json`, etc.)

### Considerations
- Need to migrate existing `config/codex/auth.json` to `~/.codex/auth.json` (or re-authenticate)
- Session history will start fresh (existing sessions in `config/codex/sessions/` won't be accessible)

## Implementation Steps

### 1. Verify Codex version
```bash
codex --version  # Must be 0.88.0+
```

If not, upgrade first:
```bash
npm update -g @openai/codex
# or
codex self-update
```

### 2. Update Nix configuration

Edit `nix/home/shared/default.nix`:

```nix
# Before
home.file.".codex".source = config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/codex";

# After
home.file = {
  ".codex/config.toml".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/codex/config.toml";
  ".codex/prompts".source =
    config.lib.file.mkOutOfStoreSymlink "${dotfiles}/config/codex/prompts";
};
```

### 3. Update Ansible configuration

Edit `ansible/all_config.yml`:

```yaml
# Before
- name: codex folder is symlinked
  file:
    state: link
    dest: "{{ home_dir }}/.codex"
    src: "{{ dotfiles_dir }}/config/codex"

# After
- name: Ensure ~/.codex directory exists
  file:
    state: directory
    path: "{{ home_dir }}/.codex"
    mode: '0755'

- name: codex config.toml is symlinked
  file:
    state: link
    dest: "{{ home_dir }}/.codex/config.toml"
    src: "{{ dotfiles_dir }}/config/codex/config.toml"

- name: codex prompts are symlinked
  file:
    state: link
    dest: "{{ home_dir }}/.codex/prompts"
    src: "{{ dotfiles_dir }}/config/codex/prompts"
```

### 4. Migrate auth (one-time)

Before switching, backup auth:
```bash
cp ~/.codex/auth.json ~/codex-auth-backup.json
```

After switching:
```bash
# If ~/.codex/auth.json doesn't exist, restore it
cp ~/codex-auth-backup.json ~/.codex/auth.json
```

Or just re-authenticate with `codex`.

### 5. Clean up old state files from repo

After confirming everything works, remove gitignored state files from the repo:

```bash
rm -rf config/codex/auth.json
rm -rf config/codex/history.jsonl
rm -rf config/codex/sessions/
rm -rf config/codex/internal_storage.json
rm -rf config/codex/shell_snapshots/
rm -rf config/codex/tmp/
rm -rf config/codex/log/
rm -rf config/codex/version.json
rm -rf config/codex/skills/  # Unless we want to track skills
```

### 6. Update .gitignore

Simplify gitignore since state files no longer live in repo:

```gitignore
# Before
config/codex/*
!config/codex/config.example.toml
!config/codex/prompts

# After
config/codex/config.toml
```

### 7. Update CLAUDE.md

Update the paths documentation to reflect the new structure.

## Rollback

If issues occur, revert to the directory symlink approach:
1. Revert changes to `nix/home/shared/default.nix` and `ansible/all_config.yml`
2. Run `just switch` or Ansible playbook
3. Move any auth/state back to `config/codex/`

## Testing

1. Run `just switch`
2. Verify symlinks: `ls -la ~/.codex/`
3. Run `codex` and verify config is loaded
4. Make a config change via Codex (e.g., change model) and verify symlink survives
5. Check prompts are available: type `/` in Codex to see prompt list
