# Shared Skills

Single source of truth for agent skills.

Home Manager links each shared skill folder individually to:
- `~/.pi/agent/skills/<skill-name>`
- `~/.claude/skills/<skill-name>`
- `~/.codex/skills/<skill-name>`

Skill directories are store-backed and immutable after `just switch`. Edit the source files in this repo, then rebuild to apply changes.

This keeps agent-managed state (for example `.../skills/.system`) in each agent's own config directory, not in this repo.

Add each skill as `skills/<skill-name>/SKILL.md` (plus any references/scripts/assets).

Codex slash-command replacement skills live under `config/codex/commands/<skill-name>/SKILL.md` and are linked only to `~/.codex/skills/<skill-name>`.

External skills are pinned as flake inputs and wired in `nix/lib/agent-skills.nix`. Update them with `nix flake update --flake ./nix <input-name>`.
