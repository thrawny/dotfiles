---
name: zmx
description: Manage persistent zmx sessions from Pi for long-running services, resumable terminal work, session inspection, input, and lifecycle. Use when starting or stopping dev servers, operating an existing zmx session, or choosing between managed Background Bash and manual zmx.
---

# zmx in Pi

Choose one owner for each process. Pi's Background Bash owns finite asynchronous work; direct zmx sessions own persistent or interactive work.

## Choose the owner

| Work | Owner |
|---|---|
| Short finite command | Foreground Bash |
| Long finite command, waiter, or monitor | Bash with `background: true` |
| Persistent service or interactive process | Direct zmx session |
| Inspection or control of an existing zmx session | Direct zmx command |

Make this choice before launch. A process has one owner when its completion or lifecycle is managed by exactly one path.

## Managed Background Bash

Run the underlying finite command directly with Bash `background: true`. The harness creates the `pi-bg-*` zmx session, returns control immediately, waits internally, and notifies Pi on completion.

After launch, continue independent work or end the turn. On an early timeout wake-up, inspect a bounded snapshot only when needed:

```bash
zmx history <pi-bg-session> | tail -n 200
```

A managed task is correctly launched when the underlying command was started once and no second waiter was created.

## Persistent zmx sessions

Start a service detached, then inspect enough history to verify startup:

```bash
zmx list --short
zmx run <name> -d <command...>
zmx history <name> | tail -n 200
```

Return control while the service runs. Pair detached sessions with bounded history snapshots rather than foreground `zmx wait` or `zmx tail` calls.

Pass the binary and ordinary arguments directly. Use `env` for inline variables. When shell interpretation is required, invoke a shell explicitly:

```bash
zmx run mqtt -d sh -c 'mosquitto_sub -t topic -v | jq .field'
```

## Session control

```bash
zmx history <name> | tail -n 200
zmx send <name> <text...>
zmx kill <name>... [--force]
zmx detach
zmx help
```

- Inspect history before sending input so it matches the process state.
- `send` writes raw bytes; append `\r` when a shell should execute the text.
- Use `attach` only when the user explicitly wants interactive takeover.
- Kill or detach only with explicit user intent.
- If invocation prints usage, consult `zmx help`, correct it, and retry once.
- Prefix matching for `kill`, `wait`, and `tail` requires an explicit `*` suffix.

## File transfer through an SSH session

When an existing zmx session is idle at a remote shell prompt:

```bash
cat config.json | zmx write <name> ./config.json
```

The remote host needs `base64` and `printf`; the path cannot contain a single quote. Verify the resulting file separately. Use a dedicated secure transfer mechanism for secrets because encoded content may appear in scrollback.
