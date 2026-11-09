# OmniWM Notes

Workspace names must be numbers; `displayName` carries the labels main, web and code.

`settings.toml` is linked to `~/.config/omniwm/settings.toml`; OmniWM reloads edits without `just switch`.
Bindings follow `config/hypr/lua/binds.lua` (niri-like), with the same Option-key chords where OmniWM has an equivalent.

The schema is strict: one unknown or duplicate hotkey `id`, or one missing required key, rejects the whole file. Keep every default key.
To see the current defaults and action IDs, move the file aside, start OmniWM and read the file it writes.
The written defaults leave out some valid IDs, such as `consumeOrExpelWindowLeft` and `consumeOrExpelWindowRight`. A rejected file is moved to `settings.toml.corrupt`.

Differences from the Hyprland binds and AeroSpace:

- Every workspace uses the `niri` layout (scrolling columns). `toggleWorkspaceLayout` (Hyprland's Super+L) is unbound.
- Option+F toggles the full-width column and Option+Shift+F is OmniWM fullscreen. Option+Minus and Option+Equal resize the column by 10 percent, Option+Backslash cycles the 1/3, 1/2 and 2/3 presets.
- Unavailable in 0.7.6: new Ghostty window (Option+Return), directional monitor focus, window groups' next (Option+Shift+G), Option+Shift+W (close the workspace) and Option+B.
- Number keys use fixed workspace IDs, not Hyprland's position in the workspace list. OmniWM's `switchWorkspaceSlot.N` counts per monitor, so it would move `code` off Option+3.
- Option+scroll has no workspace switch. Option+Shift+scroll scrolls columns (`scrollModifierKey`).
- Scratchpad slots (`toggleScratchpad.N`) exist but are unbound: a window must be assigned by hand, not matched by app.
- Service mode and the Vowen follow-workspace script from AeroSpace have no equivalent.
- Monitors are placed by `[monitors] ranking`: first connected entry is the main monitor, the next is secondary. `code` (workspace 3) uses secondary.
