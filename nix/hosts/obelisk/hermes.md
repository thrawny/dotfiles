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
Hermes package, including messaging dependencies and Python package fixes.
Hermes 0.21.0 omitted `hermes_state_holders` and `hermes_state_registry` from its
wheel. `nix/lib/hermes-state-modules.nix` supplies those files from the locked
upstream source through `extraPythonPackages`. Remove this workaround when
upstream includes both modules. The helper skips modules already declared by
upstream so it does not shadow a future packaged copy.

The dashboard listens only on `127.0.0.1:9119`. Nix manages Tailscale Serve's
`svc:hermes` HTTPS proxy. `dashboard.public_url` declares the browser-facing URL
and keeps authentication required despite the loopback listener.
