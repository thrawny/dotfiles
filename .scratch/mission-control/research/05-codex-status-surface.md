# Codex CLI: machine-readable session/status surfaces (no terminal scraping)

**Question:** what authoritative, machine-readable session/status surface does OpenAI Codex CLI expose that a local status producer could consume without scraping the terminal?

**Verified against:** locally installed `codex-cli 0.146.0` (`/etc/profiles/per-user/thrawny/bin/codex`, Nix store `/nix/store/56q67z8vx9i7mq06rapq04cdxbfn6maq-codex-0.146.0`), the generated protocol JSON Schema from that exact binary (`codex app-server generate-json-schema --out DIR`), a partial clone of `openai/codex` at tag `rust-v0.146.0` (commit `e363b08c9175ac1cbe5893615dd2cb9ddf95043b`), live experiments against the local binary, and official docs at `developers.openai.com/codex`. Date: 2026-08-03.

Everything below is either (a) read out of the schema the local binary itself generates, (b) read out of 0.146.0 Rust source, or (c) observed in a live run. Nothing is from secondhand prose.

---

## TL;DR — recommended producer design

**There is no equivalent of Claude Code's `~/.claude/sessions/<pid>.json`. Codex never persists thread status to disk — `ThreadStatus` lives only in `Arc<Mutex<ThreadWatchState>>` in the app-server process and is not written to `state_5.sqlite` or the rollout files.** So a producer cannot poll a file for `busy|waiting|idle`; it has to either be *pushed* status or *infer* it.

Two viable designs, and they are complementary rather than competing:

### Primary: hooks → producer writes its own state file (the Claude-Code-shaped path)

Codex 0.146.0 has a full Claude-Code-compatible hooks engine with **11 events**, JSON-on-stdin payloads carrying `session_id`, `cwd`, `turn_id`, `transcript_path`, and it **fires in `codex exec` as well as the TUI**. The state machine you want falls straight out:

| Hook event | Producer state |
|---|---|
| `SessionStart` | register session (`session_id`, `cwd`, pid via `$PPID`) |
| `UserPromptSubmit` | `busy` |
| `PermissionRequest` | `waiting` (needs-input) |
| `Stop` | `idle` |
| `SessionEnd` | deregister |

This is the same shape this repo already uses — `config/codex/hooks.agent-switch.json` wires `SessionStart` / `UserPromptSubmit` / `Stop` to `agent-switch track`. Adding `PermissionRequest` and `SessionEnd` closes the state machine. It is the only option that works for a **default `codex` TUI with no daemon** and for `codex exec`, which is most real usage.

Cost: the producer owns liveness itself (there is no heartbeat), and hooks are trust-gated (see caveats).

### Secondary: app-server `thread/status/changed` broadcast (authoritative, richest, but narrow applicability)

This is the *authoritative* status surface and it is genuinely broadcast: **a third-party observer process that merely connects and calls `initialize` receives `thread/status/changed` for threads it did not create, with zero conversation content leakage.** Verified empirically (see candidate 2). It gives you exactly the four states you want, natively:

```
notLoaded | idle | systemError | active { activeFlags: ["waitingOnApproval" | "waitingOnUserInput"] }
```

But it only sees threads running *inside that app-server process*. `codex exec` is standalone and `codex` TUI is `Embedded` by default. It becomes broadly useful only if a daemon is running (a bare `codex` then silently auto-adopts it — see candidate 2.4), and `codex app-server daemon start` **is broken on a Nix install** (verified). So treat this as a high-fidelity opt-in upgrade, not the baseline.

### Recommendation

Build the producer on **hooks**, and structure it so the app-server observer can be layered in later as an optional high-fidelity source keyed by `thread_id` (hooks give you `session_id`, which equals the thread id — the rollout `session_meta` carries both `session_id` and `id` and they are the same UUIDv7). Use the **rollout JSONL tail** as a cross-check/recovery oracle only, not as the live signal.

Explicitly do **not** build on `notify` (single event, argv-not-stdin, silently dies on long threads) or `tui.notifications` (pure OSC 9 / BEL escapes, nothing machine-readable).

---

## Candidate 1 — Session/state files under `~/.codex`

### 1.1 `~/.codex/sessions/YYYY/MM/DD/rollout-<ISO8601>-<uuid>.jsonl`

Verified shape: every line is `{"type": ..., "payload": ..., "timestamp": ...}` — 38/38 lines in a sampled file had exactly those three keys.

Top-level `type` distribution across all rollouts newer than 2026-07-01 (401 session files total in `~/.codex/sessions`):

| `type` | count |
|---|---|
| `response_item` | 19097 |
| `turn_context` | 229 |
| `world_state` | 122 |
| `session_meta` | 96 |
| `compacted` | 14 |
| `event_msg` | (see below) |

`event_msg` `payload.type` distribution — **this is the status-bearing subset**:

| `payload.type` | count |
|---|---|
| `token_count` | 6024 |
| `agent_reasoning` | 5613 |
| `agent_message` | 1106 |
| `patch_apply_end` | 719 |
| `user_message` | 219 |
| **`task_started`** | **216** |
| **`task_complete`** | **204** |
| `thread_settings_applied` | 103 |
| `web_search_end` | 26 |
| `context_compacted` | 14 |
| `mcp_tool_call_end` | 12 |
| **`turn_aborted`** | **11** |
| `thread_rolled_back` | 1 |

