---
name: zmx
description: Manage persistent terminal sessions with zmx for long-running or resumable commands. Use when users mention zmx directly or ask to start, monitor, attach to, inspect logs/history for, wait on, detach from, or stop background processes that should survive shell disconnects.
---

# zmx

Use `zmx` to run and manage session-based processes with persistent scrollback.

## Command reference

```bash
zmx list --short                         # List active sessions (short names)
zmx attach <name> [command...]           # Attach to session; create if missing
zmx run <name> [command...]              # Send command without attaching; create if missing
zmx history <name>                       # Print scrollback
zmx history <name> --html                # Scrollback with escape sequences preserved
zmx history <name> --vt                  # Scrollback with VT escape sequences
zmx wait <name>...                       # Wait for one or more session tasks to complete
zmx kill <name>                          # Kill a session and attached clients
zmx detach                               # Detach clients from current session
```

## Standard workflow

1. Run `zmx list --short` first.
2. Resolve the target session name.
3. Choose the action:
   - Start or attach interactively: `zmx attach <session> sh -lc '<command>'`
   - Send command without attaching: `zmx run <session> sh -lc '<command>'`
   - Inspect logs: `zmx history <session> | tail -n 200`
   - Wait for completion: `zmx wait <session>`
4. Report whether the session already existed or was created, then summarize output.

## Playbooks

### Start a long-running service

- Prefer stable names like `<project>-api` or `<project>-web`.
- Use `zmx attach <session> sh -lc '<command>'` when interactive monitoring is useful.
- Use `zmx run <session> sh -lc '<command>'` when the user wants fire-and-forget execution.

### Check logs or status

- Do not create a new session for log requests.
- If the session is missing, tell the user and ask whether to start it.
- Use `zmx history <session> | tail -n <N>` (`N=200` by default unless user asks otherwise).

### Stop or disconnect

- Stop only when explicitly requested.
- Use `zmx kill <session>` for full teardown.
- Use `zmx detach` only to disconnect clients, not to stop the process.

## Guardrails

- Do not kill or detach sessions without explicit user intent.
- Read history before suggesting restarts.
- Wrap complex commands in `sh -lc '...'` to preserve quoting, pipes, and env expansion.
- Keep session naming consistent within a task; avoid duplicate sessions for the same service.
