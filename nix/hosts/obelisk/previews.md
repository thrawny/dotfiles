# Private web previews on Obelisk

Portless is available to local users, including `thrawny`, `t3code`, and `openclaw`. Tailscale sharing is on by default.

Run from your project or worktree:

```sh
portless
portless myapp pnpm dev
portless list
```

Share a static build without changing the project:

```sh
portless report sh -c 'exec python3 -m http.server "$PORT" --bind 127.0.0.1 --directory ./dist'
```

Return the printed Tailscale URL, not the `.localhost` URL. Each preview has its
own HTTPS port on `obelisk.tailf85bba.ts.net`, at `/`. HTTPS ports are 443 and
8443-8499; access depends on the tailnet policy. Frameworks with host or origin
checks may need this hostname in their allowlist.

Keep long-lived previews in a persistent terminal session. Exiting Portless stops
its child server and removes the HTTPS registration. The per-user local proxy
can remain running; `portless proxy stop` stops it. Set `PORTLESS_TAILSCALE=0`
for a local-only run.

## Permissions and state

`nix/modules/portless.nix` configures the package from `thrawny-pkgs` and a
socket-activated registration broker. Each UID has a distinct local proxy port
and private Portless state under `$HOME/.portless`. The local proxy uses HTTP;
Tailscale provides browser-facing HTTPS. No local CA installation, hosts-file
changes, sudo or Tailscale operator grant is needed.

The broker permits only private loopback HTTP proxies and their cleanup. It
checks the caller's kernel UID and serializes changes with the same lock as the
named Tailscale Services. It rejects Funnel, files, remote targets and changes
to named Services. Users cannot overwrite or stop another UID's preview.
Previews do not isolate applications from other local users or permitted tailnet
members.

Root-owned leases and local proxy assignments live in
`/var/lib/portless/ownership.json`. If a registration is interrupted, its port
stays reserved until its owner cleans it up. To remove a stranded owned preview:

```sh
portless-tailscale serve --yes --https=8443 off
```

Root can remove any broker-owned preview with the same command. Cleanup refuses
endpoints changed outside Portless. Do not use `tailscale serve reset`.

## Checks

From the dotfiles repository root:

```sh
just nix::check-tailscale-serve
just nix::tailscale-serve-health
```

These checks verify the existing named Services, not a preview. To check a
preview, run one of the commands above, open its printed Tailscale URL, then
stop Portless and confirm that the URL no longer serves the application.
