# Forgejo access and troubleshooting

Forgejo runs on `127.0.0.1:3000` and is published at
`https://forgejo.tailf85bba.ts.net/` through the Tailscale Service `svc:forgejo`.
Configuration lives in [the Forgejo module](../../modules/forgejo.nix) and
[the Tailscale Serve module](../../modules/tailscale-serve.nix).
See [runner operations](forgejo-runner.md) and [backup recovery](backup.md).

## One device times out while Forgejo is healthy

On 2026-10-27, Safari on an iPhone timed out at the Forgejo URL despite an
active Tailscale connection. The same phone could open an ordinary Obelisk
HTTPS endpoint. Forgejo's loopback endpoint and its service URL returned HTTP
200 from the Mac, including explicit IPv4 and IPv6 checks. Obelisk was the only
advertised host for the Forgejo service.

Refreshing the service advertisement restored the original URL on the iPhone:

```sh
ssh root@obelisk 'systemctl restart tailscale-serve-forgejo.service'
```

This refreshes the Tailscale Serve configuration for `svc:forgejo`; it does not
restart Forgejo or the Tailscale daemon. The result was consistent with a stale
service route or advertisement, but the underlying cause was not established.
Do not infer that a successful request from another device proves the affected
device can reach the service. Confirm recovery on that device.

Before refreshing, check the application and advertisement:

```sh
ssh root@obelisk 'systemctl is-active forgejo tailscaled tailscale-serve-forgejo; curl --max-time 10 -sS -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1:3000/; tailscale serve status'
curl --max-time 10 -sS -o /dev/null -w 'HTTP %{http_code}\n' https://forgejo.tailf85bba.ts.net/
```

## Temporary direct-host fallback

To distinguish a virtual service route failure from general phone-to-host
connectivity, expose Forgejo on an unused ordinary Obelisk HTTPS port. Port
8448 was used during this incident. Check `tailscale serve status` first so an
existing mapping is not overwritten. Keep the shared Serve configuration lock:

```sh
ssh root@obelisk 'flock --exclusive --wait 60 /run/lock/dotfiles-tailscale-serve.lock tailscale serve --bg --yes --https=8448 http://127.0.0.1:3000'
```

Open `https://obelisk.tailf85bba.ts.net:8448/` on the affected device. This stays
tailnet-only and bypasses the virtual service address. It does not change
Forgejo's canonical URL, so some links may still lead to the original address.
The mapping is imperative, outside Nix configuration; do not rely on it as a
permanent endpoint. It was left enabled after this incident as a fallback.
Remove it when no longer needed:

```sh
ssh root@obelisk 'flock --exclusive --wait 60 /run/lock/dotfiles-tailscale-serve.lock tailscale serve --https=8448 off'
```
