# Quickshell implementation checkpoint

Read [AGENTS.md](AGENTS.md). This is the current Hyprland implementation;
`docs/quickshell-implementation-plan.md` is historical. Niri remains unchanged.

## Implemented and deployed

- Waybar functional parity is recorded in [PARITY.md](PARITY.md), including
  keyboard switching, network traffic/frequency, audio settings and mute,
  battery power details, clock actions, and compact tray behavior.
- Quota indicators and details use `quotabar snapshot` schema 1. The Rust backend
  retains caching, expiry, notifications, costs and credit policy. The flake pins
  `5d6b3811303276081f1c510f4c9f3255bd64dffa` from `~/code/quotabar`.
- The QML agents sidebar replaces the Hyprland GTK workflow. Its state and actions
  use `agent-switch serve --sidebar`, owned by `dotfiles-agent-switch.service`.
  The flake pins `6f7c9bb1c90cc0087f682a29bb19f03ebb7cc35c` from
  `~/code/agent-switch`. Alt+S toggles the QML sidebar. The old Process Compose
  development stack was stopped through `just watch-stop`; do not restart it
  alongside the production sidebar daemon. The sidebar opens on the left.
- Image clipboard history shows asynchronous thumbnails and copies original
  bytes through the approved Python adapter `bin/shell-clipboard-image`.
  Nix pins its interpreter and commands. Separate systemd text/image watchers
  record history. Private preview files are bounded and cleaned on picker close;
  a later request removes abandoned sessions. See [README.md](README.md) for limits.
- Caffeine remains ON and survives QML reloads. Preserve that state.

`just check`, shell formatting and strict QML lint passed. The shell suite has
48 tests, including rendered sidebar/rename regressions, failed/late backend
responses, image cancellation and cleanup. The Nix-built image adapter also
passed PNG and animated GIF round-trips on a private headless Wayland compositor.
Quotabar has 52 passing Rust tests; agent-switch has 81 Rust and 9
lifecycle tests. Both Nix packages and the whole system built successfully.
`just switch` succeeded; production service commands use Nix store paths.
Shell IPC reports ready. Both clipboard watchers run exactly once, and the
agent daemon is healthy. The live sidebar and bar state were inspected.
No destructive live thread operations or live clipboard-content tests were performed.

## Claude authentication

`claude auth status` reports loggedIn=false with the expected config directory.
Jonas explicitly chose to keep Claude visibly unavailable for now. Do not ask
for login again as part of this task. Cached windows remain visibly stale;
Codex quotas are fresh. No implementation work remains deferred for authentication.
