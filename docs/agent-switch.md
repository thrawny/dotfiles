# agent-switch

Unified tool for tracking and switching between AI coding agent sessions (Claude, Codex, OpenCode).

## Goals

- Single binary for all platforms (niri, tmux, macOS)
- Fast daemonless operation where possible
- Clean up stale sessions automatically
- Support multiple agent types with minimal per-agent code

## Commands

```
agent-switch track <event>    # Called by hooks, updates state
agent-switch fix              # Manual: re-associate focused window with session
agent-switch list             # JSON output for scripts
agent-switch cleanup          # Remove stale sessions
agent-switch tmux             # Daemonless tmux picker
agent-switch niri             # GTK daemon for niri
```

## State

Single JSON file at `~/.local/state/agent-switch/sessions.json`:

```json
{
  "sessions": {
    "<window-id>": {
      "agent": "claude",
      "session_id": "abc123",
      "cwd": "/home/user/project",
      "state": "responding",
      "state_updated": 1234567890.123,
      "window": {
        "niri_id": "42",
        "tmux_id": "@1"
      }
    }
  }
}
```

Window ID is the primary key (niri ID or tmux ID depending on environment).

## Track Events

Received from agent hooks:

| Event | Action |
|-------|--------|
| `session-start` | Create session entry |
| `session-end` | Remove session entry |
| `prompt-submit` | Set state to `responding` |
| `stop` | Set state to `idle` or `waiting` (check transcript) |
| `notification` | If permission prompt, set `waiting` |

Input via stdin (JSON):

```json
{
  "agent": "claude",
  "event": "session-start",
  "session_id": "abc",
  "cwd": "/path"
}
```

## Window ID Capture

Window ID is captured only on:
- `session-start` - new session starting
- `prompt-submit` when session not found - resumed session

Other events (`stop`, `notification`, etc.) look up by `session_id`, never re-query window.
This avoids mis-registration when agent works in background while user focuses another window.

**Race condition**: Small window (~100ms) between session start and niri query where user could
switch windows. Accepted tradeoff - use `fix` command to recover if needed.

## Fix Command

Manual recovery for mis-associated sessions:

```
agent-switch fix
```

1. Query focused niri/tmux window
2. Detect agent session in window (by title pattern: ✳, spinner, etc.)
3. Find orphan session (registered to non-existent or wrong window)
4. Re-associate session with current window

Use when: agent shows wrong status, or status not showing for active agent.

## Cleanup Logic

Run on every `list`, `tmux`, or `niri` toggle:

1. Query current windows (niri or tmux)
2. Remove sessions where window no longer exists
3. Optionally: remove sessions with `state_updated` older than 24h

```rust
fn cleanup(sessions: &mut Sessions, valid_windows: &HashSet<String>) {
    sessions.retain(|id, _| valid_windows.contains(id));
}
```

## Platform Modes

### tmux (daemonless)

```
agent-switch tmux
```

1. Load sessions + cleanup stale
2. Filter to sessions with `tmux_id`
3. Show fzf picker with state indicators
4. Switch to selected tmux window
5. Exit

Keybind: `bind s run-shell "agent-switch tmux"`

### niri (daemon)

```
agent-switch niri
```

Long-running GTK process:
- Listens on socket for toggle command
- Watches sessions file for changes
- Shows overlay picker on toggle
- Cleans up stale sessions on toggle

Keybind calls: `agent-switch niri --toggle`

### macOS (future)

Daemonless, similar to tmux but queries Terminal.app or iTerm windows.

## Hook Integration

### Claude

```json
{
  "hooks": {
    "SessionStart": [{ "command": "agent-switch track session-start" }],
    "SessionEnd": [{ "command": "agent-switch track session-end" }],
    "Stop": [{ "command": "agent-switch track stop" }],
    "Notification": [{ "command": "agent-switch track notification" }],
    "UserPromptSubmit": [{ "command": "agent-switch track prompt-submit" }]
  }
}
```

### Codex / OpenCode

Similar hook configs, passing `"agent": "codex"` etc in the JSON input.

## UI Display

State indicators:

| State | Color | Label |
|-------|-------|-------|
| `waiting` | Red | Needs attention |
| `responding` | Green | Working |
| `idle` | Gray | Done |

Format: `[key] workspace / agent [state]: description`

Example:
```
[hh] dotfiles / claude [waiting]: implement feature X
[hj] backend / codex [working]
[hk] frontend / claude [idle]
```

## File Structure

```
rust/agent-switch/
├── Cargo.toml
└── src/
    ├── main.rs         # CLI dispatch
    ├── state.rs        # Session state management
    ├── track.rs        # Hook event handling
    ├── cleanup.rs      # Stale session removal
    ├── tmux.rs         # Tmux picker (fzf)
    └── niri.rs         # GTK daemon + UI
```

## Non-Goals

- Real-time sync between machines
- Historical session data
- Agent-specific features beyond state tracking
