---
allowed-tools: Bash(tmux-dev-server-control:*)
argument-hint: action and session name (e.g., "start my-app npm run dev", "logs my-app 50", "stop my-app")
description: Manage development servers running in tmux sessions
model: claude-haiku-4-5-20251001
---

Manage dev servers. All processes run as windows in a single `dev` tmux session. Window names are auto-generated from directory + command.

**Commands:**
- `start <command>` - Start a dev server (name auto-generated)
- `stop <name>` - Stop a window
- `logs <name> [lines]` - View logs (default: 50 lines)
- `list` - List all dev server windows

**Examples:**
```bash
# In project directory - name is auto-generated
tmux-dev-server-control start npm run dev        # -> myapp-npm-dev
tmux-dev-server-control start go run ./cmd/api/main.go  # -> backend-go-api

tmux-dev-server-control logs myapp-npm-dev 100
tmux-dev-server-control stop myapp-npm-dev
tmux-dev-server-control list
```

User can `tmux attach -t dev` to tab between all processes.

Parse the user's arguments and run the appropriate command. If no arguments, run `list`.
