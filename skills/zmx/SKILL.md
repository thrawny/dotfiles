---
name: zmx
description: Manage persistent terminal sessions with zmx for long-running or resumable commands, including dev server lifecycle tasks. Use when users mention zmx directly or ask to start/stop/restart dev servers, inspect logs/history, monitor status, wait for completion, attach/detach sessions, or run background processes that should survive shell disconnects.
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
   - Start or attach interactively: `zmx attach <session> <command...>`
   - Send command without attaching: `zmx run <session> <command...>`
   - With inline env vars: `VAR=value zmx run <session> <command...>`
   - Inspect logs: `zmx history <session> | tail -n 200`
   - Wait for completion: `zmx wait <session>`
4. Report whether the session already existed or was created, then summarize output.

## Playbooks

### Start a long-running service

- Prefer stable names like `<project>-api` or `<project>-web`.
- Use `zmx attach <session> <command...>` when interactive monitoring is useful.
- Use `zmx run <session> <command...>` when the user wants fire-and-forget execution.
- For env-var-driven commands, prefix env vars before `zmx` so the subprocess inherits them.
  Example: `DB_NAME=test_db FEATURE_FLAG=true zmx run api go run ./cmd/foo`
- For commands that need a subdirectory without `cd ... &&`, prefer command-native directory flags.
  Example: `zmx run frontend pnpm --dir web -F @kanel/installer-app dev`

### Check logs or status

- Do not create a new session for log requests.
- If the session is missing, tell the user and ask whether to start it.
- Use `zmx history <session> | tail -n <N>` (`N=200` by default unless user asks otherwise).
- If a task exits unexpectedly with little/no output, check history for immediate completion markers (for example `ZMX_TASK_COMPLETED:0`) before retrying.

### Stop or disconnect

- Stop only when explicitly requested.
- Use `zmx kill <session>` for full teardown.
- Use `zmx detach` only to disconnect clients, not to stop the process.
- If restart fails due to port conflicts, check and clean up listeners explicitly (`lsof -i :<port>` then terminate stale processes).

## Guardrails

- Do not kill or detach sessions without explicit user intent.
- Read history before suggesting restarts.
- Use `zmx history` for logs (there is no `zmx logs` command).
- Prefer direct argument form (`zmx run <name> <command...>`). Use `sh -lc '...'` only when shell syntax is required (pipes, redirects, `&&`, globbing).
- Keep session naming consistent within a task; avoid duplicate sessions for the same service.