`task_started` (216) ≈ `task_complete` (204) + `turn_aborted` (11) = 215, i.e. the pairing is essentially exact — one unterminated turn, consistent with a crash or an in-flight session.

`session_meta.payload` field types (keys only, no content read): `session_id`(str), `id`(str), `timestamp`(str), `cwd`(str), `originator`(str), `cli_version`(str), `source`(str), `model_provider`(str), `base_instructions`(obj), `history_mode`(str), `context_window`(obj), `git`(obj).

**Is it written live during a turn? YES — verified.** I launched `codex exec --json ... "run sleep 25 && echo hello, then reply DONE"` and polled the newest rollout file 12 s in, mid-turn. It already contained `session_meta`, `turn_context`, `world_state`, `event_msg/user_message`, **`event_msg/task_started`**, `event_msg/agent_message`, and a `response_item/custom_tool_call` — and *no* `task_complete`. So `task_started` is flushed immediately and a tailer sees turn boundaries in real time.

**Does it encode status?** Partially, and by inference only:

- working → `task_started` seen with no matching `task_complete` / `turn_aborted`
- done → `task_complete`
- failed/aborted → `turn_aborted` (also covers user interrupt — not distinguishable from failure here)
- **needs-input → NOT REPRESENTED.** There is no approval-request event in the rollout stream. The rollout persists only a filtered subset of `EventMsg` (note the absence of `exec_command_begin`/`exec_command_end` — only the `*_end` variants for patch/web-search/MCP survive). An approval prompt is invisible to a rollout tailer.
- there is **no** status/state field anywhere; it is an append-only transcript.

**Liveness:** no pid, no heartbeat, nothing. `session_meta` has no pid field. A stale `task_started` with no terminator is indistinguishable from a live long turn except by file mtime heuristics. This is the surface's fatal weakness for a status producer.

**Headless:** works identically for `codex exec` (my live test above *was* `codex exec`).

**Caveats:** privacy — the rollout contains full conversation content, so a producer tailing it must be scoped to reading `type`/`payload.type` only. Files are large (up to 7 MB observed for one session). Path layout is date-sharded, so "find the newest rollout" requires a directory walk or the sqlite index below.

### 1.2 `~/.codex/state_5.sqlite`

Tables: `threads`, `thread_dynamic_tools`, `thread_spawn_edges`, `backfill_state`, `remote_control_enrollments`, `external_agent_config_imports`, `_sqlx_migrations`.

`threads` columns (full): `id`, `rollout_path`, `created_at`, `updated_at`, `source`, `model_provider`, `cwd`, `title`, `sandbox_policy`, `approval_mode`, `tokens_used`, `has_user_event`, `archived`, `archived_at`, `git_sha`, `git_branch`, `git_origin_url`, `cli_version`, `first_user_message`, `agent_nickname`, `agent_role`, `memory_mode`, `model`, `reasoning_effort`, `agent_path`, `created_at_ms`, `updated_at_ms`, `thread_source`, `preview`, `recency_at`, `recency_at_ms`, `history_mode`, `name`, `is_pinned`.

**There is no `status` column.** This confirms at the schema level what the source says: thread status is never persisted. What you *do* get is a fast index — `rollout_path` per thread id, `cwd`, `updated_at_ms`, `model`, `source` — which is genuinely useful for resolving "which rollout belongs to which thread in which directory" without walking the date shards. `thread_spawn_edges` has a `status TEXT` column but that is subagent spawn bookkeeping, not turn status.

Useful for: enumerating known threads, mapping thread → rollout path → cwd, coarse activity via `updated_at_ms`. Not useful for busy/waiting/idle.

Live-written (mtime tracked the running session; WAL files active). Read it read-only with `PRAGMA query_only` / immutable URI to avoid contending with codex's writer.

### 1.3 Other files

- `~/.codex/logs_2.sqlite` (113 MB, actively written) — `logs(id, ts, ts_nanos, level, target, feedback_log_body, module_path, file, line, thread_id, process_uuid, estimated_bytes)`. Tracing logs keyed by `thread_id` and `process_uuid`. Could in principle serve as a liveness proxy (a live process writes rows) but it is a diagnostics sink, not a contract; large; and `process_uuid` is not a pid. Not recommended.
- `~/.codex/history.jsonl` — user prompt history, no status.
- `~/.codex/session_index.jsonl` — stale (last modified 2026-06-04), superseded by `state_5.sqlite`.
- `~/.codex/app-server-control/`, `~/.codex/app-server-daemon/` — daemon socket/pid/lock dir; see candidate 2.

---

## Candidate 2 — app-server / ACP protocol

This is the authoritative surface. The local binary self-documents it: `codex app-server generate-json-schema --out DIR` (and `generate-ts` for TypeScript bindings). That produced 36 top-level schema files plus `codex_app_server_protocol.schemas.json` (590 KB) and a `v2/` directory of per-message schemas.

Transport (`codex app-server --listen <URL>`): `stdio://` (default), `unix://[PATH]`, `ws://IP:PORT`, `off`.

### 2.1 The status surface itself

`ThreadStatus` (from `ServerNotification.json`, generated by the local 0.146.0 binary) is a tagged union of exactly four variants:

