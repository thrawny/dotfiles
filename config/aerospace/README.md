# AeroSpace on macOS

Requires AeroSpace 0.21.3 or newer and Ghostty 1.3 or newer. Home Manager links
`aerospace.toml` to `~/.aerospace.toml`; edits take effect without `just switch`.
Reload once manually after upgrading to enable automatic reload on save.

## Keybindings

- Alt-Enter opens a Ghostty window. Allow macOS Automation access when prompted.
- Alt-W closes a window; Alt-F uses AeroSpace fullscreen; Alt-V toggles floating.
- Alt-M and Alt-Tab toggle previous focus; Alt-Shift-M toggles the previous workspace.
- Alt-HJKL focuses tiled windows; Alt-Shift-HJKL swaps windows.
- Alt-Ctrl-HJKL focuses monitors; adding Shift moves the window and follows it.
- Alt-Cmd-HJKL moves the whole workspace to another monitor.
- Alt-Minus/Equal resizes width by 50 pixels; adding Shift resizes height.
- Alt-1/2/3 selects main/web/dotfiles; Alt-4 through Alt-0 selects 4 through 10.
  Adding Shift moves the focused window there and follows it. Alt-B selects web.
- Alt-Shift-Semicolon enters rescue mode. Esc reloads and exits; R resets the tree
  and exits.

Only main/web/dotfiles persist when empty. No workspace is pinned to a monitor.
Chat apps open on main. Finder and Preview float where opened. Helium and other
normal apps stay where launched and use the default tiling behavior. AeroSpace
handles dialogs and Wispr Flow popups without blanket app rules.

Scratchpads, monitor history, workspace cycling, project selection, app jumps,
bulk-close and niri-specific column controls are deliberately not bound.

## Validation

Run `just test-aerospace` for portable configuration and shell-syntax checks.
On the Mac, confirm `aerospace config --config-path` points to this configuration,
then run `just check-aerospace` to validate it with AeroSpace's own parser without
applying changes. Enter rescue mode and press Esc to reload.

Smoke-test Alt-Enter with Ghostty stopped, running and running with no windows.
Also check hover focus with pointer warping, window swaps, monitor movement,
workspace moves, floating Finder/Preview windows, chat routing and Wispr Flow.
Portable tests cannot validate AppleScript or actual macOS window behavior.
