# OmniWM Notes

Workspace names must be numbers; `displayName` carries the labels main, web and code.

`settings.toml` is linked to `~/.config/omniwm/settings.toml`; OmniWM reloads edits without `just switch`.
It was converted from `config/aerospace/aerospace.toml`, with the same Option-key chords where OmniWM has an equivalent.

The schema is strict: one unknown or duplicate hotkey `id`, or one missing required key, rejects the whole file. Keep every default key.
To see the current defaults and action IDs, move the file aside, start OmniWM and read the file it writes.

Differences from AeroSpace:

- Every workspace uses the `niri` layout (scrolling columns), not AeroSpace tiles. `toggleSplit` is unbound: it is dwindle-only. Option+Minus/Equal change the column width and Option+Shift+Minus/Equal the window height, in 10 percent steps.
- No chord opens a new Ghostty window: OmniWM 0.7.6 has no `openApp` action.
- `Option+B` (web workspace) is unbound: an action takes one chord only.
- Directional monitor focus, the service mode and the Vowen follow-workspace script have no equivalent.
- Monitors are placed by `[monitors] ranking`: first connected entry is the main monitor, the next is secondary. `code` (workspace 3) uses secondary.
