# Shared Skills

Single source of truth for agent skills.

Home Manager links each shared skill folder individually to:
- `~/.pi/agent/skills/<skill-name>`
- `~/.claude/skills/<skill-name>`
- `~/.codex/skills/<skill-name>` (except `skill-creator`, since Codex has a built-in one)

This keeps agent-managed state (for example `.../skills/.system`) in each agent's own config directory, not in this repo.

Add each skill as `skills/<skill-name>/SKILL.md` (plus any references/scripts/assets).
