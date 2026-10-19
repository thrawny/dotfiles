# Forgejo Actions runner

The [runner module](../../modules/forgejo-runner.nix) runs Forgejo Runner as
`forgejo-runner` (UID 3104), with its own rootless Podman socket and state in
`/var/lib/forgejo-runner`. Only `thrawny/thechalkboard` can use its `chalkboard`
label. Jobs run in Node 24 Bookworm containers, one at a time; workflows install
their own pinned Bun and pnpm versions.

The entire account, including container scopes, shares two CPUs and a 3 GiB
memory ceiling without swap. Jobs cannot mount arbitrary host volumes, request
privileged containers, or receive the Podman API socket. This is container
isolation on the shared host kernel, not a VM or a network isolation boundary.

After deploying the module, register once from the repository root:

```sh
just nix::register-forgejo-runner obelisk
```

The recipe generates a repository-scoped shared identity, writes `.runner` as
`0600`, and starts the user service. It preserves an existing identity on later
runs. Neither registration secrets nor deployment credentials belong in Nix.
Deployment secrets are configured separately in the repository's Actions settings.

Inspect on Obelisk as root:

```sh
systemctl --user -M forgejo-runner@ status forgejo-runner.service podman.socket
journalctl _UID=3104 --since '1 hour ago'
systemctl show user-3104.slice -p MemoryCurrent -p MemoryMax -p CPUQuotaPerSecUSec
```

The runner waits for registration before starting. To replace a lost identity,
remove its stale registration in Forgejo first, stop the runner, preserve the
old `.runner` privately, then register again. Do not rotate it during an active
job. Runner shutdown waits up to 45 minutes for work to finish.

Container images are pulled on each job. The Actions cache server is disabled;
there are no persistent dependency caches or host cache mounts yet. Monitor
container storage under the runner account; prune unused images only while idle.
