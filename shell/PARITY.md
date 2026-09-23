# Waybar parity

Audit against `nix/home/nixos/waybar.nix`. Hyprland uses Quickshell; Niri keeps
its existing Waybar configuration. The appearance follows the current shell.

| Function | Quickshell implementation |
| --- | --- |
| Workspace names, order, active and urgent states, click to focus | Per-monitor WorkspaceList and Workspaces; global ordinal keyboard shortcuts remain in Hyprland |
| Active window title on external displays | Per-monitor application and title; hidden on the laptop and narrow displays |
| Keyboard layout indicator and click to cycle | Keyboard service queries Hyprland and follows layout events; AU/SE labels |
| Network connection, Wi-Fi strength, frequency, receive/send rates | Native NetworkManager state, nmcli frequency query, native FileView of interface counters; click opens connection editor |
| Audio device and volume tooltip, scroll in 5% steps, pavucontrol | Left-click opens settings; right-click mutes |
| Battery capacity, charging state, low warnings and power draw | UPower; tooltip also shows remaining time when available |
| Clock date/time and alternate weekday | Click changes display; right-click locks |
| Tray icons, tooltips, application/menu/secondary actions, scroll | Native SystemTray and DBus menus |
| Compact tray expansion and passive filtering | Click the ellipsis on compact screens; external screens show all icons |
| Caffeine indication and toggle | Separate systemd inhibitor survives UI reloads; existing active state preserved |
| Claude/Codex quota indicators and details | Rust snapshot and QML quota popup, including stale/error state, pace, cost and credits |
| Agent attention indicator and sidebar | Rust daemon state/actions and QML sidebar; focus, new, settle, archive, read, rename, reorder, scopes and shelves |

No Waybar interaction is intentionally deferred. The clock lock shortcut and
audio mute interaction added by the initial Quickshell version remain available
on right-click.
