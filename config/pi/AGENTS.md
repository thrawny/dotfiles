# Global Pi Instructions

**Project-specific AGENTS.md files take precedence over these global defaults.**

## Rules Source of Truth

Language/tooling instructions are provided by the `claude-rules` extension from rule files in:

- `~/.claude/rules`
- `<repo>/.claude/rules` (project-specific)

Keep per-language formatting/testing guidance in rule files instead of duplicating it here.

## Task Runners

If the project has a `Justfile`, prefer `just` commands over raw tool invocations. Run `just` to see available recipes.

## Respect human edits

Assume human edits are intentional and represent the desired direction.

- Never revert files to a pre-human-edit state unless the user explicitly asks.
- Build on top of human changes; do not “clean up” by undoing them.
- If a request conflicts with recent human edits, ask before changing those edits.
