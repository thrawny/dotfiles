# T3 Code on the M1

Home Manager manages the T3 Code package, its launch agent, and Tailscale Serve.
The M1 opts in through `nix/hosts/thrawnym1/home.nix`; the service configuration
lives in `nix/home/darwin/t3code.nix`. It uses the same pinned nightly package
input as Obelisk and updates through the dotfiles flake. Projects, history, and
pairing credentials live in `~/.t3/userdata`. It uses your Mac repositories and
provider logins.

```sh
just switch-hm
t3 project add ~/code/my-project
```

The service starts at login. Keep the Mac logged in and awake for remote work.
See the fleet guide at `fleet/references/mac-remote-access.md` in the [private skills checkout](private-agent-skills.md) for sleep and restart behavior.

## Add the Mac to another T3 app

Connect both devices to Tailscale, then run:

```sh
t3 pair --tailscale --tailscale-serve-port 8445
```

Paste the pairing URL into **Add environment** in the receiving app. Choose
`thrawnym1` as its name. Pairing links expire and are single-use; generate a new
one for each device. The HTTPS endpoint is
`https://thrawnym1.tailf85bba.ts.net:8445/`.

Tailscale Serve forwards HTTPS port 8445 to loopback port 4773. The Home Manager launch
agent reapplies that mapping at login and retries if Tailscale is not ready.
Change `dotfiles.t3code.port` and `dotfiles.t3code.httpsPort` in the Mac's Home
Manager configuration to use different ports. Remote project access requires
pairing. When changing the HTTPS port, remove the old mapping with
`tailscale serve --https=<old-port> off` after activating the new configuration.

## Service maintenance

Use dotfiles updates and `just switch-hm` to update the service. Do not use
`t3 update`, `t3 service install`, or the standalone installer, which create a
separate installation outside Nix.

Home Manager checks the local server after updating launch agents. If that step
fails after unloading T3, it tries to reload the installed launch agent before
exiting, while still reporting the activation failure. This recovery also keeps
Home Manager's generation cleanup intact.

An independent recovery launch agent also checks every 30 seconds. If an
interrupted activation left T3 unloaded, it reloads the installed launch agent.
It waits while the activation process is alive. Recovery messages go to
`~/.t3/userdata/logs/recovery.log`.

```sh
launchctl print gui/$(id -u)/org.nix-community.home.t3code
launchctl kickstart -k gui/$(id -u)/org.nix-community.home.t3code
tail -n 80 ~/.t3/userdata/logs/launchd.log
codex login status
claude auth status
```

Provider authentication belongs to this Mac. Sign in with `codex login` or
`claude auth login` when needed. The service log can contain pairing credentials;
do not publish it without redacting them.
