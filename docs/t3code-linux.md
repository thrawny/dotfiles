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
