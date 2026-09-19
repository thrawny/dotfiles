# M1 Air remote access

`thrawnym1` uses nix-darwin with integrated Home Manager. Determinate still owns
the Nix daemon. The configuration runs the open-source `tailscaled` as a root
launch daemon at boot and restarts it if it exits. This is the macOS variant
that supports the [Tailscale SSH server](https://tailscale.com/docs/features/tailscale-ssh).
macOS Remote Login does not need to be enabled for it.

## Activate nix-darwin

Run these from `/Users/thrawny/dotfiles` on the Mac:

```sh
just install-nix-caches
just build-darwin
just bootstrap-darwin
```

Cache installation and bootstrap need your local administrator password. The
bootstrap also ensures the repo's binary caches are installed before building,
so `just bootstrap-darwin` alone is enough if you want to build and activate in
one step. Remove any Tailscale
GUI app first, as the bootstrap checks require. Do this locally because replacing
an existing Tailscale client interrupts its connection. Avoid running a Homebrew
Tailscale daemon alongside the Nix daemon.

Open a new terminal after activation. Future updates use `just switch`, which
switches nix-darwin and Home Manager together on this host. The standalone
`homeConfigurations.thrawnym1` target remains available for migration recovery.

## Sign in and enable SSH

```sh
just tailscale-login
```

Open the printed login URL and authenticate to your tailnet. This runs
`tailscale up --ssh`; the setting survives daemon restarts. No auth key belongs
in this repository. If the device was already configured with non-default
Tailscale preferences, use `sudo tailscale set --ssh` to preserve those settings.

Check the daemon and the assigned address:

```sh
sudo launchctl print system/com.tailscale.tailscaled
tailscale status
tailscale ip -4
```

From another signed-in tailnet device:

```sh
ssh thrawny@thrawnym1
```

Use the `100.x.y.z` address from `tailscale ip -4` if the name does not resolve.
The daemon variant has different DNS behavior from the GUI app. The nix-darwin
module configures a resolver for `*.ts.net`; a short hostname may still need the
tailnet's full DNS name or an IP address. Do not change global DNS just to test SSH.

The [tailnet policy](https://tailscale.com/docs/features/tailscale-ssh) must permit
both network access to this device on TCP port 22 and Tailscale SSH access as
`thrawny`. For two devices owned by your same Tailscale account, a suitable SSH
rule is:

```json
{
  "action": "check",
  "src": ["autogroup:member"],
  "dst": ["autogroup:self"],
  "users": ["thrawny"]
}
```

Merge that rule into the existing `ssh` array only if a suitable rule is missing.
It permits members to reach their own devices, with browser reauthentication.
It does not grant network access by itself. Tagged devices need an explicit rule
for their tag instead of `autogroup:self`. Keep existing policy entries intact.

## Keep the Mac available with its lid closed

nix-darwin sets `pmset -c sleep 0` on every switch. This prevents idle system sleep
on AC power, while retaining the battery and display timers. It does not prevent
lid-close sleep.

For headless use without an external display, connect power and run:

```sh
just clamshell-on
```

This explicitly sets the system-wide `pmset -a disablesleep 1` flag. The recipe
checks for AC power before enabling it, but **unplugging does not turn it off**.
It persists until disabled, including across restarts. Keep the Mac ventilated
and turn this mode off before putting it in a bag or using it on battery:

```sh
just clamshell-off
```

This restores lid-close and manual sleep. AC idle sleep remains disabled by the
Nix setting. To restore AC idle sleep too, remove the `pmset -c sleep 0` activation
line in `nix/hosts/thrawnym1/darwin.nix` and run `sudo pmset -c sleep 1`, the
pre-migration value on this machine.

Apple's [power-management source](https://github.com/apple-oss-distributions/PowerManagement)
implements `disablesleep`, but it is not a documented `pmset` man-page option.
Treat a real closed-lid test as required after macOS upgrades. `caffeinate` alone
is not a substitute for verifying lid-close behavior.

Test SSH with the lid open first. Then close it while plugged in, wait at least
two minutes, and make a fresh SSH connection from the other device. Check
`pmset -g` over SSH if it works. This physical test cannot be replaced by a Nix build.

## Recovery and limits

- If closed-lid SSH fails, open the lid and inspect `tailscale status` and
  `pmset -g`. Use `just clamshell-off` to return to ordinary lid behavior.
- Restart a stuck daemon with
  `sudo launchctl kickstart -k system/com.tailscale.tailscaled`. This disconnects
  active Tailscale SSH sessions.
- With FileVault enabled, plan to unlock the disk locally after a cold boot.
  A launch daemon cannot run before macOS has booted from the unlocked disk.
- Neither Tailscale nor a sleep setting can provide access while the Mac is
  powered off, has lost its network connection, or is waiting for disk unlock.
