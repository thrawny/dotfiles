---
name: zmx
description: Manage persistent zmx sessions for long-running or resumable terminal work. Use when starting or stopping dev servers, running background tasks, inspecting session logs, waiting for completion, or executing any zmx command.
---

# zmx

Use `zmx` for processes that need persistent scrollback or should survive a shell disconnect.

## Core loop

1. Run `zmx list --short` and determine whether the target session exists.
2. Choose a stable name such as `<project>-web`, `<project>-api`, or `<project>-test`.
3. Select the execution mode:
   - Run and observe a finite command: `zmx run <name> <command...>`
   - Start detached work: `zmx run <name> -d <command...>`
   - Inspect a snapshot: `zmx history <name> | tail -n 200`
   - Follow live output: `zmx tail <name>`
   - Supply input to an interactive process: `zmx send <name> <text...>`
   - Transfer a file through an SSH shell inside a session: `zmx write <name> <path>`
4. Verify the requested outcome from the command's exit status, `wait`, session history, or current session list.
5. Report whether the session was reused or created and summarize the evidence.

## Run, detach, and wait

`run` is synchronous by default: it follows output and returns the task's aggregate exit status.

```bash
zmx run test go test ./...
zmx run api env DB_NAME=test FEATURE_FLAG=true go run ./cmd/api
zmx run frontend pnpm --dir web test
```

Pass the binary and ordinary arguments directly. Use `env` for inline variables. A single quoted command is treated as an executable path. When shell interpretation is genuinely required, invoke a shell explicitly and quote only its expression:

```bash
zmx run mqtt sh -c 'mosquitto_sub -t topic -v | jq .field'
```

Use detached mode when the caller should return before the command exits:

```bash
zmx run build -d make all
zmx wait build
```

Use `wait` for finite tasks you detached manually; it returns their result and includes recent output for failures. Do not run `zmx wait` for a `pi-bg-*` session created by Pi's Bash tool with `background: true`: the harness already owns that wait and will wake the agent on completion. Continue independent work or end the turn instead. Use `history` only when diagnosing such a session after an early timeout wake-up or when the user explicitly asks to inspect it. For a long-running service, inspect startup through `history` or `tail` instead of waiting for it to exit.

## Observe sessions

Use `history` for a bounded snapshot and `tail` for intentional live monitoring:

```bash
zmx history web | tail -n 200
zmx history web --html
zmx history web --vt
zmx tail web
```

`tail` follows output until interrupted, so prefer `history` for ordinary status checks.

## Interactive input

Use `send` only when an existing shell, prompt, or TUI is waiting for input. It sends raw bytes without appending Enter, recording completion, or tracking an exit status.

```bash
printf 'yes\r' | zmx send deploy
zmx send app "$(printf '\x03')"  # Ctrl-C
```

Inspect history first so the input matches the process's current state. Append `\r` when the shell should execute the text. Prefer `run` for commands whose completion matters.

## File transfer through an SSH shell

`write` is useful when a zmx session is currently sitting at a remote shell prompt opened through SSH:

```bash
zmx attach remote-app ssh user@example.com
cat config.json | zmx write remote-app ./config.json
```

Zmx base64-encodes the input and injects decoding commands into the session PTY, which SSH forwards to the remote shell. Relative paths therefore resolve from that shell's current directory.

Use `write` only while the session is at a shell prompt; otherwise the injected commands go to whichever interactive process owns the PTY. The remote host needs `base64` and `printf`, and the path cannot contain a single quote. The acknowledgement confirms that zmx queued the commands, so verify the resulting file separately.

Encoded content may appear in scrollback or logs. Use a dedicated secure transfer mechanism for secrets, and ordinary file tools for local files.

## Lifecycle and diagnostics

```bash
zmx attach <name> [command...]       # interactive user takeover; create if missing
zmx print <name> <text...>           # annotate display/scrollback; never process input
zmx kill <name>... [--force]         # terminate sessions and clients
zmx detach                            # detach clients
zmx version                           # version, socket directory, and log directory
zmx help                              # version-matched command reference
```

- Reuse an existing session for status and log requests.
- If a requested session is missing, report that and ask before starting an unspecified service.
- Use `attach` only when an interactive terminal is available or the user explicitly wants to take over.
- Kill or detach only with explicit user intent.
- Read history before restarting or sending interactive input.
- Prefix matching for `kill`, `wait`, and `tail` requires an explicit `*` suffix.
- For a confirmed port conflict, identify the stale listener before terminating it.
- If invocation prints usage, consult `zmx help`, correct the argument order, and retry once.
