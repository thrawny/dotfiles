# ThinkPad Z13 Gen 2: Suspend & Hibernate Issues

## Sleep Configuration

The Z13 uses **suspend-then-hibernate**: suspend to RAM on lid close, then hibernate to disk after 2 hours (`HibernateDelaySec=2h`). Hibernate uses a 64 GiB swapfile on the LUKS-encrypted root partition.

When docked (external monitors connected), logind sets `HandleLidSwitchDocked=ignore` to allow clamshell mode. This means closing the lid while docked does **not** suspend — the system stays awake. UPower is configured to hibernate at 5% battery as a safety net for the "close lid then unplug" scenario.

## Current Status

As of March 25, 2026:

- The `mt7921e` Wi-Fi workaround is active and appears to have fixed the original "Wi-Fi driver wedges during sleep/hibernate" problem.
- Hibernate is **still intermittent**. The remaining failures do **not** always show `mt7921e` errors, so Wi-Fi is no longer the only suspect.
- The current failure shape is usually:
  - hibernate begins and logs `PM: hibernation: hibernation entry`
  - the next boot logs `systemd-hibernate-resume: Unable to resume ...`
  - the kernel logs `PM: Image not found (code -22)`
  - the system falls back to a fresh boot instead of restoring the saved session

## Problem 1: mt7921e WiFi breaks suspend/hibernate recovery

The original bug was the MediaTek `mt7921e` Wi-Fi driver failing to suspend/restore cleanly. The PCIe device appears to enter a low-power state and then fail to come back within the driver's timeout window. Typical errors looked like:

```
mt7921e: Message timeout
mt7921e: Timeout for driver own (repeated)
mt7921e: hardware init failed
mt7921e: PM: failed to resume async: error -5 (EIO) or -110 (ETIMEDOUT)
```

On this machine, that bug could leave Wi-Fi dead after resume, and in the worst case could poison the wider wake path badly enough that hibernate never completed cleanly.

### Current Mitigation

The current workaround unloads the driver before sleep and reloads it after wake, and also disables PCIe ASPM for the device:

```nix
boot.extraModprobeConfig = ''
  options mt7921e disable_aspm=Y
'';

systemd.services.mt7921e-sleep = {
  wantedBy = [ "sleep.target" ];
  before = [ "sleep.target" ];
  unitConfig.StopWhenUnneeded = true;
  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    ExecStart = "-${pkgs.kmod}/bin/modprobe -r mt7921e";
    ExecStop = "${pkgs.kmod}/bin/modprobe mt7921e";
  };
};
```

Important details:

- This uses the documented `sleep.target` `ExecStart` / `ExecStop` pattern.
- `RemainAfterExit=true` keeps the service active across sleep so `ExecStop` runs after wake.
- `StopWhenUnneeded=true` makes systemd stop the unit when sleep finishes, which triggers the reload.
- `modprobe -r` is better than `rmmod` here because it handles dependencies more safely.
- `disable_aspm=Y` is a targeted power-management workaround for this card.

### What This Fixed

After the change:

- `mt7921e-sleep.service` is visible in the journal before sleep and after wake.
- The driver reloads cleanly on wake.
- `/sys/module/mt7921e/parameters/disable_aspm` becomes `Y` after the reload.
- Successful hibernate resumes no longer show the old `mt7921e` timeout / failed-resume signatures.

### What This Did Not Fix

The remaining intermittent hibernate failures do **not** consistently show Wi-Fi driver errors. When the bad failure happens now, the journal usually ends at:

```text
PM: hibernation: hibernation entry
```

and the next boot reports:

```text
systemd-hibernate-resume: Unable to resume ...
PM: Image not found (code -22)
```

That means the Wi-Fi workaround helped, but it did not fully solve hibernate on its own.

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

## Remaining Hibernate Problem

The remaining issue looks like a **late hibernate / restore failure**, and it appears to be intermittent.

### What The Recent Logs Show

- The newer `26.05.20260318...` generation first became the default boot generation on **March 23, 2026 at 08:23:51**.
- There was at least one successful hibernate/resume after that:
  - hibernate started on **March 23, 2026 at 20:25:30**
  - the resumed system logged `PM: hibernation: hibernation exit` on **March 24, 2026 at 08:15:41**
- A later cycle failed:
  - hibernate started on **March 24, 2026 at 19:11:35**
  - the next boot on **March 25, 2026 at 10:01:06** logged `PM: Image not found (code -22)`

So a newer kernel/initrd being present is **not enough by itself** to explain every failure. It still looks like a risk factor, but not a complete explanation.

### Monitor Hotplug Learning

One recent bad wake happened around dock / external monitor hotplug. The surviving logs show the important ordering:

- `systemd-hibernate-resume` had already failed with `Image not found`
- only **after that** did the dock / USB-C / DisplayPort / MST events appear

That means monitor hotplug may have made the visible aftermath uglier, but it did **not** appear to be the primary cause of the failed hibernate restore in that specific case.

### Experiments Tried And Reverted

Two additional experiments were tested and then removed:

- `HibernateMode=shutdown`
- a pre-hibernate `bootctl set-oneshot @current` hook

Neither clearly improved reliability on this machine, and the boot-entry pinning added extra ambiguity during recovery.

## Operational Guidance

- The Wi-Fi workaround is worth keeping. It addresses a real and separately observable bug.
- Hibernate should still be treated as intermittent on this machine.
- Avoid hibernating immediately after boot-critical changes when practical, especially kernel or initrd changes.
- While debugging, avoid hotplugging docks or monitors during wake.
- After a failed resume, the fastest useful checks are:

```bash
journalctl -b -1 | rg 'hibernate|resume|PM:|Image not found|mt7921|amdgpu'
journalctl -b | rg 'hibernate|resume|PM:|Image not found|mt7921|amdgpu'
```

## References

- [Kernel Bugzilla #217415](https://bugzilla.kernel.org/show_bug.cgi?id=217415) — mt7921e suspend/hibernate failure
- [Bugzilla Comment #12](https://bugzilla.kernel.org/show_bug.cgi?id=217415#c12) — rmmod/modprobe workaround
- [NixOS Discourse: Mt7921e Wireless Issues](https://discourse.nixos.org/t/mt7921e-wireless-issues/49476)
