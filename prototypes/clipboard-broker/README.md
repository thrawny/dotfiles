# Desktop broker prototype

Throwaway prototype answering two questions:

1. Can Pi and Claude Code paste a host clipboard image when the sandbox has no usable Wayland or X11 connection and `wl-paste` on `PATH` is a broker client?
2. Can a sandbox request the existing host-side `niri-open-url` behavior without receiving Niri IPC access?

The broker runs outside the sandbox. The replacement `bin/wl-paste` only supports listing image MIME types and reading an allowlisted image. The replacement `bin/niri-open-url` accepts HTTP, HTTPS, and local HTML under configured roots. By default those roots are `~/dotfiles`, `~/code`, and `~/work/*/code`; `--html-root` overrides them. It cannot read clipboard text, write the clipboard, execute an arbitrary command, or issue a caller-selected Niri action.

Run the broker from the repository root:

```bash
just prototype-clipboard-broker
```

In another shell, point the wrapper at it:

```bash
export CLIPBOARD_BROKER_SOCKET="${XDG_RUNTIME_DIR}/clipboard-broker-prototype.sock"
PATH="$PWD/prototypes/clipboard-broker/bin:$PATH" \
  wl-paste --list-types

PATH="$PWD/prototypes/clipboard-broker/bin:$PATH" \
  niri-open-url https://example.com
```

## Verdict

Validated against the installed Pi 0.84.4 and Claude Code 2.1.251 binaries on 2026-09-01.

Both clients pasted a brokered 1 x 1 PNG while running with:

- an empty `XDG_RUNTIME_DIR`;
- `WAYLAND_DISPLAY` pointing to a nonexistent socket;
- `DISPLAY` unset;
- this prototype's `wl-paste` first on `PATH`.

The broker log recorded `list-types` followed by `read image/png` for each client. Pi created its usual `/tmp/pi-clipboard-*.png` attachment, and Claude rendered `[Image]`. A direct request for `--type text` failed as intended.

This proves that an image-only broker can replace raw host Wayland access for image paste in both tools. The broker also accepted HTTP, HTTPS, and allowlisted local HTML targets while rejecting `javascript:`, local files outside its roots, and non-HTML files. It delegated accepted targets to the fixed host-side `niri-open-url` command.

It does not yet solve the separate requirement for a restricted Wayland socket when nested Niri needs to display a window.

## Limits

This is not production code. It has enough framing, MIME filtering, size limiting, and logging to test the real client behavior, but no lifecycle integration with `bin/sandbox`. The final broker should bind a per-sandbox socket, verify the connecting process, avoid exposing `xclip`, and clean up reliably when the sandbox exits.
