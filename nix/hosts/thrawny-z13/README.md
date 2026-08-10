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

The patch was accepted into the ASoC maintainer tree for Linux 7.2 and later
backported to the Linux 6.18 stable series as commit
`f33ad19e3e3d63c0d43b8be96754aae156c8c5af`. Linux 6.18.42 is the first 6.18
release containing it, so no local `boot.kernelPatches` build is needed.

The host booted Linux 6.18.42 on 2026-08-09. The microphone remained functional
after two suspend/resume cycles, including an overnight suspend from 20:18 to
08:58. A Wayvoice recording after the overnight resume contained real audio,
and a subsequent PipeWire capture from the digital microphone produced nonzero
samples while the ACP interrupt count advanced. The journal did not contain the
patch's `ACP: MSI unexpectedly enabled after resume` warning, so that particular
resume may not have triggered the formerly bad firmware state. Treat the issue
as provisionally fixed and revisit only if it recurs on Linux 6.18.42 or newer.
