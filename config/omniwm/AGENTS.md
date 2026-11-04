# OmniWM Notes

Workspace names must be numbers; `displayName` carries the labels main, web and code.

`settings.toml` is linked to `~/.config/omniwm/settings.toml`; OmniWM reloads edits without `just switch`.
Bindings follow `config/hypr/lua/binds.lua` (niri-like), with the same Option-key chords where OmniWM has an equivalent.

The schema is strict: one unknown or duplicate hotkey `id`, or one missing required key, rejects the whole file. Keep every default key.
To see the current defaults and action IDs, move the file aside, start OmniWM and read the file it writes.

Differences from the Hyprland binds and AeroSpace:

- Every workspace uses the `niri` layout (scrolling columns). `toggleWorkspaceLayout` (Hyprland's Super+L) is unbound.
- Option+F toggles the full-width column and Option+Shift+F is OmniWM fullscreen. Option+Minus and Option+Equal resize the column by 10 percent, Option+Backslash cycles the 1/3, 1/2 and 2/3 presets.
- Unavailable in 0.7.6: new Ghostty window (Option+Return), consume from the left (`[`), directional monitor focus, window groups' next (Option+Shift+G), the scratchpad terminal and Option+B.
- Service mode and the Vowen follow-workspace script from AeroSpace have no equivalent.
- Monitors are placed by `[monitors] ranking`: first connected entry is the main monitor, the next is secondary. `code` (workspace 3) uses secondary.
