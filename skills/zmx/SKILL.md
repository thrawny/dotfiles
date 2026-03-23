---
name: zmx
description: Manage persistent terminal sessions with zmx for long-running or resumable commands, including dev server lifecycle tasks. Use proactively whenever zmx commands will be executed (whether user-requested or agent-initiated), and when users ask to start/stop/restart dev servers, inspect logs/history, monitor status, wait for completion, attach/detach sessions, or run background processes that should survive shell disconnects.
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
   - With inline env vars: `zmx run <session> env VAR=value <command...>`
   - Inspect logs: `zmx history <session> | tail -n 200`
   - Wait for completion: `zmx wait <session>`
4. Report whether the session already existed or was created, then summarize output.

## Playbooks

### Start a long-running service

- Prefer stable names like `<project>-api` or `<project>-web`.
- Use `zmx attach <session> <command...>` when interactive monitoring is useful.
- Use `zmx run <session> <command...>` when the user wants fire-and-forget execution.
- For env-var-driven commands, use `env` as the command so zmx passes the vars correctly.
  Example: `zmx run api env DB_NAME=test_db FEATURE_FLAG=true go run ./cmd/foo`
- For commands that need a subdirectory without `cd ... &&`, prefer command-native directory flags.
  Example: `zmx run frontend pnpm --dir web -F @kanel/installer-app dev`

### Check logs or status

- Reuse the existing session for log requests.
- If the session is missing, tell the user and ask whether to start it.
- Use `zmx history <session> | tail -n <N>` (`N=200` by default unless user asks otherwise).
- If a task exits unexpectedly with little/no output, check history for immediate completion markers (for example `ZMX_TASK_COMPLETED:0`) before retrying.

### Stop or disconnect

- Stop sessions when the user explicitly requests it.
- Use `zmx kill <session>` for full teardown.
- Use `zmx detach` to disconnect clients.
- If restart fails due to port conflicts, check and clean up listeners explicitly (`lsof -i :<port>` then terminate stale processes).

## Guardrails

- Kill or detach sessions only with explicit user intent.
- Read history before suggesting restarts.
- Use `zmx history` for logs.
- Prefer direct argument form (`zmx run <name> <command...>`).
- Never wrap the entire command in quotes — zmx takes `[command...]` as separate args and will treat a quoted string as a literal executable path.
- For subcommand args that need shell interpretation (pipes, `&&`, globbing), quote only that specific argument: `zmx run s cmd --flag 'sub1 && sub2'`.
- Keep session naming consistent within a task and use one session per service.

## Command form checklist

Before running a command, ask:
- Use direct args when invoking one binary with normal flags/args.
- Only quote the specific argument that needs shell interpretation, not the whole command: `zmx run s watchexec -- 'cmd1 && cmd2'`.
- For inline env vars, use `env` as the command: `zmx run s env VAR=val command args...`.

## Examples

- SSH tunnel:
  `zmx run tunnel ssh -N -L 8888:localhost:8888 user@host`
- MQTT subscriber:
  `zmx run mqtt mosquitto_sub -h broker.example.com -t sensors/# -v`
- MQTT subscriber with pipe (quote only the shell expression):
  `zmx run mqtt sh -c 'mosquitto_sub -h localhost -p 1883 -t topic -v | jq .field'`
- Go tests:
  `zmx run test go test ./...`
- Tail a logfile:
  `zmx run logs tail -f /var/log/system.log`

## Failure handling

- If a command exits immediately with usage/help output, retry once in direct-arg form before any other debugging.
- If it still fails, inspect `zmx history <session> | tail -n 200` and check argument ordering/quoting.
