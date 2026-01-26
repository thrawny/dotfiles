# Agent-Switch Daemon Refactor Implementation Plan

## Overview

Refactor agent-switch into a compositor-agnostic daemon (`serve`) with optional niri overlay (`--niri`). The daemon pre-loads and caches session data (especially slow Codex parsing), making the tmux picker instant. Remove tmux-fzf-switcher after migrating its async loading logic.

## Current State Analysis

- **niri daemon** (`niri.rs`): Monolithic GTK4 app with file watchers, socket IPC, session cache, and niri-specific overlay
- **tmux picker** (`tmux.rs`): One-shot, loads Claude sessions synchronously, no Codex support
- **tmux-fzf-switcher**: Async Codex loading via background thread + channel polling

### Key Discoveries:

- Socket IPC already compositor-agnostic: `track.rs:socket_path()`, commands: `toggle`, `track <json>`
- File watchers in `niri.rs:981-1089` are compositor-agnostic (watch sessions.json, ~/.codex/sessions/)
- Codex parsing in `niri.rs:205-625` is compositor-agnostic
- `state.rs` already abstracts window IDs: `WindowId { niri_id, tmux_id }`
- Niri-specific: focus tracking (1091-1139), GTK overlay (1146-1611), niri IPC (627-651)

## Desired End State

```
agent-switch serve              # Headless daemon (macOS/Linux)
agent-switch serve --niri       # Daemon + GTK overlay (Linux only)
agent-switch tmux               # Picker queries daemon for instant cached data
agent-switch track <event>      # Unchanged, sends to daemon socket
```

**Verification:**
- `agent-switch serve` starts, watches files, responds to socket commands
- `agent-switch tmux` shows Codex status instantly (no async loading delay)
- On macOS: daemon exits when tmux server dies
- `tmux-fzf-switcher` binary and directory removed

## What We're NOT Doing

- AeroSpace/Hyprland/Sway support (future work)
- Changing the track event protocol
- Modifying how hooks call `agent-switch track`

## Implementation Approach

The daemon is **fully compositor-agnostic**. It doesn't know or care about tmux vs niri - it just:
1. Listens on a socket for `track`/`list`/`toggle` commands
2. Watches session files (sessions.json, ~/.codex/sessions/)
3. Caches parsed session state in memory

Session tracking works the same way everywhere: hooks call `agent-switch track`, which sends to the daemon socket. The daemon stores sessions with optional `tmux_id` and `niri_id` fields.

The only compositor-specific parts:
- `--niri` flag: Adds GTK overlay and niri focus tracking on top of core daemon
- Headless mode: Monitors tmux sockets to know when to exit (lifecycle only)

Extract core daemon from `niri.rs` into `daemon.rs`. The `serve` command runs it. Tmux picker queries it via `list` socket command.

---

## Phase 1: Extract Core Daemon Module

### Overview

Create `daemon.rs` with the shared daemon infrastructure: message types, socket listener, file watchers, session cache.

### Changes Required:

#### 1. New file: `src/daemon.rs`

Extract from `niri.rs`:
- `Message` enum (lines 96-102) - rename to `DaemonMessage`, add `List` variant
- `socket_path()` (lines 166-171) - already in `track.rs`, reuse
- `start_socket_listener()` (lines 932-979) - add `list` command support
- `start_sessions_watcher()` (lines 1027-1089) - file watching logic
- `AgentSession`, `CodexSession` structs (lines 66-86)
- `load_agent_sessions()` (lines 182-203)
- `load_codex_sessions()` and helpers (lines 205-625)

New additions:
- `SessionCache` struct holding `HashMap<u64, AgentSession>` and `HashMap<String, CodexSession>`
- `list` socket command returning JSON: `{"claude": [...], "codex": [...]}`
- Tmux socket monitoring thread for auto-exit

#### 2. Socket protocol extension

Add `list` command:
```
Request:  list
Response: {"claude": [...sessions...], "codex": [...sessions...]}
```

Sessions include: session_id, cwd, state, state_updated, window_id

### Success Criteria:

#### Automated:
- [ ] `cargo build -p agent-switch` compiles
- [ ] `cargo test -p agent-switch` passes
- [ ] New module exports `DaemonMessage`, `SessionCache`, `start_daemon_threads()`

