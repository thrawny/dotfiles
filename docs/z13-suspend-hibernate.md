# ThinkPad Z13 Gen 2: Suspend & Hibernate Issues

## Sleep Configuration

The Z13 uses **suspend-then-hibernate**: suspend to RAM on lid close, then hibernate to disk after 2 hours (`HibernateDelaySec=2h`). Hibernate uses a 64 GiB swapfile on the LUKS-encrypted root partition.

When docked (external monitors connected), logind sets `HandleLidSwitchDocked=ignore` to allow clamshell mode. This means closing the lid while docked does **not** suspend — the system stays awake. UPower is configured to hibernate at 5% battery as a safety net for the "close lid then unplug" scenario.

## Problem 1: mt7921e WiFi kills hibernate

**Bug**: The MediaTek mt7921e WiFi driver fails to suspend/restore reliably during hibernate. The PCIe device enters D3cold (fully powered off), and on resume the link fails to re-establish within the timeout window. This produces cascading errors:

```
mt7921e: Message timeout
mt7921e: Timeout for driver own (repeated)
mt7921e: hardware init failed
mt7921e: PM: failed to resume async: error -5 (EIO) or -110 (ETIMEDOUT)
```

This is a [known kernel bug](https://bugzilla.kernel.org/show_bug.cgi?id=217415) affecting MT7921/MT7922 chips from kernel 5.16 through at least 6.18. No upstream fix exists.

**Consequences**: WiFi is dead after resume (requires reboot). In the worst case, the failed hibernate aborts entirely, leaving no image to resume from — causing a fresh boot with potential display corruption. A failed driver can also block shutdown, requiring a hard power-off.

### Fix: rmmod/modprobe via systemd service

Unload the driver before sleep and reload it after resume. The driver does a clean probe on reload, avoiding the broken restore path entirely.

**Critical detail**: NixOS's `powerManagement.powerDownCommands` / `resumeCommands` use `pre-sleep.service` and `post-resume.service`, which are ordered around `sleep.target`. However, `sleep.target` is reached **before** the kernel actually suspends — both the rmmod and modprobe run before suspend, defeating the workaround entirely. The post-resume service's `After=sleep.target` does not mean "after waking up."

The fix hooks directly into the actual suspend/hibernate services:

```nix
systemd.services.mt7921e-sleep = {
  before = [
    "systemd-suspend.service"
    "systemd-hibernate.service"
    "systemd-suspend-then-hibernate.service"
  ];
  wantedBy = [ /* same list */ ];
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    ExecStart = "rmmod mt7921e";       # runs before sleep
    ExecStop = "modprobe mt7921e";     # runs after wake
  };
};
```

`RemainAfterExit=true` is key: ExecStart runs when entering sleep (rmmod), and ExecStop runs when the service stops after resume (modprobe).

## Problem 2: Docked lid close + unplug = no suspend

When external monitors are connected, logind considers the system "docked" and ignores lid close events (`HandleLidSwitchDocked=ignore`). If you close the lid while docked, then unplug everything, logind does **not** re-evaluate — it only reacts to the lid close event itself. The system stays awake with the lid closed until the battery dies.

### Fix: UPower critical battery hibernate

UPower monitors battery level as a system daemon regardless of lid/display state. Configured to hibernate at 5% battery:

```nix
services.upower = {
  enable = true;
  percentageLow = 20;
  percentageCritical = 10;
  percentageAction = 5;
  criticalPowerAction = "Hibernate";
};
```

This doesn't prevent the battery drain but saves the session before it hits 0%.

## References

- [Kernel Bugzilla #217415](https://bugzilla.kernel.org/show_bug.cgi?id=217415) — mt7921e suspend/hibernate failure
- [Bugzilla Comment #12](https://bugzilla.kernel.org/show_bug.cgi?id=217415#c12) — rmmod/modprobe workaround
- [NixOS Discourse: Mt7921e Wireless Issues](https://discourse.nixos.org/t/mt7921e-wireless-issues/49476)
