---
name: zmx
description: Manage persistent zmx sessions for long-running or resumable terminal work. Use when starting or stopping dev servers, running background tasks, inspecting session logs, waiting for completion, or executing any zmx command.
---

# zmx

Use `zmx` for processes that need persistent scrollback or should survive a shell disconnect.

## Core loop

1. Run `zmx list --short` and determine whether the target session exists.
2. Choose a stable name such as `<project>-web`, `<project>-api`, or `<project>-test`.
3. Perform the requested action using direct command arguments.
4. Inspect history before diagnosing an unexpected exit or recommending a restart.
5. Report whether the session was reused or created and summarize its state or output.

## Commands

```bash
zmx list --short
zmx attach <name> [command...]       # interact; create when missing
zmx run <name> [command...]          # run without attaching; create when missing
zmx history <name>                   # persistent scrollback
zmx history <name> --html            # preserve escape sequences as HTML
zmx history <name> --vt              # preserve VT escape sequences
zmx wait <name>...                    # wait for tasks to complete
zmx kill <name>                       # terminate session and clients
zmx detach                            # detach clients
```

Use `zmx history <name> | tail -n 200` for ordinary log inspection. If a task exits with little output, look for an immediate `ZMX_TASK_COMPLETED:<code>` marker.

## Command construction

Pass a binary and its arguments directly:

```bash
zmx run test go test ./...
zmx run api env DB_NAME=test FEATURE_FLAG=true go run ./cmd/api
zmx run frontend pnpm --dir web dev
```

Use `env` for inline variables. When shell interpretation is genuinely required, invoke a shell explicitly and quote only its expression:

```bash
zmx run mqtt sh -c 'mosquitto_sub -t topic -v | jq .field'
```

A single quoted string is treated as an executable path, so keep ordinary commands in direct-argument form.

## Lifecycle guardrails

- Reuse the existing session for status and log requests.
- If a requested session is missing, report that and ask before starting an unspecified service.
- Kill or detach only when the user explicitly requests it.
- Read history before restarting.
- For a confirmed port conflict, identify the stale listener before terminating it.
- If invocation immediately prints usage, retry once in direct-argument form, then inspect history.
