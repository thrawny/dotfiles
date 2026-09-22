# Desktop shell

A Quickshell bar and app launcher for Hyprland, using the shared Monokai theme.
Includes text clipboard history. Niri keeps its existing setup.

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
- Click volume to mute or scroll to adjust it. Click the clock to lock.

Clipboard history is text-only and stored unencrypted in `~/.cache/cliphist/db`.
Copied passwords or tokens may remain there after their source app closes.

For development, checks, and troubleshooting, see [AGENTS.md](AGENTS.md).
