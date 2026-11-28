# Rex

[Rex](https://www.superlogical.com/rex/docs) is Superlogical's terminal multiplexer. The M1 runs the Rex app, and z13 runs a personal Rex server that the app reaches over SSH.

## Install

- **M1 app.** Install the DMG from `https://blob.superlogical.com/download/rex-app/preview/latest.dmg` into `/Applications`. The app updates itself, so Nix leaves it alone.
- **Home Manager.** `dotfiles.rex.enable` installs the `rex` CLI from the Rex flake, Rex's terminfo entry, and `~/.config/rex/init.lua` as a link to `config/rex/init.lua`. It is on for the M1 and z13.
- **z13 server.** `dotfiles.rex.server` runs the personal server as the systemd user unit `rex`. Linger keeps it running after logout.

The flake input tracks the preview channel, the only channel with releases so far. `nix flake update rex` from `nix/` moves it to the newest preview. The app and the server can run different versions, and the server refuses a client that is too far apart.

## Connecting

The app's local server declares z13 in `init.lua` as `ssh://thrawny@thrawny-z13`. If the app does not list it, choose Add Remote Host and enter that address. Rex then runs `rex` on z13 over SSH. Both machines take SSH through Tailscale SSH, which signs you in by your tailnet identity, so Rex needs no key and no port of its own.

After `just switch-hm` on z13, check the server:

```sh
systemctl --user status rex
rex server status
```

From the M1, run `rex -S ssh://thrawny@thrawny-z13 ls`.

Rex for iOS connects the same way. With the Tailscale app connected, add `ssh://thrawny@thrawny-z13` and `ssh://thrawny@thrawnym1` under Settings > Remote Hosts. The M1 address reaches the Rex app's own server, which keeps running with the app's window closed while the Mac is awake. To match the Mac's colors, paste the color lines of `~/.config/ghostty/config` into Settings > Themes > Import Theme: `background`, `foreground`, `cursor-color`, `cursor-text`, the two `selection-` lines and the 16 `palette` lines.

## Agent keys

`init.lua` gives Rex the agent keys of the [Herdr desktop app](herdr-app.md). An agent is a terminal whose program reports its status to Rex, as Claude Code does. Agents are numbered in sidebar order. Each server runs the file for its own sessions, so the keys act on the host the app is showing.

| Keys | Action |
| --- | --- |
| Cmd+1–9 | Focus the numbered agent |
| Cmd+J/K | Next / previous agent |
| Cmd+O | Cycle blocked, done, working agents; oldest first in each tier |
| Cmd+Shift+J/K | Move the focused session down / up |
| Cmd+B | Toggle the sidebar |

These replace Rex's Cmd+1–9 tab keys and its Cmd+K session switcher. Cmd+P still opens Rex's go-to picker for sessions, tabs and panes. `rex config reload` applies an edit to `init.lua`.

The sidebar's look, such as vertical tabs and the Activity grouping, stays an app setting.

## Look

On the Mac, every Home Manager switch writes the app's look into its defaults: Ghostty's colors as the dark theme "Dotfiles Monokai", Ghostty's font, size and padding, and tabs in a sidebar on the left. Rex's own default puts the tabs above the panes, with no sidebar. `scripts/rex-app-defaults.py` writes only these settings and replaces only that one custom theme. A running app shows the change after a restart.

## moto

moto runs workers in Rex when it starts from a Rex terminal. Each worker gets a session of its own, named after the worker, so the sidebar shows one row per worker. Claude Code's status reports give moto the agent's state. `spawn-session --focus` switches the app only while Remote Control is on in the app's General settings.

## Not set up

- `rex skill setup` would write a Claude skill and hook into this repository's `config/claude`, so it stays unrun.
- The SSH guard needs Home Manager to own `~/.ssh/config`. Without it, Rex terminals use `TERM=xterm-256color`. `rex terminfo setup` adds the guard to a hand-kept `~/.ssh/config`.
