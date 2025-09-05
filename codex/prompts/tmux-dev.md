## Context

Check if tmux is available:
```bash
which tmux
```

List current tmux sessions:
```bash
tmux list-sessions 2>/dev/null || echo "No active sessions"
```

Get current working directory:
```bash
pwd
```

## Your task

Based on the command arguments, manage tmux development sessions. Actions: `start`, `logs`, `monitor`, `list`, `stop`.

1. Parse arguments:
   - First: action.
   - Second: session name (required for most actions).
   - Additional by action:
     - `start`: remaining args form the command to run.
     - `logs`: optional number of lines (default 50).
2. Handle `start`:
   - If session exists (`tmux has-session -t <name>`), ask before restarting.
   - Create detached: `tmux new-session -d -s <name> -c $(pwd) '<command>'`.
3. Handle `logs`:
   - If exists, show: `tmux capture-pane -t <name> -p | tail -<N>`.
   - If absent, list sessions.
4. Handle `monitor`:
   - Attach: `tmux attach -t <name>` and remind how to detach (Ctrl+B then D).
5. Handle `list`:
   - Run `tmux list-sessions`; if none, say so.
6. Handle `stop`:
   - Kill: `tmux kill-session -t <name>`; then list remaining sessions.
7. Error handling:
   - If tmux missing, provide install hint.
   - If required args missing, show usage.
   - Handle nonexistent sessions gracefully.

Usage examples:
- `/tmux-dev start my-app npm run dev`
- `/tmux-dev logs my-app 100`
- `/tmux-dev monitor my-app`
- `/tmux-dev list`
- `/tmux-dev stop my-app`

