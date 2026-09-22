# Desktop shell

A compact Quickshell bar and launcher for Hyprland, developed alongside the dotfiles.
It uses the existing Monokai theme, without shadows or animated transitions.
Niri keeps Waybar for now.

Run from the repository root:

```sh
just shell::dev           # Foreground, hot reload; leaves Waybar running
just shell::use           # Switch to Quickshell after its readiness check
just shell::use waybar    # Restore Waybar and stop this Quickshell config
just shell::check
just shell::fmt
```

Home Manager installs the pinned runtime and `dotfiles-bar` launcher. Hyprland
starts it on login. QML edits apply immediately; Nix changes need `just switch`.
Quickshell logs are available with `quickshell log`.

The bar shows workspace positions matching Alt+1 through Alt+0, a system tray,
network, volume, battery, and clock. Workspace labels scroll horizontally when
space is tight. Click volume to mute, scroll to adjust it, click network to open
connection settings, and right-click tray icons for their menus. Clicking the
clock locks the screen. Battery is hidden on machines without one.

## Launcher

Super+Space opens application search. Tab switches between applications and
clipboard history; type `?` to choose a mode. Up/Down or Ctrl+P/N select a result,
Enter launches or copies it, and Escape or Super+Space closes the launcher.
Ctrl+Delete removes the selected clipboard entry. Terminal apps open in Ghostty.

Clipboard history uses cliphist for text and images. Image entries show a text
summary for now. Selecting an entry copies it without pasting into the focused
app. History starts fresh; Walker/Elephant's existing history is not imported.
Cliphist stores unencrypted history in `~/.cache/cliphist/db`, so copied content
can remain there after its source app closes. Offers marked sensitive are skipped.

Home Manager installs the clipboard helpers. Hyprland starts text/image watchers
as user services, which stop at logout. Niri keeps its existing launcher setup.
Walker stays installed as a fallback if Quickshell is stopped; `walker` also opens
it directly. Mako, wpaperd, swayOSD, hyprlock, and agent-switch remain separate.
Agent/quota indicators, a calendar, and the agent sidebar are not implemented yet.

## Structure

- `components/`: shared controls, independent of compositor details.
- `services/`: theme and live system state. `Workspaces.qml` is the Hyprland adapter.
- `modules/bar/`: panel windows and bar widgets, one panel per screen.
- `modules/launcher/`: application search and clipboard picker.
- `tests/`: workspace, battery, bar handoff, search, and isolated clipboard tests.

Colors come only from `~/.config/dotfiles/theme.json`. A bad theme reload keeps
the last valid palette; an unavailable initial theme fails the readiness check.
Workspace ordering is global across monitors, sorted by ID with special
workspaces excluded, matching `config/hypr/lua/binds.lua`.

The future agent sidebar can consume the agent-switch daemon through a service
adapter without putting hook tracking or transcript parsing in the QML UI.
