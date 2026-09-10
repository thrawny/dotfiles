# Global Codex instructions

Prefer `fd` for file discovery and the repository task runner for checks. Use `uv run --with <package>` for one-off Python dependencies and `npx` for one-off Node tools.

Avoid shell parameter names that are special in zsh, including `status`, `history`, `path`, `commands`, and `functions`.

Never inspect or edit `.secrets*`. Use targeted environment-variable checks. Keep persistent services in zmx sessions and run builds, tests, and linters in the foreground.

## Questions

When clarification is needed, use an available structured question tool that supports the current mode. Prefer asynchronous questions when available, and continue independent work while waiting. If no suitable tool is available, ask in plain text. Never treat an unanswered question as approval.

## Grilling

When grilling, ask one decision at a time using the available question tool, and wait for the answer before asking the next question. This overrides skill instructions to batch questions.