```json
notLoaded
idle
systemError
active { activeFlags: ThreadActiveFlag[] }
```

and `ThreadActiveFlag` is a closed enum of exactly two values:

```json
["waitingOnApproval", "waitingOnUserInput"]
```

`ThreadStatusChangedNotification` = `{ threadId: string, status: ThreadStatus }` — required fields, no optionals.

**All four target states are natively distinguishable:**

| Wanted state | Codex representation |
|---|---|
| working | `active` with `activeFlags: []` |
| needs-input | `active` with `activeFlags` containing `waitingOnApproval` or `waitingOnUserInput` |
| done / idle | `idle` |
| failed | `systemError` (thread-level); per-turn failure via `TurnStatus` |

`TurnStatus` is a separate closed enum: `["completed", "interrupted", "failed", "inProgress"]`, and `Turn.error` is "only populated when the Turn's status is `failed`". `Turn` also carries `startedAt`, `completedAt`, `durationMs`. So turn-level granularity distinguishes user-interrupt from genuine failure — something the rollout's single `turn_aborted` cannot.

`Thread` objects (returned by `thread/start`, `thread/list`, `thread/read`) include a `status` field directly, so status is also **pollable**, not just push-only. Verified live: `thread/list` returned `{"id":"019fc7e8-…","status":{"type":"notLoaded"},"cwd":"/home/thrawny/dotfiles","source":"vscode"}`.

`Thread` properties (full): `agentNickname`, `agentRole`, `cliVersion`, `createdAt`, `cwd`, `ephemeral`, `forkedFromId`, `gitInfo`, `id`, `isPinned`, `modelProvider`, `name`, `parentThreadId`, `path`, `preview`, `recencyAt`, `sessionId`, `source`, `status`, `threadSource`, `turns`, `updatedAt`.

### 2.2 Full notification surface

