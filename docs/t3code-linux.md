# T3 Code on the Z13

Nix manages the pinned nightly T3 package, the `t3code` user service, and
Tailscale Serve. Like the M1, it uses your repositories and provider logins.
State, history, and pairing credentials live in `~/.t3/userdata`.

Apply the configuration from the dotfiles root:

```sh
just switch
t3 project add ~/code/my-project
```

The server starts at boot and stays available after logout. Keep the laptop
awake for remote work; this setup does not change suspend behavior.

## Pair another T3 app

Connect both devices to Tailscale, then run:

```sh
t3 pair --tailscale --tailscale-serve-port 8445
```

Paste the single-use pairing URL into **Add environment** in the receiving app.
The endpoint is `https://thrawny-z13.tailf85bba.ts.net:8445/`, forwarding to
loopback port 4773. Port 8445 is tailnet-only; the existing port 443 Funnel
mapping is unchanged. Remote project access requires pairing.

For app credentials shared across worktrees, see [app credential setup](t3-app-secrets.md).

## Desktop client

`t3code-desktop-nightly` uses `~/.t3-desktop` so it does not contend with the
background server for `~/.t3`. Keep **Settings → Environments → Local environment**
disabled and pair the desktop with the servers you want to use. Pairings stay in
the app's encrypted connection catalog, not in this public repository.

Model defaults and shortcuts live in
[`config/t3code/preferences.json`](../config/t3code/preferences.json). New threads
default to **Sol 6.1 / High** unless a project has its own override. Nix activation
reapplies these preferences; apply them live without a server restart with
`just sync-t3code-preferences` (Z13), `just sync-t3code-preferences thrawnym1`, or
`just sync-t3code-preferences obelisk`.

Cmd means left Super on Linux and Command on macOS. Native Ctrl shortcuts remain.

| Shortcut | Action |
| --- | --- |
| Cmd+P | New thread |
| Cmd+Shift+P | Command palette |
| Cmd+J / Cmd+K | Next / previous thread |
| Ctrl+Shift+H / Ctrl+Shift+L | Previous / next thread |
| Cmd+1–9 | Jump to thread |
| Cmd+B | Toggle sidebar |
| Cmd+M / Cmd+Shift+M | Next / previous workspace focus |
| Cmd+Enter | Split the focused terminal right |
| Cmd+Shift+Enter | Split the focused terminal down; otherwise new thread |

See [keyboard rules](keyboard-rules.md) for modifier ownership and reserved keys.

## Maintenance

Update through dotfiles and `just switch` (or `just switch-hm` for package
and user-service changes only). Do not use `t3 update`, `t3 service install`,
or the standalone installer.

```sh
systemctl --user status t3code
systemctl --user restart t3code
journalctl --user -u t3code -n 80
sudo systemctl status t3code-tailscale-serve
tailscale serve status
codex login status
claude auth status
```

Sign in with `codex login` or `claude auth login` if needed. Logs can contain
pairing credentials; redact them before sharing.

The user-service module is `nix/home/nixos/t3code.nix`; the host enables it,
user lingering, and the root-owned Tailscale mapping in
`nix/hosts/thrawny-z13/default.nix`. Removing the Serve service leaves its
persistent mapping in place; explicitly remove it with
`sudo tailscale serve --https=8445 off` when decommissioning it.
