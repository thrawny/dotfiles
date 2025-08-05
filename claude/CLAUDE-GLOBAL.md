### Screenshot and Testing

- When using playwright mcp to take screenshots, always take raw (png) screenshots

### Development Server Management

- Use the `dev-server-controller` agent for managing tmux development sessions across multiple projects
- The agent uses `tmux-workspace-control` wrapper with auto-generated session names: `{foldername}-{command-slug}`
- Start sessions: `tmux-workspace-control start [-d <directory>] <command>`
- Supports multi-project workflows (backend + frontend + services)
- Enforces workspace boundaries (default: ~/code) and validates commands per project type