#### Manual:
- [ ] N/A (module not yet wired to CLI)

---

## Phase 2: Add `serve` Subcommand

### Overview

Wire `daemon.rs` to a new `serve` subcommand. Runs headless daemon with optional tmux socket monitoring.

### Changes Required:

#### 1. `src/main.rs` CLI changes

Add to `Command` enum:
```rust
Serve {
    /// Enable niri GTK overlay (Linux only)
    #[arg(long)]
    niri: bool,
}
```

Tmux sockets are discovered by scanning `/tmp/tmux-$UID/` (or `/private/tmp/` on macOS).

#### 2. `src/daemon.rs` - main loop

```rust
pub fn run(niri: bool) -> Result<()> {
    let (tx, rx) = mpsc::channel();
    let cache = Arc::new(Mutex::new(SessionCache::new()));

    // Start compositor-agnostic threads
    start_socket_listener(tx.clone(), cache.clone());
    start_sessions_watcher(tx.clone());

    if niri {
        // Niri mode: run GTK overlay, lifecycle tied to niri session
        #[cfg(feature = "niri")]
        niri::run_overlay(tx, rx, cache);
    } else {
        // Headless mode: monitor tmux sockets for auto-exit
        start_tmux_monitor();
        // Process messages until exit
        loop { handle_message(rx.recv()?, &cache); }
    }
}
```

#### 3. Headless mode lifecycle

In headless mode (no `--niri`), the daemon needs to know when to exit. Scan for tmux sockets:

```rust
fn find_tmux_sockets() -> Vec<PathBuf> {
    let uid = unsafe { libc::getuid() };
    let base = if cfg!(target_os = "macos") { "/private/tmp" } else { "/tmp" };
    let dir = PathBuf::from(format!("{}/tmux-{}", base, uid));
    fs::read_dir(&dir).into_iter().flatten().filter_map(|e| e.ok()).map(|e| e.path()).collect()
}
```

Poll every 5 seconds, exit when no sockets found.

**Note:** This is ONLY for daemon lifecycle. Session tracking works without any tmux-specific code - hooks call `agent-switch track` which sends to the daemon socket regardless of compositor.

### Success Criteria:

#### Automated:
- [ ] `cargo build -p agent-switch` compiles on macOS (no niri feature)
- [ ] `agent-switch serve --help` shows options

#### Manual:
- [ ] `agent-switch serve` starts, logs "listening on socket"
- [ ] `echo "list" | nc -U $XDG_RUNTIME_DIR/agent-switch.sock` returns JSON
- [ ] Kill tmux server -> headless daemon exits automatically

---

## Phase 3: Refactor Niri to Use Core Daemon

### Overview

Make `--niri` flag layer GTK/niri-specific code on top of the core daemon.

### Changes Required:

#### 1. `src/niri.rs` refactor

Remove extracted code (now in daemon.rs). Keep:
- GTK4 application setup (lines 1146-1320)
- Niri IPC: `niri_request()`, `niri_workspaces()`, `niri_windows()` (lines 627-651)
- Focus tracker: `start_focus_tracker()` (lines 1091-1139)
- Overlay rendering and key handling (lines 1321-1611)
- `WorkspaceColumn`, `Config`, `Project` structs

New entry point:
```rust
pub fn run_overlay(tx: Sender<DaemonMessage>, rx: Receiver<DaemonMessage>, cache: Arc<Mutex<SessionCache>>) {
    // Start niri-specific threads
    start_focus_tracker(focused_window.clone());

    // Build GTK app, run main loop
    // Poll rx via glib::timeout_add_local (existing pattern)
}
```

#### 2. Update `Cargo.toml` features

```toml
[features]
niri = ["gtk4", "gtk4-layer-shell", "niri-ipc", "notify", "toml", "shellexpand", "time"]

[dependencies]
notify = "8"  # Move to non-optional (needed for daemon)
```

### Success Criteria:

#### Automated:
- [ ] `cargo build -p agent-switch --features niri` compiles
- [ ] `cargo build -p agent-switch` compiles (no niri feature)

#### Manual:
- [ ] `agent-switch serve --niri` shows GTK overlay on toggle
- [ ] Overlay shows correct Claude/Codex session states
- [ ] `agent-switch track` events update overlay in real-time

