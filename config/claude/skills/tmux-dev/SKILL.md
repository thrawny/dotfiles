---
name: tmux-dev
description: Manage development servers running in tmux. Use when starting, stopping, or monitoring dev servers (npm, go, python, docker, etc.). Triggers on requests like "start the dev server", "check if the server is running", "show server logs", "stop the backend", or any dev server lifecycle management.
---

# tmux-dev

Manage dev servers as windows in a single `dev` tmux session.

## Commands

```bash
tmux-dev start -n <name> <command>  # Start or restart (requires approval)
tmux-dev stop <name>                # Stop a window
tmux-dev status <name>              # Check running/exited
tmux-dev logs <name> [lines]        # View logs (default: 50)
tmux-dev list                       # List all with status
```

## Workflow

1. Run `tmux-dev list` to see existing servers
2. Start servers from project directory: `cd /path/to/project && tmux-dev start -n frontend npm run dev`
3. Check health with `status`, view output with `logs`
4. Re-running `start` with same name restarts the server

## Output Format

**start** outputs `WINDOW_NAME: <name>` for parsing, then streams 10s of logs.

**status** outputs: `<name>: running` or `<name>: exited (code N)`

**list** outputs:
```
Dev server windows (session: dev):
  frontend                       running
  api                            exited (code 1)
```
