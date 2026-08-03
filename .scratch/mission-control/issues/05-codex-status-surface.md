# Codex status surface

Type: research
Status: claimed

## Question

What authoritative, machine-readable session/status surface does Codex CLI expose that a local producer could consume **without terminal scraping**? Candidates to verify against current Codex versions:

- Session/state files under `~/.codex` (rollout/session JSONL — what do they carry, are they written live?)
- The app-server / ACP protocol events (t3code's `effect-codex-app-server` package suggests this exists)
- `notify` hook configuration — its full event set (docs historically said only `agent-turn-complete`; verify)
- `tui.notifications` and any MCP-server mode signals

For each: which states are distinguishable (working / needs-input / done / failed), how liveness is detected, and whether it works headless. Compare with the Claude baseline (`~/.claude/sessions/<pid>.json`: status busy|waiting|idle, zero hooks).

Deliverable: findings markdown at `.scratch/mission-control/research/05-codex-status-surface.md`.
