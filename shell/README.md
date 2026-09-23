# Desktop shell

A Quickshell desktop bar, launcher and agents sidebar for Hyprland, using the
shared Monokai theme. Includes quota details and text clipboard history. Niri
keeps its existing setup.

## Start

After installing the dotfiles with `just switch`, Hyprland starts the shell on
login. From the repository root:

```sh
just shell::use       # Use Quickshell now
just shell::waybar    # Restore Waybar
```

Walker is still available manually with `walker`.

## Use

- Super+Space opens the launcher. Tab switches apps/clipboard; `?` lists modes.
- Ctrl+K moves up; Ctrl+J moves down in every picker. Up/Down and Ctrl+P/N also work.
- Enter launches or copies the selected entry; Escape closes.
- Ctrl+Delete removes a clipboard entry. Copying does not automatically paste.
- Click volume for audio settings, right-click to mute, or scroll to adjust it.
- Click the layout label to switch keyboards. Hover over network or battery for
  connection speeds and power details. Click the ellipsis to expand the laptop tray.
- Click the clock to change its display; right-click to lock.
- Click either quota indicator for usage windows, reset times, pace, spending
  and reset credits. Failed refreshes keep the last data and label it stale.
- Alt+S or the agents indicator opens the sidebar. Enter focuses the selected
  thread; Ctrl+J/K moves selection. The footer lists the remaining actions.
  Archive and deletion require confirmation. The daemon keeps tracking when
  the sidebar closes or the shell reloads.
- Click the coffee cup to toggle caffeine. It prevents idle locking, screen-off,
  and idle sleep, survives shell reloads, and turns off at logout. Manual sleep
  and the closed-lid safety timer still apply.

Clipboard history is text-only and stored unencrypted in `~/.cache/cliphist/db`.
Copied passwords or tokens may remain there after their source app closes.

Quotabar and agent-switch are installed from revisions pinned in Nix. Claude
quota access needs `claude auth login`; the sidebar uses the separate
`dotfiles-agent-switch.service`.

For development, checks, and troubleshooting, see [AGENTS.md](AGENTS.md).
The [Waybar parity checklist](PARITY.md) records the restored interactions.
