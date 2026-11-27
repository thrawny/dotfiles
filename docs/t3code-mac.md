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

## Desktop app

The desktop app is the Homebrew cask `t3-code@nightly`. It also uses
`~/.t3` as its T3 home, and the server already owns that home. Home Manager
writes `localEnvironmentEnabled: false` to `~/.t3/userdata/desktop-settings.json`,
so the app starts no backend of its own and only connects to paired servers.
Keep **Settings → Environments → Local environment** turned off. If you turn it on,
the app finds the server's lock on `~/.t3`, shows an error and quits.

Pair the app with each server through **Add environment**:

- This Mac: run `t3 pair` and paste the `http://127.0.0.1:4773/pair#token=…` URL.
- Obelisk: run `ssh obelisk sudo -u t3code t3 pair --base-dir /srv/t3code/.t3code`.
  In the printed URL, replace `http://127.0.0.1:3773` with
  `https://t3code.tailf85bba.ts.net`, then paste it.

Don't add this Mac as an SSH environment, because the app would start a second
server in `~/.t3`. The model default, shortcuts and Monokai theme are server
settings, so the app picks them up from each paired server.

Homebrew updates the app. A Home Manager launch agent sets
`T3CODE_DISABLE_AUTO_UPDATE` and `T3CODE_TELEMETRY_ENABLED=false` in the login
session with `launchctl setenv`, which turns off the app's own updater and
telemetry. The cask declares its own updater, so `brew upgrade` skips it unless
`HOMEBREW_UPGRADE_GREEDY_CASKS` names it. Home Manager sets that variable, so
`brew upgrade` covers the app. Quit and reopen the app after an upgrade.

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

Provider authentication belongs to this Mac. Sign in with `codex login` when
needed. Claude Code authenticates with `CLAUDE_CODE_OAUTH_TOKEN` in
`~/.secrets`, a one-year token from `claude setup-token`. Both zsh and the T3
launcher load that file, so T3 and terminal sessions share one login. After
replacing the token, open a new shell and restart the launch agent. Gauntlet
reviews started from a Claude session cannot inherit the token, so they read it
from `~/.config/gauntlet/claude-oauth-token` (mode 600, the token only); replace
it there too. The service log can contain pairing credentials;
do not publish it without redacting them.
