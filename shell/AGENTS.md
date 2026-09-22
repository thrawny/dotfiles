# Shell development

User-facing setup and controls live in [README.md](README.md). Follow the
[repository conventions](../AGENTS.md) for task invocation, helper placement,
and theme changes.

## Implementation rules

- Prefer native Quickshell APIs and QML/JS services. Direct `Process` calls to
  existing programs such as cliphist are allowed. Do not add Bash runtime
  wrappers or inline shell backends, including through Nix.
- If a feature needs a custom backend, stop and say "this requires a backend".
  Agree on it with Jonas before implementing; defer the feature meanwhile.
- Keep process handling and shared state in `services/`; widgets render state
  and invoke service methods. Keep compositor-specific logic out of shared controls.
- Preserve the quiet visual design: no shadows or unsolicited animations.

## Checks

Run from the repository root:

```sh
just shell::fmt
just shell::check
```

The check runs model tests, offscreen QML/cliphist integration tests, and strict
QML linting. For Nix wiring changes, also follow [the Nix guide](../nix/AGENTS.md).
For theme changes, use the root guide's theme check.

Test clipboard changes with isolated databases and offscreen Qt. Do not inspect
or overwrite the user's live clipboard for testing. Keep clipboard content out
of logs and command arguments; pass entry IDs through stdin. Preserve decoded
whitespace and reject asynchronous results from a closed or replaced picker.

## Runtime and gotchas

- [The Home Manager module](../nix/home/nixos/hyprland.nix) links this directory
  as the mutable `dotfiles` config. QML edits hot-reload; Nix changes need a switch.
- Use `quickshell ipc -c dotfiles`, not `-p shell`, for the managed instance.
  Quickshell treats those entrypoint paths as different instance identities.
- `just shell::dev` leaves an existing instance alone. To run in the foreground,
  first stop `dotfiles-shell.service` with `systemctl --user stop`.
- Systemd owns the shell and the separate text clipboard watcher. Reloading the
  UI must not start another watcher. Niri's startup remains independent.
- Inspect logs with `journalctl --user -u dotfiles-shell.service` or
  `quickshell log -c dotfiles`. Check readiness with
  `quickshell ipc -c dotfiles call shell ping`.
- Quickshell 0.3.1 ignores `DesktopEntry.runInTerminal` when executing entries;
  keep the explicit terminal handling. A failed `Process` start does not emit
  `exited`; handle it separately from a nonzero command exit.
- Popup text must escape the bar's window bounds. Use `PopupWindow` for tooltips,
  rather than rendering them inside the panel.
