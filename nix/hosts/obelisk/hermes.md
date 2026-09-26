# Hermes on Obelisk

Dashboard: https://hermes.tailf85bba.ts.net/

Sign in as `admin`. The generated password is stored on Obelisk at
`/srv/agents/hermes/home/.hermes/dashboard-password`, readable only by root.
The bootstrap preserves existing credentials across deployments.

## Checks

Run from the repository root:

```sh
just nix::check-hermes-web
just nix::tailscale-serve-health
ssh root@obelisk 'systemctl show hermes-dashboard hermes-agent -p Id -p ActiveState -p SubState -p NRestarts'
```

`check-hermes-web` starts the actual packaged dashboard in an isolated temporary
home without network access. It checks the login page, rejects anonymous API
access and an incorrect password, then authenticates and reads sessions.

## Packaging and proxy

`nix/modules/agents.nix` gives the dashboard and gateway the same effective
Hermes package, including messaging dependencies. Upstream's `setup.py` now
includes all root Python modules in the wheel, including the state modules
that previously needed a local workaround.

The dashboard listens only on `127.0.0.1:9119`. Nix manages Tailscale Serve's
`svc:hermes` HTTPS proxy. `dashboard.public_url` declares the browser-facing URL
and keeps authentication required despite the loopback listener.
