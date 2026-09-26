# T3 Code from agents and scripts

`bin/t3ctl` controls the running T3 Code server on obelisk. It requires Python 3 and SSH access to `root@obelisk`. It uses the server's existing HTTP API without additional packages.

```sh
t3ctl projects
t3ctl threads --project dotfiles

receipt=$(t3ctl start dotfiles - --model gpt-6-sol < task.md)
thread=$(printf '%s' "$receipt" | jq -r .threadId)
message=$(printf '%s' "$receipt" | jq -r .messageId)
t3ctl wait "$thread" --message-id "$message" --timeout 300

t3ctl show "$thread" | jq '.messages[] | select(.role == "assistant") | .text'
t3ctl send "$thread" 'Now review the changes'
t3ctl interrupt "$thread"
t3ctl archive "$thread"
```

All successful commands write JSON to stdout. Errors go to stderr. `start` and `send` return a command receipt, not a completed answer. Use their `messageId` with `wait` to avoid mistaking the previous turn's completion for the new result.

`wait` returns the thread with its server-reported `state`. Exit codes are 0 for completion, 1 for errors or reported interruption, 2 when approval or user input is needed, and 124 for timeout. A timeout does not interrupt the agent. Run waits in the background when calling from an interactive coding agent.

Completion does not prove the requested work succeeded. During the initial test on `0.0.39-nightly.20260905.1287`, the server marked an interrupted turn as `completed`. Inspect the messages and activities before treating a result as successful.

## Permissions and workspace

New threads default to `approval-required`. Use `--runtime-mode full-access` only when you intend to allow unattended execution. `--mode plan` starts a planning conversation. `send` preserves the thread's provider, model, and modes, and refuses busy, blocked, or archived threads. This check is not a server-side lock; avoid simultaneous writers to the same thread.

`start` uses the project's existing checkout, **not a new Git worktree**. For isolated work, create and register a separate checkout first. Projects resolve by exact ID, server path, or unique title. A model must be supplied unless the project has an explicit default. `--provider` selects a provider instance and defaults to `codex` when `--model` is supplied.

`show` includes messages and activities. The initially tested `0.0.39` server omitted archived threads from `threads` and returned 404 for `show` after archiving. Unarchive through the UI or a raw `thread.unarchive` command before reading them again.

Answer approvals or questions through the UI, or use `dispatch` with the matching request ID:

```sh
t3ctl dispatch '{"type":"thread.approval.respond","threadId":"...","requestId":"...","decision":"accept","createdAt":"2026-09-23T12:00:00Z"}'
```

`dispatch` accepts a JSON object or `-` for stdin, and adds a UUID `commandId` when absent. It does not validate provider-specific payloads. See the server's [orchestration contracts](https://github.com/pingdotgg/t3code/blob/main/packages/contracts/src/orchestration.ts).

## Connection and compatibility

SSH runs the client as the `t3code` service user and calls `127.0.0.1:3773`. Each invocation issues a bearer session through `t3 auth session issue`, then revokes it on exit. Tokens never leave the server or enter command arguments. The installed T3 CLI issues administrative scopes, not narrower read/operate scopes. Tokens also expire after the wait timeout plus two minutes, or two minutes for other commands, if the client is killed before cleanup.

Use `--host root@HOST` or `T3CTL_HOST` to choose another similarly configured server. Global `--port` and `--base-dir` options must precede the command. SSH host-key verification stays enabled. No public listener, stored bearer token, or database edits are needed.

Tested against obelisk's `0.0.39-nightly.20260905.1287` and, after deployment, `0.0.43-nightly.20260923.2150`. This uses the V1 HTTP API. API compatibility is not guaranteed across upgrades.

The initial test completed a prompt and follow-up with `gpt-6-astra`. After updating Codex from `0.154.0` to `0.157.1`, a live `gpt-6-sol` prompt completed successfully through T3 Code. The older Codex binary had rejected Sol 6 as unsupported with the same ChatGPT account. Dispatch acceptance alone does not imply the provider accepted the model.

The CLI never automatically retries a failed mutation. A connection failure can happen after the server commits a command. Inspect the thread before resending. Raw dispatch can reuse a known command ID for an identical retry, never for a different payload.
