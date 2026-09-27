# Remote mode

The same command works on `thrawny-desktop`, `thrawny-z13`, and `thrawnym1`, from any directory:

```sh
remote-mode on
remote-mode status
remote-mode off
```

Turning the mode on or off requires sudo. It starts off on Linux and remembers
your choice across logouts, reboots, and Nix switches. On macOS it reflects the
existing `pmset` sleep-disable setting, including changes made by the old
`just clamshell-on` command.

Remote mode blocks system sleep, including manual suspend and hibernation.
It leaves screen locking and monitor power-off alone. It does not stop shutdown
or reboot, configure networking, or enable SSH. Use the existing Tailscale SSH
connection while the machine is awake.

## Laptops

Connect AC power before running `remote-mode on`. Unplugging does not disable
remote mode. Run `remote-mode off` before using battery power or putting the
laptop in a bag. Do not depend on low-battery hibernation while sleep is blocked.
A remembered setting also applies if the laptop boots on battery.

The Z13's existing lid handler still turns the internal panel off. Remote mode
blocks its undocked-lid safety timer from suspending the system. Turning the mode
off restores that timer's normal behavior; it does not immediately force sleep.

For M1 closed-lid behavior, AC idle-sleep defaults, and FileVault limitations,
see [Mac remote access](mac-remote-access.md). In particular, `remote-mode off`
does not undo the Mac's separately configured AC idle-sleep policy.

## Linux installation and diagnosis

Apply the host's system configuration with `just switch`. The command is also
in the repo's `bin/` directory, but needs the installed system service to work.
It is only wired into the desktop and Z13 configurations.

```sh
systemctl status remote-mode.service
systemd-inhibit --list
journalctl -u remote-mode.service
```

The service holds a sleep-only inhibitor. Its root-owned marker at
`/var/lib/remote-mode/enabled` controls whether it starts at boot. It does not
hold an idle inhibitor, so hypridle can still lock the session and blank screens.
Privileged commands can bypass sleep inhibitors; this mode is not a security
boundary.

The desktop's power-button LED is unchanged. No control for that LED was exposed
in `/sys/class/leds` on its ASUS TUF GAMING B450-PLUS II motherboard.
