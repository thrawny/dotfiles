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
  alongside the production sidebar daemon.
- Caffeine remains ON and survives QML reloads. Preserve that state.

`just check`, shell formatting and strict QML lint passed. The shell suite has
40 tests, including rendered sidebar/rename regressions and failed/late backend
responses. Quotabar has 52 passing Rust tests; agent-switch has 81 Rust and 9
lifecycle tests. Both Nix packages and the whole system built successfully.
`just switch` succeeded; production service commands use Nix store paths.
The live sidebar and bar state were inspected. No destructive live thread
operations or clipboard-content tests were performed.

## Remaining: image clipboard adapter approval

Jonas requested thumbnails and copying original image bytes. A structured
approval question is pending for this design; an unanswered question is not
approval. Do not implement custom backend code before his answer.

Quickshell 0.3.1 exposes text process/clipboard APIs; cliphist decode only writes
binary stdout. The proposed adapter is a Python-stdlib executable owned by
`shell/`, packaged with cliphist and wl-copy. It accepts numeric IDs through
stdin, decodes images into private per-picker directories under XDG_RUNTIME_DIR,
returns only file paths/metadata, and passes original files directly to wl-copy.
QML loads thumbnails asynchronously. Cleanup must handle picker close, stale
results and abandoned sessions. No daemon, shell wrapper, image conversion
library or credentials are needed. A Rust adapter was offered as the alternative.

Safe preparatory work is present: synthetic PNG/GIF fixtures, optional image row
parsing, and dormant asynchronous thumbnail rendering. The Clipboard service
still uses text-only parsing. After approval, implement the adapter, generation
checks, bounded preview work, cleanup, isolated binary round-trip tests, and the
separate systemd image watcher `wl-paste --type image --watch cliphist store`.
Keep the existing text watcher and never use the live clipboard for fixtures.
Then run checks, switch, and verify the deployed shell.

## Claude authentication

`claude auth status` reports loggedIn=false with the expected config directory.
Fresh Claude quota needs Jonas to run `claude auth login`; a separate structured
question is pending. Do not inspect credential contents. Codex quotas are fresh;
Claude cached windows remain visibly stale. After login the backend retries
normally, or `quotabar fetch` can refresh immediately.
