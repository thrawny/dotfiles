### Screenshot and Testing

- When using playwright mcp to take screenshots, always take raw (png) screenshots

### Development Server Management

- Use `tmux-dev-server-control` CLI for managing development server sessions in tmux
- Auto-generates session names: `{foldername}-{command-slug}` (e.g., `asset-simulator-uv-run-main-py`)
- Commands: `start [-d <directory>] <command>`, `stop <session>`, `logs <session>`, `list`, `status`, `monitor <session>`
- Validates commands against allowlist (npm, go, python, docker, etc.)
- Enforces workspace boundaries (default: ~/code) and requires git repositories
- Shows actual error output when commands fail immediately
