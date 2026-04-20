---
name: notify
description: >
  Use the local `notify` CLI to send a desktop notification when work finishes
  or reaches a requested condition. Trigger only when the user explicitly asks
  to notify, ping, or alert them later. Do not use proactively for ordinary
  long-running tasks unless the user asked for a notification.
---

# notify

Use `notify` for end-of-task desktop notifications.

## Command

```bash
notify "message"
notify --sound "message"
```

The notification title is set automatically from the current directory name.

## Guidelines

- Use this only after an explicit user request to notify later.
- Notify on completion, failure, or the requested state change.
- Prefer one final notification over noisy progress notifications.
- Keep the message short and outcome-focused.
- Use `--sound` only when the user asks for it.
- Good fit for polling loops: check condition, sleep, repeat, then `notify` before exiting.

## Examples

```bash
notify "CI passed"
notify "Tests failed"
notify --sound "Build finished"
```
