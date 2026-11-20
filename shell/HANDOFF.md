# Quickshell implementation checkpoint

Read [AGENTS.md](AGENTS.md). This is the current Hyprland implementation.

## Implemented and deployed

- Quota indicators and details use `quotabar snapshot` schema 1. The Rust backend
  retains caching, expiry, notifications, costs and credit policy. The flake pins
  `5d6b3811303276081f1c510f4c9f3255bd64dffa` from `~/code/quotabar`.
  The QML presentation follows the original compact indicators and stacked
  provider popup, including SVG logos and the orange Claude mark.
- Workspace pills use the active gradient and state colors from the old Waybar theme.
- Image clipboard history shows asynchronous thumbnails and copies original
  bytes through the approved Python adapter `bin/shell-clipboard-image`.
  Nix pins its interpreter and commands. Separate systemd text/image watchers
  record history. Private preview files are bounded and cleaned on picker close;
  a later request removes abandoned sessions. See [README.md](README.md) for limits.
- Caffeine survives QML reloads. Preserve its live state during development.

`just check`, shell formatting and strict QML lint passed. The shell suite has
tests for quota layout and SVG loading, failed/late backend responses,
image cancellation and cleanup. The Nix-built image adapter also
passed PNG and animated GIF round-trips on a private headless Wayland compositor.
Quotabar has 52 passing Rust tests. Its Nix package and the whole system built successfully.
`just switch` succeeded; production service commands use Nix store paths.
Shell IPC reports ready. Both clipboard watchers run exactly once. The live
bar state was inspected. No live clipboard-content tests were performed.

## Claude authentication

`claude auth status` reports loggedIn=false with the expected config directory.
Jonas explicitly chose to keep Claude visibly unavailable for now. Do not ask
for login again as part of this task. Cached windows remain visibly stale;
Codex quotas are fresh. No implementation work remains deferred for authentication.
