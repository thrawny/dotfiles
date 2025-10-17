---
allowed-tools: Bash(tmux:*), Bash(pwd:*), Bash(ls:*), Read, Grep
argument-hint: action and session name (e.g., "start my-app npm run dev", "logs my-app 50", "stop my-app")
description: Manage development servers running in tmux sessions
model: claude-haiku-4-5-20251001
---

## Context

! Check if tmux is available
```bash
which tmux
```

! List current tmux sessions
```bash
tmux list-sessions 2>/dev/null || echo "No active sessions"
```

! Get current working directory
```bash
pwd
```

## Your task

Based on the command arguments, manage tmux development sessions. Follow these guidelines:

1. **Parse the command arguments**:
   - First argument is the action: `start`, `logs`, `monitor`, `list`, `stop`
   - Second argument is the session name (required for most actions)
   - Additional arguments depend on the action:
     - `start`: Remaining args form the command to run
     - `logs`: Optional number of lines (default: 50)
     - Other actions: No additional args needed

2. **Handle the 'start' action**:
   - Extract session name and command from arguments
   - Check if session already exists with `tmux has-session -t [session-name]`
   - If session exists, inform user and ask if they want to kill and restart
   - Create new detached session: `tmux new-session -d -s [session-name] -c $(pwd) '[command]'`
   - Verify session was created successfully
   - Provide feedback with session name and command

3. **Handle the 'logs' action**:
   - Check if session exists
   - Extract number of lines (default: 50)
   - Capture pane content: `tmux capture-pane -t [session-name] -p | tail -[N]`
   - Display the logs to user
   - If session doesn't exist, list available sessions

4. **Handle the 'monitor' action**:
   - Check if session exists
   - Inform user about attaching to session
   - Provide detach instructions (Ctrl+B then D)
   - Execute: `tmux attach -t [session-name]`
   - Note: This will transfer control to the tmux session

5. **Handle the 'list' action**:
   - Run `tmux list-sessions`
   - Format output for better readability
   - If no sessions exist, inform user

6. **Handle the 'stop' action**:
   - Check if session exists
   - Kill the session: `tmux kill-session -t [session-name]`
   - Confirm session was stopped
   - List remaining sessions

7. **Error handling and validation**:
   - If tmux is not installed, provide installation instructions
   - If no action provided, display usage examples
   - If session name is required but missing, prompt user
   - Handle cases where session doesn't exist gracefully
   - Provide helpful error messages for common issues

**Usage examples**:
- `/tmux-dev start my-app npm run dev` - Start Next.js dev server
- `/tmux-dev logs my-app 100` - Show last 100 lines from my-app session
- `/tmux-dev monitor my-app` - Attach to my-app session for real-time monitoring
- `/tmux-dev list` - Show all running sessions
- `/tmux-dev stop my-app` - Stop the my-app session

**Action-specific behaviors**:
- **start**: Creates detached session in current directory with specified command
- **logs**: Shows recent output without interrupting the session
- **monitor**: Attaches to session for interactive monitoring (user can detach)
- **list**: Shows all sessions with their status
- **stop**: Cleanly terminates the specified session

If no arguments provided, display usage information and list current sessions.