# Disk headroom

Obelisk reserves **15 GiB physically free** on its ext4 root filesystem for root.
Ordinary service users cannot allocate that space. They receive a disk-full error
when they reach the reserve, so this protects recovery capacity rather than
promising uninterrupted writes. Arbitrary privileged writes can still consume it.

`storage.nix` installs these controls:

- Every five minutes, collect unused Nix paths when physical free space falls below
  20 GiB, aiming for 25 GiB. Generations older than one day may be removed; current
  and booted systems remain protected by Nix roots. Live data is never deleted.
- Refuse deployment imports and backup staging when their estimated size plus
  overhead would cross the 15 GiB floor. Estimates do not serialize concurrent
  writers; the filesystem reserve protects against ordinary writers regardless.
- Limit the journal to 256 MiB and configure Nix's automatic GC thresholds.
- Disable local Nix build jobs. Build the system elsewhere, using the Mac's Linux
  VM builder when deploying from macOS. Use `just nix::plan-deploy obelisk` and
  `just nix::deploy obelisk`; both check space before copying the closure.

`df`'s Available column excludes the reserve. For example, 5 GiB Available means
approximately 20 GiB physically free with this policy. Check physical space with:

```sh
ssh root@obelisk "stat -f -c '%f %S' /" # multiply free blocks by block size
ssh root@obelisk 'obelisk-storage check --required-bytes 0'
ssh root@obelisk 'systemctl status obelisk-storage.timer obelisk-storage-reserve'
ssh root@obelisk 'journalctl -u obelisk-storage -n 30'
```

If cleanup cannot restore 20 GiB, inspect retained application data and increase
capacity or configure its retention. Do not automatically delete transcripts,
worktrees, Podman volumes, or active release directories. T3's own retention and
[encrypted transcript backups](backup.md) handle their respective data.

On 2026-10-27, unused dotfiles direnv roots were released and Nix GC run; Go module,
npm download and Bun install caches were removed. These are regenerable caches,
not application history. Unused pnpm packages were pruned with pnpm itself;
`node_modules` caches in releases older than a day were removed while retaining
the current release, three newest releases and any process working directory.
All release source files remain. The initial root filesystem was about 74 GiB, with
26 GiB in Nix and 22 GiB under T3, so ongoing monitoring and capacity remain useful.

The reserve service only changes ext4's reserved-block count after verifying at
least 16 GiB physically free. It persists across boots. Reserve changes do not
allocate files or erase data. A larger disk provides more working room above the
same floor; object storage is useful for backups, not a replacement for local
Nix closures, databases and working trees.
