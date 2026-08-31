# 1. Lua-owned Hyprland project-directory map

Date: 2026-08-31

## Status

Accepted

## Context

Under niri, per-workspace project directories live in niriusd (a niri-only
daemon): the project picker registers a workspace→directory mapping, and
terminal spawns read it back. Hyprland has no such daemon, but several
consumers need the same mapping: the dir-aware `ALT+Return` terminal bind,
`bin/hyprland-project`, and eventually per-workspace scratchpads.

Hyprland 0.56's Lua config is a live runtime with events, timers, queries,
and full stdlib, and `hyprctl eval`/`repl` are first-class entry points into
the live config Lua state from shell scripts. However, `hyprctl reload`
destroys and recreates the whole Lua state, and a reload auto-fires on every
save of any config file (inotify on the main config and every `require`d
file).

Alternatives considered:

- **Shell-owned state file** (picker writes a tsv, scripts read it with awk):
  simplest, but the keybinds live in Lua, which would then have to shell out
  to read its own state; no event-driven cleanup.
- **Derive from the focused window's `/proc/<pid>/cwd`**: no state at all,
  but wrong semantics — a browser-focused workspace reports `$HOME`, not the
  project the workspace was created for.

## Decision

The map is owned by the Hyprland Lua config (`config/hypr/lua/projectdirs.lua`):

- Global functions `set_project_dir(ws, dir)` / `project_dir(ws?)`, callable
  in-process from keybinds and externally via `hyprctl eval` / `hyprctl repl`.
- The Lua table is only a cache. The source of truth is a tsv state file in
  `$XDG_RUNTIME_DIR/hypr-project-dirs`, re-read at config top level — which
  runs on every reload, making reloads survivable for free.
- The state file must never be `require`d or placed under the config
  directory, or every write would itself trigger a full config reload.
- Entries are keyed by workspace name (stable across sessions) and dropped on
  the `workspace.removed` event.

## Consequences

- Keybinds resolve directories in-process with no hyprctl round-trip; shell
  scripts pay one `hyprctl eval` call.
- State survives config reloads but is intentionally per-boot
  (`XDG_RUNTIME_DIR`): reopening a project via the picker re-registers it.
- Anything reading the map from outside depends on the compositor being
  responsive (`hyprctl eval` has a 250 ms watchdog); consumers must tolerate
  an empty answer.
- niri keeps niriusd; the two compositors deliberately have separate
  implementations behind the shared `project-picker` entry point.
