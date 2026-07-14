# ThinkPad Z13 Gen 2 notes

## ACP63 internal microphone failure after resume

The internal digital microphone has historically been prone to stopping after
suspend/resume and not recovering until reboot. When reproduced on 2026-07-14:

- The `acp63` ALSA card and PipeWire source remained visible.
- PipeWire capture returned only zero samples.
- Direct ALSA capture with `S32_LE`, 48 kHz, stereo failed with
  `pcm_read: Input/output error`.
- The device was correctly bound to `snd_pci_ps` (`1022:15e2`, revision `63`,
  Lenovo subsystem `17aa:2318`).
- The WirePlumber rule in `default.nix` only disables the unused analog `Mic2`
  source; it does not disable the internal ACP63 digital microphone (`Mic1`).

A likely upstream fix is:

- Commit: `5893013efabb056399a01e267f410cf76eba25eb`
- Subject: `ASoC: amd: ps: disable MSI on resume in ACP PCI driver`
- Patch: <https://git.kernel.org/pub/scm/linux/kernel/git/broonie/sound.git/patch/?id=5893013efabb056399a01e267f410cf76eba25eb>
- Message-ID: `20260707060130.2514138-2-Vijendar.Mukunda@amd.com`

The fix handles firmware unexpectedly enabling PCI MSI during resume even
though `snd_pci_ps` uses legacy INTx. Stale MSI configuration can cause lost
ACP interrupts, leaving capture present but nonfunctional. The patch clears MSI
before reinitializing ACP hardware.

The patch was accepted into the ASoC maintainer tree for Linux 7.2 and applies
cleanly to Linux 6.18.38. It is intentionally not applied in this configuration
because `boot.kernelPatches` would require a local kernel build. Revisit this
when the commit is included in a binary-cached kernel, backported to 6.18, or if
locally compiling the kernel becomes acceptable.
