# Global Claude Code instructions

Use the repository's `AGENTS.md` and `CLAUDE.md` files when present.

Prefer reproducible project commands and the repository task runner over global installs. Use Homebrew only for workstation tools. Use `uv run --with <package>` for one-off Python dependencies and `npx` for one-off Node tools.

Avoid shell parameter names that are special in zsh, including `status`, `history`, `path`, `commands`, and `functions`.

Never inspect or edit `.secrets*`. Use targeted environment-variable checks. Keep persistent services in zmx sessions and run builds, tests, and linters in the foreground.

@~/.claude/CLAUDE.local.md
