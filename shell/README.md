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
- Click the coffee cup for keep-awake sessions and rules. Right-click toggles
  an indefinite manual session. Screen sleep and locking remain enabled by default.
  Sessions survive shell reloads and end at logout.

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

## Keep awake

The separate `dotfiles-keepawake.service` supports Amphetamine's core session
types: indefinite, duration, until a clock time, while an app or PID runs, and
while a file downloads. Its configurable triggers cover Wi-Fi, running processes,
AC power, external displays, and weekly schedules. The original app's
[feature listing](https://apps.apple.com/us/app/amphetamine/id937984704) is the
reference; there is no published usage ranking for individual features.

On first start, the service creates `~/.config/keepawake/config.toml` from the
[example](../config/keepawake/config.example.toml). All example rules start
disabled. Click **Edit rules**, set the Wi-Fi SSID, and enable that rule:

```toml
version = 1
battery_floor = 20
keep_display_awake = false

[[rules]]
name = "Home Wi-Fi"
enabled = true
[rules.when]
wifi_ssid = "YOUR_WIFI_SSID"
```

The Wi-Fi rule applies only while connected to that SSID. All sessions and rules
release their holds at or below the battery floor when unplugged, and have no
battery limit on AC. Manual sessions end at the floor; automatic rules can
reactivate when their conditions and power requirements match again.

Each rule's `when` conditions use AND by default; `match = "any"` uses OR.
Supported conditions are `wifi_ssid` and `process` strings, `ac_power` and
`external_display` booleans, and a `schedule` with `days`, `start`, and `end`.
Process names match the current user's processes, even in the background.
Schedules use local time, include their start and exclude their end. An overnight
window belongs to its start day. Rules may override `keep_display_awake` or
`allow_lid_closed`; both default to false. Configuration reloads every five
seconds. Invalid configuration releases all holds and shows the error.

The popup offers time presets, per-session end buttons, countdowns, and **Pause
all**. Ending a manual session leaves automatic rules active. Pausing temporarily
releases every hold; running timers still expire. Rules and controls are also
available from the terminal:

```sh
keepawake start                         # Indefinitely, subject to the battery floor
keepawake start --duration 1h30m
keepawake start --until 17:00            # Tomorrow if that time has already passed
keepawake start --process obs            # Process must already be running
keepawake start --pid 1234
keepawake start --file ~/Downloads/file.part --quiet-seconds 60
keepawake start --duration 2h --keep-display-awake --allow-lid-closed
keepawake status                        # JSON, including session IDs and rule reasons
keepawake stop --id SESSION_ID
keepawake stop                          # End all manual sessions
keepawake pause                         # Pause manual sessions and automatic rules
keepawake resume
keepawake check-config
```

File-download sessions watch an existing file's size and modification time.
They end after the configured quiet period or if the file disappears, including
when a browser renames its temporary file. A stalled download can therefore end
the session; this is not a browser download-progress API. End notifications can
be disabled with `notifications = false`.

The service gates hypridle's automatic suspend and display-off timeouts. It does
not block manual sleep, screen locking, or critical-battery hibernation. Optional
closed-lid sessions defer the undocked-laptop safety timer while power permits;
ordinary sessions leave that safety timer active. A missing, dead, or stale
daemon permits normal sleep. Changes to power and Wi-Fi are sampled every five
seconds, and a deferred idle action is retried every ten seconds. Sessions and
the pause state clear when the service stops, including at logout. Manual sessions
also end after system sleep; automatic rules reevaluate on wake.
