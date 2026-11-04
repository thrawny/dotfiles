# T3 Code on the desktop

The desktop runs T3 Code at boot as your normal user, using your repositories
and provider logins. Configuration lives in `nix/hosts/desktop/t3code.nix`.
Apply changes with `just switch` from the repository root.

Like the [M1](t3code-mac.md), it listens on loopback port 4773 and exposes HTTPS
port 8445 through Tailscale Serve. It is not exposed on the LAN or public internet.
Connect from another tailnet device using the desktop's Tailscale DNS name and
port 8445.

Generate a single-use pairing URL on the desktop to add it to another T3 app:

```sh
t3 pair --tailscale --tailscale-serve-port 8445
```

State and pairing credentials live in `~/.t3/userdata`. Sign in with `codex login`
or `claude auth login` if provider authentication is missing. Update through the
flake, not `t3 update`, `t3 service install`, or the standalone installer.

```sh
systemctl status t3code t3code-tailscale-serve
journalctl -u t3code -n 80
tailscale serve status
```

Logs can contain pairing credentials. Do not publish them without redacting.
The service survives logout, but the computer must stay awake for remote work.
Tailscale SSH is enabled separately in the desktop configuration and uses the
tailnet's SSH access policy rather than a local OpenSSH daemon.
