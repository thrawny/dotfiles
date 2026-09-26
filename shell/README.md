# Desktop shell

A Quickshell desktop bar, launcher and agents sidebar for Hyprland, using the
shared Monokai theme. Includes quota details and text/image clipboard history.
Niri keeps its existing setup.

## Start

After installing the dotfiles with `just switch`, Hyprland starts the shell on
login. From the repository root:

```sh
just shell::use       # Use Quickshell now
just shell::waybar    # Restore Waybar
```

Walker is still available manually with `walker`.

## Use

- Super+Space opens the launcher. Tab switches apps/clipboard/projects; `?` lists modes.
- Left Alt+P opens projects. Enter focuses an existing project workspace or creates
  one with one terminal. Ctrl+O accepts an absolute directory path or `~/`.
  Projects come from zoxide Git roots, `~/code`, and `~/work/*/code`.
- Ctrl+G on a project asks for a worktree branch. Enter reuses an existing checkout
  or creates `../<project>-worktrees/<branch>`, then opens a workspace named
  `<project>/<branch>`. Local branches work offline; origin branches are fetched
  and tracked. New branches start from origin's default branch, or HEAD when
  there is no origin. Network failures stay visible rather than changing the base.
  Escape returns from path/branch entry; closing during an operation does not
  undo a Git command already running. The CLI and Herdr pickers remain available.
- Ctrl+K moves up; Ctrl+J moves down in every picker. Up/Down and Ctrl+P/N also work.
- Enter opens or copies the selected entry; Escape closes unless entering a path or branch.
- Ctrl+Delete removes a clipboard entry. Copying does not automatically paste.
- Images show thumbnails; selecting one copies the original image bytes.
- Click volume for audio settings, right-click to mute, or scroll to adjust it.
- Click the layout label to switch keyboards. Hover over network or battery for
  connection speeds and power details. Click the ellipsis to expand the laptop tray.
- Click the clock to change its display; right-click to lock.
- Click either quota indicator for usage windows, reset times, pace, spending
  and reset credits. Both providers appear together in the original Quotabar
  layout, with their logos. Failed refreshes keep the last data and label it stale.
- Alt+S or the agents indicator opens the left sidebar. Enter focuses the selected
  thread; Ctrl+J/K moves selection. The footer lists the remaining actions.
  Provider icons and status colors distinguish approval, input, work and completion.
  The global/local scope setting survives closing the sidebar and shell restarts.
  Archive and deletion require confirmation. The daemon keeps tracking when
  the sidebar closes or the shell reloads.
- Click the coffee cup to toggle caffeine. It prevents idle locking, screen-off,
  and idle sleep, survives shell reloads, and turns off at logout. Manual sleep
  and the closed-lid safety timer still apply.

Clipboard history is stored unencrypted in `~/.cache/cliphist/db`. Copied
passwords, tokens and images may remain there after their source app closes.
Cliphist 0.7 records entries up to 5 MB. Image previews use private temporary files
under `$XDG_RUNTIME_DIR/dotfiles-clipboard`, cleared when the picker closes.
The next image request removes abandoned sessions after a crash or reload, and
sessions older than one hour. Preview storage is capped at 32 images and 128 MiB;
copying always prepares the selected original again if needed.

Quotabar, agent-switch and the clipboard image adapter are installed through Nix.
Claude quota data remains visibly unavailable until login. The sidebar uses
the separate `dotfiles-agent-switch.service`.

For development, checks, and troubleshooting, see [AGENTS.md](AGENTS.md).
The [Waybar parity checklist](PARITY.md) records the restored interactions.
