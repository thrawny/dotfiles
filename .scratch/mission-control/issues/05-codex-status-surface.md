# Codex status surface

Type: research
Status: resolved

## Question

What authoritative, machine-readable session/status surface does Codex CLI expose that a local producer could consume **without terminal scraping**? Candidates to verify against current Codex versions:

- Session/state files under `~/.codex` (rollout/session JSONL — what do they carry, are they written live?)
- The app-server / ACP protocol events (t3code's `effect-codex-app-server` package suggests this exists)
- `notify` hook configuration — its full event set (docs historically said only `agent-turn-complete`; verify)
- `tui.notifications` and any MCP-server mode signals

For each: which states are distinguishable (working / needs-input / done / failed), how liveness is detected, and whether it works headless. Compare with the Claude baseline (`~/.claude/sessions/<pid>.json`: status busy|waiting|idle, zero hooks).

Deliverable: findings markdown at `.scratch/mission-control/research/05-codex-status-surface.md`.

## Answer

Resolved 2026-08-03. Full findings: [research/05-codex-status-surface.md](../research/05-codex-status-surface.md) (verified empirically against codex 0.146.0, not just docs).

- **No Claude-style status file exists**: `ThreadStatus` is in-memory only in the app-server; `state_5.sqlite` has no status column. A producer must be *pushed* status or infer it.
- **Recommended surface: hooks** (`~/.codex/hooks.json`) — Claude-Code-compatible engine, 11 events (`UserPromptSubmit`→busy, `PermissionRequest`→waiting, `Stop`→idle, `SessionEnd`→gone), fires headless in `codex exec`, payload carries `session_id`/`cwd`. This repo already wires 3 events → `agent-switch track`; extend that file.
- **App-server observer** as optional high-fidelity layer later: `thread/status/changed` is broadcast to all clients (verified) with content staying thread-scoped — but `codex exec` and default TUIs are invisible to it, and the daemon doesn't start on Nix.
- **Do not use** `notify` (single event, silently dies on long threads via E2BIG) or `tui.notifications` (terminal escapes = scraping). Rollout JSONL is a recovery oracle, not a live signal (no needs-input, no pid, no heartbeat).
- **Liveness**: no pid anywhere — record `$PPID` in the `SessionStart` hook and gate on `kill -0`.
- **Operational risk**: hook trust is content-hashed; editing a hook command (e.g. via `just switch` on the store-backed file) silently untrusts it until re-approved via `/hooks`. The producer must surface "hook untrusted" as a distinct degraded state.