---

## Phase 4: Update Tmux Picker to Query Daemon

### Overview

Replace synchronous session loading in tmux picker with daemon socket query.

### Changes Required:

#### 1. `src/tmux.rs` changes

Add daemon query function:
```rust
fn query_daemon_sessions() -> Option<(Vec<AgentSession>, Vec<CodexSession>)> {
    let socket = track::socket_path();
    let mut stream = UnixStream::connect(&socket).ok()?;
    stream.write_all(b"list\n").ok()?;
    let response: Value = serde_json::from_reader(&stream).ok()?;
    // Parse claude and codex arrays
}
```

Update `run()` (line 441):
```rust
pub fn run(fzf: bool) -> Result<()> {
    // Try daemon first, fall back to direct file read
    let (claude_sessions, codex_sessions) = query_daemon_sessions()
        .unwrap_or_else(|| {
            eprintln!("daemon not running, loading sessions directly (slower)");
            (load_from_state_file(), vec![])  // No Codex without daemon
        });

    // Rest of picker logic unchanged
}
```

#### 2. Display Codex status

Port status display from tmux-fzf-switcher:
- Match Codex sessions by cwd to tmux window's pane_current_path
- Show colored status indicator (waiting=red, working=green, idle=gray)

Pattern: `tmux-fzf-switcher/src/main.rs:758-820` (render_window_line with status)

### Success Criteria:

#### Automated:
- [ ] `cargo build -p agent-switch` compiles
- [ ] `cargo test -p agent-switch` passes

#### Manual:
- [ ] With daemon running: `agent-switch tmux` shows instantly with Codex status
- [ ] Without daemon: `agent-switch tmux` shows warning, works without Codex
- [ ] Codex status colors match session state (waiting/working/idle)

---

## Phase 5: Remove tmux-fzf-switcher

### Overview

Delete the legacy package and update all references.

### Changes Required:

#### 1. Delete directory
```
rm -rf rust/tmux-fzf-switcher/
```

#### 2. Update `rust/Cargo.toml`
```toml
members = ["bash-validator", "voice", "agent-switch"]  # Remove tmux-fzf-switcher
```

#### 3. Update `rust/Justfile`
```
# Packages: bash-validator, voice, agent-switch
```

#### 4. Remove `bin/tmux-fzf-switcher` wrapper

#### 5. Update tmux config

File: `config/tmux/tmux.conf`
Keybindings already use `agent-switch tmux` (lines 119-120), no change needed.

#### 6. Clean up references

- `handoff.md` - remove or update
- `config/tmux/session-order.conf.example` - update comment

### Success Criteria:

#### Automated:
- [ ] `just rust::build` succeeds
- [ ] `just rust::test` succeeds
- [ ] No references to tmux-fzf-switcher in codebase (grep)

#### Manual:
- [ ] Ctrl+` in tmux opens agent-switch picker with Codex status

---

## Testing Strategy

### Unit Tests:
- Socket protocol: `list` command returns valid JSON
- Session cache: concurrent access safety
- Codex file parsing: handles malformed files gracefully

### Integration Tests:
- Daemon starts, responds to list command
- File watcher triggers cache reload
- Track events update cache

### Manual Testing Steps:
1. Start `agent-switch serve` on macOS
2. Open tmux, run Claude/Codex in different windows
3. Verify `agent-switch tmux` shows correct status for both
4. Kill tmux server, verify daemon exits
5. On Linux: test `agent-switch serve --niri` with overlay

## Migration Notes

- Users running tmux-fzf-switcher keybindings need no change (already points to agent-switch tmux)
- Daemon should be started in tmux.conf or shell profile:
  ```
  # In ~/.tmux.conf
  run-shell "agent-switch serve &"
  ```
- Or use tmux's server-ready hook (if available)

## References

- Current niri daemon: `rust/agent-switch/src/niri.rs`
- Current tmux picker: `rust/agent-switch/src/tmux.rs`
- Async Codex loading pattern: `rust/tmux-fzf-switcher/src/main.rs:1049-1105`
- Socket path: `rust/agent-switch/src/track.rs:socket_path()`
- Session state: `rust/agent-switch/src/state.rs`