70 `ServerNotification` methods in 0.146.0 (extracted from the binary's own schema). Lifecycle/status-relevant ones in bold:

**`error`**, **`thread/started`**, **`thread/status/changed`**, `thread/archived`, `thread/deleted`, `thread/unarchived`, **`thread/closed`**, `skills/changed`, `thread/name/updated`, `thread/goal/updated`, `thread/goal/cleared`, `thread/environment/connected`, `thread/environment/disconnected`, `thread/settings/updated`, `thread/tokenUsage/updated`, **`turn/started`**, `hook/started`, **`turn/completed`**, `hook/completed`, `turn/diff/updated`, `turn/plan/updated`, `item/started`, `item/autoApprovalReview/started`, `item/autoApprovalReview/completed`, `item/completed`, `item/agentMessage/delta`, `item/plan/delta`, `command/exec/outputDelta`, `process/outputDelta`, `process/exited`, `item/commandExecution/outputDelta`, `item/commandExecution/terminalInteraction`, `item/fileChange/outputDelta`, `item/fileChange/patchUpdated`, `serverRequest/resolved`, `item/mcpToolCall/progress`, `mcpServer/oauthLogin/completed`, `mcpServer/startupStatus/updated`, `account/updated`, `account/rateLimits/updated`, `app/list/updated`, `remoteControl/status/changed`, `externalAgentConfig/import/progress`, `externalAgentConfig/import/completed`, `fs/changed`, `item/reasoning/summaryTextDelta`, `item/reasoning/summaryPartAdded`, `item/reasoning/textDelta`, `thread/compacted`, `model/rerouted`, `model/verification`, `turn/moderationMetadata`, `model/safetyBuffering/updated`, `warning`, `guardianWarning`, `deprecationNotice`, `configWarning`, `fuzzyFileSearch/sessionUpdated`, `fuzzyFileSearch/sessionCompleted`, `thread/realtime/*` (8), `windows/worldWritableWarning`, `windowsSandbox/setupCompleted`, `account/login/completed`.

`ErrorNotification` = `{ error: TurnError, threadId, turnId, willRetry: bool }` — note `willRetry`, which lets a producer avoid flapping to "failed" on a transient retry.

`ServerRequest` methods (server→client, i.e. the approval prompts): `item/commandExecution/requestApproval`, `item/fileChange/requestApproval`, `item/tool/requestUserInput`, `mcpServer/elicitation/request`, `item/permissions/requestApproval`, `item/tool/call`, `account/chatgptAuthTokens/refresh`, `attestation/generate`, `applyPatchApproval`, `execCommandApproval`.

90 `ClientRequest` methods exist. The ones that matter for a producer: `initialize`, `thread/list`, `thread/loaded/list`, `thread/read`, `thread/resume`, `thread/unsubscribe`, `hooks/list`, `turn/interrupt`.

### 2.3 Fan-out: **verified — a non-owning observer DOES receive status**

This was the load-bearing question. Tested empirically **and** confirmed in source.

**Source chain (0.146.0):** one `MessageProcessor`/`OutgoingMessageSender` per *process* (`app-server/src/lib.rs:872-895`), so `ThreadWatchManager` holds the global sender. The single emission site (`app-server/src/thread_status.rs:238`) calls `outgoing.send_server_notification(...)`, defined at `app-server/src/outgoing_message.rs:590` as:

```rust
pub(crate) async fn send_server_notification(&self, notification: ServerNotification) {
    self.send_server_notification_to_connections(&[], notification).await;
}
// empty slice ⇒ OutgoingEnvelope::Broadcast
```

`transport.rs:189-226` fans a `Broadcast` to every connection that is `initialized` and hasn't opted out. `thread/status/changed` is **not** marked `#[experimental]` (`app-server-protocol/src/protocol/common.rs:1655`), so no capability flag is needed.

**Empirical test.** I ran `codex app-server --listen ws://127.0.0.1:47311` and connected two independent WebSocket clients. Only OWNER called `thread/start` and `turn/start`; OBSERVER only called `initialize` (+ `initialized`) and then read.

OBSERVER received exactly:

```
remoteControl/status/changed  x1
thread/started                x1
thread/status/changed         x2
  → {"threadId":"019fc7fc-1dc5-7c02-ac59-0ce85300518f","status":{"type":"active","activeFlags":[]}}
  → {"threadId":"019fc7fc-1dc5-7c02-ac59-0ce85300518f","status":{"type":"idle"}}
```

OWNER received 13 distinct methods (`turn/started`, `turn/completed`, `item/started`, `item/completed`, `item/agentMessage/delta`, `hook/started` x4, `hook/completed` x4, `thread/tokenUsage/updated`, `account/rateLimits/updated`, `mcpServer/startupStatus/updated` x4, plus the same status ones).

**This split is exactly what a status producer wants: lifecycle/status is global; conversation content is thread-scoped.** Content notifications go only to `subscribed_connection_ids` via `ThreadScopedOutgoingMessageSender`, which explicitly refuses to fall back to broadcast. So the observer sees state transitions and *cannot* see prompts, messages, reasoning, or command output. No privacy problem.

Also broadcast: `thread/started`, `remoteControl/statusChanged`, `thread/goal/updated`.

Polling also works from the observer connection: `thread/loaded/list` returned `{"data": []}` before the owner started a thread and `{"data": ["019fc7fc-1dc5-7c02-ac59-0ce85300518f"]}` after — i.e. **the set of threads currently loaded in memory, which is the closest thing Codex has to "live sessions"**. And `thread/read` on the observer connection returned `status={"type":"idle"}` for the other client's thread.

### 2.4 What the producer can actually observe — the crucial scoping caveat

The observer only sees threads running **inside that app-server process**. Three cases:

1. **`codex exec` (headless)** — standalone process, own in-process agent. **Invisible** to any app-server observer. Its machine-readable surface is its own `--json` stdout stream (§2.6) plus the rollout file.
2. **`codex` TUI with no daemon socket present → `AppServerTarget::Embedded`** — agent runs inside the TUI process over in-memory channels. **Invisible.** This is the current state of this machine (no `~/.codex/app-server-control/app-server-control.sock` existed before my testing).
3. **`codex` TUI with a live daemon socket → `AppServerTarget::LocalDaemon`** — **a bare `codex` with no flags silently auto-connects to the running daemon** (50 ms `UnixStream::connect` probe, `tui/src/lib.rs:417-444`; branch at `tui/src/lib.rs:862-878`). Its thread then runs *in the daemon* and **is** visible to observers. This auto-adopt is **skipped** if you pass any `-c` override, `--strict-config`, or `--bypass-hook-trust`. There is no config key or env var to disable it.

In 0.146.0 the TUI *always* speaks the app-server protocol (`Feature::TuiAppServer` is `Stage::Removed`, `default_enabled: true`, "The TUI now always uses the app-server implementation"); "app-server" just defaults to an in-process one. The TUI never *spawns* a daemon.

So: **running a daemon is the single lever that makes interactive TUI sessions observable.** Which leads to the blocker.

### 2.5 Daemon paths, transport quirks, and the Nix blocker

Socket/lock paths are under `$CODEX_HOME`, **not** `XDG_RUNTIME_DIR` and not `/tmp` (`app-server-transport/src/transport/mod.rs:52-70`):

- `~/.codex/app-server-control/app-server-control.sock` — mode `0600`, parent dir forced `0700`
- `~/.codex/app-server-control/app-server-startup.lock`
- `~/.codex/app-server-daemon/{app-server.pid, app-server.pid.lock, daemon.lock, settings.json, app-server.stderr.log}`

Confirmed from the local binary's own error message:

```
$ codex app-server daemon version
Error: failed to connect to /home/thrawny/.codex/app-server-control/app-server-control.sock
Caused by: No such file or directory (os error 2)
```

`--listen unix://` with an empty path resolves to exactly that control socket, as does `--remote unix://` and `codex app-server proxy` with no `--sock`. **There is no authentication on the UDS** — access control is purely filesystem `0700`/`0600`.

**BLOCKER on this machine (verified):**

```
$ codex app-server daemon start
Error: managed standalone Codex install not found at /home/thrawny/.codex/packages/standalone/current/codex
This command requires the standalone install managed by the Codex installer, because the daemon
starts and updates app-server from that fixed path.
  curl -fsSL https://chatgpt.com/codex/install.sh | sh
```

The Nix-packaged codex cannot use `codex app-server daemon start`. **Workaround:** run `codex app-server --listen unix:///home/thrawny/.codex/app-server-control/app-server-control.sock` yourself (supervised, e.g. via zmx or a systemd user unit). That is the same binary the daemon would spawn, and the TUI auto-adopt only probes for the socket's existence, so a self-hosted server should get adopted the same way. **Untested end-to-end** — I verified the socket path and the auto-adopt branch by source reading, and verified a self-hosted server works over `ws://`, but did not drive an interactive TUI against a self-hosted UDS.

**Transport quirk — the unix control socket speaks WebSocket over UDS, not newline-delimited JSON.** My raw newline-JSON client and even `codex app-server proxy --sock <path>` both failed against my own `--listen unix://` server, with the server logging:

```
WARN codex_app_server_transport::transport::unix_socket:
  failed to upgrade control socket websocket connection: WebSocket protocol error: httparse error: invalid token
  failed to upgrade control socket websocket connection: WebSocket protocol error: Handshake not finished
```

The handshake is `GET /rpc` + `Upgrade`, returning `101`. `codex app-server proxy` exists precisely to do this upgrade and hand you plain stdio bytes — but it failed against my non-daemon socket, so a producer targeting UDS should implement the WS upgrade itself (or use `--listen ws://127.0.0.1:PORT`, which worked first try). Over **`stdio://` the framing is plain newline-delimited JSON-RPC** — confirmed:

```
$ printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"t","version":"1"}}}' | codex app-server --stdio
{"id":1,"result":{"userAgent":"t/0.146.0 (NixOS 26.11.0; x86_64) ghostty/1.3.1 (t; 1)","codexHome":"/home/thrawny/.codex","platformFamily":"unix","platformOs":"linux"}}
{"method":"remoteControl/status/changed","params":{...},"emittedAtMs":1785766381830}
```

(stdin must stay open — closing it makes the process exit before responding, which cost me two debugging rounds.)

`initialize` requires `clientInfo: {name, version}`; `capabilities.experimentalApi: true` opts into experimental methods; `capabilities.optOutNotificationMethods: string[]` suppresses named notifications **per connection** — useful for a producer that wants only status.

### 2.6 `codex exec --json` — the headless equivalent

Verified live. Event stream (dot-notation, a *different* naming scheme from the app-server's slash-notation):

```
thread.started   {"type":"thread.started","thread_id":"019fc7f4-abba-7e02-ad74-b1fee7780ee3"}
turn.started
item.completed
item.started
item.completed
item.completed
turn.completed   {"type":"turn.completed","usage":{"input_tokens":51068,"cached_input_tokens":38144,...}}
```

Distinguishes working (`turn.started` without terminator) / done (`turn.completed`). `turn.completed` carries **no `threadId`** — you must correlate with the earlier `thread.started`. Needs-input is not applicable in `--json` exec (approvals are auto-resolved by the sandbox/approval policy). Only consumable by whoever spawned the process — no good for a passive producer observing sessions it didn't launch.

### 2.7 `~/code/t3code/packages/effect-codex-app-server`

Local reference implementation of this protocol, and a useful model for a producer:

- `src/protocol.ts` (423 lines), `src/client.ts` (269), `src/errors.ts` (427), `src/schema.ts`, `src/rpc.ts`
- `src/_generated/{schema.gen.ts, meta.gen.ts, namespaces.gen.ts}` — generated from the same schema source
- `scripts/generate.ts` — the codegen entry point
- `src/_internal/stdio.ts` — confirms **stdio child-process transport** (`makeChildStdio` wires `handle.stdout`/`handle.stdin`), i.e. t3code spawns `codex app-server` as a stdio child and is therefore a *single-client owner*, not a multi-client observer
- `test/examples/codex-app-server-probe.ts`, `test/fixtures/codex-app-server-mock-peer.ts`

Note: a stdio transport is inherently one-client-per-process, so t3code's arrangement cannot observe other sessions. The multi-client observation the producer needs requires the `unix://` or `ws://` transport.

A running `codex app-server -c mcp_servers.t3-…` process was live on this machine during research (pid 1288865) — a t3code/acpx-spawned stdio child, not a daemon.

---

## Candidate 3 — the `notify` hook in `config.toml`

**Verdict: do not build on this.**

The event set is **still exactly one variant**. The enum moved in 0.146.0 from `core/src/user_notification.rs` to `codex-rs/hooks/src/legacy_notify.rs` — note the filename, it is now a compatibility shim over the new hooks engine:

```rust
/// Legacy notify payload appended as the final argv argument for backward compatibility.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "type", rename_all = "kebab-case")]
enum UserNotification {
    #[serde(rename_all = "kebab-case")]
    AgentTurnComplete {
        thread_id, turn_id, cwd,
        client: Option<String>,
        input_messages: Vec<String>,
        last_assistant_message: Option<String>,
    },
}
```

Independently corroborated from the local binary's strings (the serde field names appear as one contiguous blob, which is what a single-variant kebab-case enum looks like):

```
agent-turn-complete thread-id turn-id cwd client input-messages last-assistant-message
```

Single-variant since `rust-v0.20.0`; only fields grew (`thread_id`/`cwd` by v0.50, `client` later). Open issue [#19921](https://github.com/openai/codex/issues/19921) *requests* `approval-requested`/`plan-mode-prompt`, confirming they don't exist; [#14813](https://github.com/openai/codex/issues/14813) was closed without adding them.

Docs: `https://developers.openai.com/codex/config-file/config-advanced.md` — "whenever Codex emits supported events (currently only `agent-turn-complete`)".

**States distinguishable:** done only. No working, no needs-input, no failed. Fields do now include `thread-id` and `cwd`, which is more than the docs historically implied.

**Liveness:** none.

**Headless:** yes — verified with a real run under a throwaway `CODEX_HOME`:

```json
{"type":"agent-turn-complete","thread-id":"019fc7fa-…","turn-id":"019fc7fa-…",
 "cwd":"…","client":"codex_exec","input-messages":["Reply with exactly: hi"],
 "last-assistant-message":"hi"}
```

Structurally surface-independent: `config.notify` → `legacy_notify_argv` (`core/src/session/mod.rs:4120`) → `run_legacy_after_agent_hook` (`core/src/hook_runtime.rs:465`) → called from the shared turn loop (`core/src/session/turn.rs:464`). Docs never state this either way.

**Two reliability traps, both in source:**

1. The payload is passed as **a single argv argument**, not on stdin (`command.arg(notify_payload)`). Open issue [#34878](https://github.com/openai/codex/issues/34878): `input-messages` accumulates the thread's *entire* user-message history, so once it exceeds Linux `MAX_ARG_STRLEN` (131072 B) `execve` fails `E2BIG` and **notify silently stops firing for the rest of a long thread.** For a long-running session — exactly the case a status producer cares about — this surface degrades to nothing.
2. Spawn failure is swallowed: `Err(err) => HookResult::FailedContinue(err.into())`, logged only at `tracing::warn`.

---

## Candidate 4 — `tui.notifications`, MCP server mode, and hooks

### 4.1 `tui.notifications` — nothing machine-readable

Config type (`codex-rs/config/src/types.rs:600`): `Notifications::Enabled(bool) | Notifications::Custom(Vec<String>)`, `#[serde(untagged)]`, default `Enabled(true)`.

The **complete** filter vocabulary is `Notification::type_name()` in `codex-rs/tui/src/chatwidget/notifications.rs` — three strings:

| Filter string | Internal variants |
|---|---|
| `agent-turn-complete` | `AgentTurnComplete` |
| `approval-requested` | `ExecApprovalRequested`, `EditApprovalRequested`, `ElicitationRequested` |
| `plan-mode-prompt` | `PlanModePrompt` |

Docs give only two as "examples" and never enumerate the set; `plan-mode-prompt` is undocumented.

**Both backends are pure terminal escapes** (`codex-rs/tui/src/notifications/`): `osc9.rs` emits OSC 9, `bel.rs` emits `\x07`. **No OSC 777 anywhere** in source or docs. `auto` picks OSC 9 only for Ghostty, iTerm2, Kitty, Warp, WezTerm; everything else falls back to BEL. Under tmux, OSC 9 is DCS-wrapped. Companion keys: `tui.notification_method` = `auto|osc9|bel`, `tui.notification_condition` = `unfocused` (default) | `always`.

Consuming this would be terminal scraping by definition — it is exactly what the question rules out. (It is, however, the only surface that signals `approval-requested` in an Embedded TUI without hooks, which is worth knowing as a fallback of last resort.) Not currently configured in this repo's `config/codex/config.toml`.

### 4.2 MCP server mode

`codex mcp-server` (stdio) exposes Codex as an MCP server to a *client that drives it*. Same ownership limitation as stdio app-server: one client per process, only sees what it drives. No passive observation surface. Not a candidate.

### 4.3 Hooks — **the actual recommended surface**

Official docs exist: **`https://developers.openai.com/codex/hooks`**. Authoritative event list from `codex-rs/hooks/src/lib.rs`:

```rust
pub const HOOK_EVENT_NAMES: [&str; 11] = [
    "PreToolUse", "PermissionRequest", "PostToolUse", "PreCompact", "PostCompact",
    "SessionStart", "SessionEnd", "UserPromptSubmit", "SubagentStart", "SubagentStop", "Stop",
];
```

Corroborated independently by the local binary's generated schema — `HookEventName` in `v2/HooksListResponse.json` and `v2/HookStartedNotification.json` is a closed enum with the camelCase forms:

```json
["preToolUse","permissionRequest","postToolUse","preCompact","postCompact",
 "sessionStart","sessionEnd","userPromptSubmit","subagentStart","subagentStop","stop"]
```

`HookHandlerType` = `["command","prompt","agent"]`. `HookExecutionMode` = `["sync","async"]`.

**There is no `Notification` hook** (unlike Claude Code) — confirmed in source, docs, and generated schemas. Codex *adds* `PermissionRequest`, `PostCompact`, and `SubagentStart` that Claude Code lacks. `PermissionRequest` is the one that gives you needs-input, and it is the reason hooks beat every other surface for this task.

**Payload: JSON on stdin** (`engine/command_runner.rs:63,85`), deliberately Claude-Code-compatible:
`session_id`, `transcript_path`, `cwd`, `hook_event_name`, `model`, `permission_mode`, plus per-event fields (`tool_name`, `tool_input`, `tool_use_id`, `prompt`, `source`, `reason`, `stop_hook_active`, `last_assistant_message`). Codex extensions: **`turn_id`, `agent_id`, `agent_type`** (`codex-rs/hooks/src/schema.rs`).

Note `session_id` + `transcript_path`: that gives the producer the thread id **and** the rollout file path in the same payload, so hook events and rollout/sqlite records join cleanly.

Output contract: `{continue, stopReason, systemMessage, suppressOutput}` and `hookSpecificOutput.additionalContext` / `hookSpecificOutput.permissionDecision`. Corroborated by this repo's own `config/codex/hooks/agents-local.mjs:88-108`, which reads `hookInput.cwd` / `hookInput.hook_event_name` from stdin and emits `hookSpecificOutput.additionalContext`.

**Config locations (all merge, higher precedence does not replace lower):** `~/.codex/hooks.json`, `~/.codex/config.toml` `[hooks]`, `<repo>/.codex/hooks.json`, `<repo>/.codex/config.toml`. Project hooks load only if the `.codex/` layer is trusted.

**Headless: YES.** Proven by an upstream test — `codex-rs/exec/tests/suite/hooks.rs:8` `exec_hook_trust_bypass_runs_session_start_hook` asserts a SessionStart hook fires under `codex exec`. Not documented as exec-compatible, but demonstrably is.

I also observed hooks firing live in app-server mode during the fan-out test — the OWNER connection received `hook/started`/`hook/completed` pairs with run ids:

```
session-start:0:/home/thrawny/.codex/hooks.json
session-start:1:/home/thrawny/.codex/hooks.json
user-prompt-submit:2:/home/thrawny/.codex/hooks.json
stop:3:/home/thrawny/.codex/hooks.json
```

`hook/started` / `hook/completed` are themselves app-server notifications carrying a `HookRunSummary` = `{id, eventName, handlerType, executionMode, scope, source, sourcePath, displayOrder, startedAt, completedAt, durationMs, status: HookRunStatus, statusMessage, entries: HookOutputEntry[]}` — i.e. hook execution is itself observable over the protocol (though thread-scoped to the owning client, not broadcast).

**Existing precedent in this repo** — `config/codex/hooks.agent-switch.json` already wires three of these:

```
SessionStart      → agent-switch track session-start --agent codex  (+ agents-local.mjs)
UserPromptSubmit  → agent-switch track prompt-submit  --agent codex
Stop              → agent-switch track stop           --agent codex
```

Selected by `nix/home/shared/ai-tools.nix:119-120` (`enableAgentSwitchIntegration ? "codex/hooks.agent-switch.json" : "codex/hooks.json"`), also linked by `nix/modules/nixos/t3code.nix:298` and referenced in `nix/lib/agent-skills.nix:100`. **The producer should extend this file with `PermissionRequest` and `SessionEnd` rather than inventing a new mechanism.**

**Trust gate — the main operational caveat.** Non-managed `command` hooks require reviewed-and-hashed trust. Live example from `~/.codex/config.toml`:

```toml
[hooks.state."/home/thrawny/.codex/hooks.json:session_start:0:0"]
trusted_hash = "sha256:26c185271a07dbe26100154aee3694c89ceda33d14d45213f3843442fcfe9da3"
[hooks.state."/home/thrawny/.codex/hooks.json:stop:0:0"]
trusted_hash = "sha256:f630042e3ba7d0c783d4a7c17818a8149f396be6884b4bc74d01de5183d63ea6"
[hooks.state."/home/thrawny/.codex/hooks.json:user_prompt_submit:0:0"]
trusted_hash = "sha256:d7cda4cf40658a346bde9ba9c9401ffb2bb8c8ed58a61c457b52684acc59c62f"
[hooks.state."/home/thrawny/.codex/hooks.json:session_start:0:1"]
trusted_hash = "sha256:a582658d10a946163f3016f6d3c334eaf40cdcab68156319d629b65dec7312e2"
```

Trust is keyed by `<path>:<event>:<block>:<index>` and pinned to a content hash. **Editing a hook command silently invalidates its trust and the hook stops running until re-approved via `/hooks`** (or `--dangerously-bypass-hook-trust`). Since `hooks.json` is store-backed here (Nix immutable symlink), every `just switch` that changes a hook command requires re-approval. This is the single biggest operational risk in the recommended design and the producer should surface "hook untrusted" as a distinct degraded state.

---

## Comparison with the Claude Code baseline

| | Claude Code | Codex CLI 0.146.0 |
|---|---|---|
| Status file on disk | `~/.claude/sessions/<pid>.json`, `status: busy\|waiting\|idle` | **none — status is in-memory only** |
| Hooks required for status | **zero** | **yes, for any non-daemon session** |
| Keyed by | pid (liveness = process existence) | `session_id`/`thread_id` (no pid anywhere) |
| Liveness detection | pid in filename; stale file ⇒ dead process | **no pid, no heartbeat** — producer must derive it |
| needs-input state | native | `activeFlags: waitingOnApproval\|waitingOnUserInput` (app-server) or `PermissionRequest` hook |
| failed state | — | `systemError` / `TurnStatus: failed` + `ErrorNotification.willRetry` (app-server); rollout `turn_aborted` conflates abort with failure |
| Headless coverage | — | hooks fire in `codex exec`; `--json` stream; rollout written live |
| Push vs poll | poll a file | push (broadcast notifications) + poll (`thread/list`/`thread/read`/`thread/loaded/list`) |

**Net:** Codex's status *model* is richer than Claude Code's (four states plus per-turn status plus retry-awareness, versus three states), but its *delivery* is worse for a passive local producer — there is no zero-config file to stat, and no pid to test for liveness. The producer must supply the persistence and the liveness layer that Claude Code hands you for free.

**Liveness suggestions**, since nothing in Codex provides it:
- `SessionStart` hook records `$PPID` (the codex process) → producer can `kill -0` it, giving pid-based liveness equivalent to the Claude Code baseline.
- Cross-check with `thread/loaded/list` when a daemon/self-hosted app-server is available — that is authoritative for "loaded in memory right now".
- Fall back to rollout file mtime + unterminated `task_started` for recovery after a producer restart.

---

## Caveats and unknowns

**Stability / support**
- `codex app-server` and `codex remote-control` are documented but marked **experimental**. `codex app-server daemon` (all subcommands) and `codex app-server proxy` are **documented nowhere** — the only prose is `codex-rs/app-server-daemon/README.md`, which warns the lifecycle contract may change; Unix-only.
- Docs never affirm multi-client thread observation as a *supported guarantee*, though the API and code plainly implement it. Treat the broadcast behavior as an implementation detail that could change between releases. Pin behavior checks to a version; regenerate the schema (`codex app-server generate-json-schema`) on every codex upgrade and diff it.
- The docs never state whether `notify` or hooks run under `codex exec`. Both answers here come from source + a live run, not documentation.

**Verified by source reading only (not end-to-end tested)**
- The `LocalDaemon` auto-adopt path for a bare interactive `codex` (needs a TTY plus a live daemon socket).
- Whether a **self-hosted** `codex app-server --listen unix://<control socket path>` gets adopted by the TUI the same way a managed daemon does. The auto-adopt only probes for socket existence, so it should — but this is the linchpin of the daemon-based design and deserves an explicit test before committing to it.

**Known operational hazards**
- **Slow-consumer disconnect.** The app-server force-disconnects a connection whose outbound queue fills (cap 128): `"disconnecting slow connection after outbound queue filled"`. A producer must drain continuously and should use `capabilities.optOutNotificationMethods` to shed everything except the status/lifecycle methods it needs.
- **No snapshot on join.** `thread/status/changed` is diff-gated; a newly connected observer gets no initial state. Always pair connect with `thread/loaded/list` + `thread/read` to seed, then reconcile.
- **No `thread/subscribe`.** There is `thread/unsubscribe` but no subscribe. To get the *full* event stream for someone else's thread you must call `thread/resume` (the code explicitly supports this: "Preserve rejoin semantics when another client can still observe the loaded thread"). For status only, no subscribe is needed — broadcast covers it.
- **`SUN_LEN` overflow.** A long `CODEX_HOME` breaks UDS binding: `Error: path must be shorter than SUN_LEN`. Keep `CODEX_HOME` short if relocating it.
- **`codex app-server daemon start` is unavailable on Nix** (requires the `install.sh` standalone managed install at `~/.codex/packages/standalone/current/codex`). Self-hosting the app-server is the workaround.
- **`CODEX_HOME` under `/tmp` is partially refused:** `WARNING: proceeding, even though we could not create PATH aliases: Refusing to create helper binaries under temporary dir "/tmp"`. This is why my isolated-`CODEX_HOME` hook-payload capture did not complete (it also hung reading stdin) — the hook payload shape here comes from source (`codex-rs/hooks/src/schema.rs`), the generated schema, this repo's working `agents-local.mjs`, and the upstream exec test, rather than from my own capture.
- **Rollout tailing is privacy-sensitive** — the files contain full conversation content. Restrict any tailer to `type` / `payload.type`.
- Do not write to `state_5.sqlite`; open read-only/immutable to avoid contending with codex's WAL writer.

**Not chased down**
- Whether `activeFlags` can hold both flags simultaneously, and the precise trigger for each (`waitingOnUserInput` vs `waitingOnApproval`) — the enum is closed at two values, but the state machine that sets them was not traced.
- The `TurnError` variant set (only its shape and its `willRetry` companion were inspected).
- `codex exec-server` (`[EXPERIMENTAL] Run the standalone exec-server service`, `--listen ws://` default, `--remote`, `--environment-id`). This may be a better fit than the app-server for observing headless runs, but it was out of scope and is entirely undocumented.
- `codex doctor` output — may expose a machine-readable health/session summary; not inspected.

---

## Reproduction commands

```bash
# authoritative protocol schema straight from the installed binary
codex app-server generate-json-schema --out ./schema
codex app-server generate-ts --out ./ts

# the four status states
jq '.definitions.ThreadStatus, .definitions.ThreadActiveFlag' schema/ServerNotification.json

# all 70 server notifications / 90 client requests
jq -r '.oneOf[].properties.method.enum[0]' schema/ServerNotification.json
jq -r '.oneOf[].properties.method.enum[0]' schema/ClientRequest.json | sort

# the 11 hook events
jq '.definitions.HookEventName' schema/v2/HooksListResponse.json

# multi-client observation (ws is easiest; unix:// needs a WS-over-UDS upgrade)
codex app-server --listen ws://127.0.0.1:47311
# then: initialize -> initialized -> read broadcast thread/status/changed

# headless event stream
codex exec --json --skip-git-repo-check -s read-only "…"

# thread -> rollout mapping without walking date shards
sqlite3 -batch ~/.codex/state_5.sqlite \
  'select id, cwd, updated_at_ms, rollout_path from threads order by updated_at_ms desc limit 5;'
```
