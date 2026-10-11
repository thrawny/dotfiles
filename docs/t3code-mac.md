# T3 Code on the M1

The Mac runs the official stable T3 Code CLI as a per-user launch agent. It uses
the logged-in user's repositories and provider logins. The installer keeps its
runtime under `~/.t3/runtime`; projects and history live in `~/.t3/userdata`.
This installation updates separately from the Nix-packaged server on Obelisk.

```sh
t3 service status
t3 update
t3 project add ~/code/my-project
```

The service starts at login. Keep the Mac logged in and awake for remote work.
See the fleet guide at `fleet/references/mac-remote-access.md` in the [private skills checkout](private-agent-skills.md) for sleep and restart behavior.

## Add the Mac to another T3 app

Connect both devices to Tailscale, then run:

```sh
t3 pair --tailscale
```

Paste the pairing URL into **Add environment** in the receiving app. Choose
`thrawnym1` as its name. Pairing links expire and are single-use; generate a new
one for each device. The HTTPS endpoint is
`https://thrawnym1.tailf85bba.ts.net/`.

Tailscale Serve forwards HTTPS to `127.0.0.1:3773`. Its mapping survives restarts.
The server requires pairing before a remote client can access projects.

## Service maintenance

The launch agent is `~/Library/LaunchAgents/com.t3tools.t3code.service.plist`.
Its PATH must include `~/.nix-profile/bin`, `~/.local/bin`, `~/dotfiles/bin`,
`/nix/var/nix/profiles/default/bin`, `/opt/homebrew/bin`,
`/run/current-system/sw/bin`, and the standard macOS command directories.
Check it after reinstalling the service from a temporary agent environment.

```sh
t3 service restart
tail -n 80 ~/.t3/userdata/logs/boot-service.log
codex login status
claude auth status
```

Provider authentication belongs to this Mac. Sign in with `codex login` or
`claude auth login` when needed. The service log can contain pairing credentials;
do not publish it without redacting them.

The upstream [background-service guide](https://github.com/pingdotgg/t3code/blob/main/docs/user/background-service.md)
describes updates and removal.
