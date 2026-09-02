# Clipboard broker prototype

Throwaway prototype answering one question: can Pi and Claude Code paste a host clipboard image when the sandbox has no usable Wayland or X11 connection and `wl-paste` on `PATH` is a broker client?

The broker runs outside the sandbox and owns the real Wayland clipboard connection. The replacement `bin/wl-paste` only supports listing image MIME types and reading an allowlisted image. It cannot read text, write the clipboard, or access any other Wayland protocol.

Run the broker from the repository root:

```bash
just prototype-clipboard-broker
```

In another shell, point the wrapper at it:

```bash
export CLIPBOARD_BROKER_SOCKET="${XDG_RUNTIME_DIR}/clipboard-broker-prototype.sock"
PATH="$PWD/prototypes/clipboard-broker/bin:$PATH" \
  wl-paste --list-types
```

## Verdict

Validated against the installed Pi 0.84.4 and Claude Code 2.1.251 binaries on 2026-09-01.

Both clients pasted a brokered 1 x 1 PNG while running with:

- an empty `XDG_RUNTIME_DIR`;
- `WAYLAND_DISPLAY` pointing to a nonexistent socket;
- `DISPLAY` unset;
- this prototype's `wl-paste` first on `PATH`.

The broker log recorded `list-types` followed by `read image/png` for each client. Pi created its usual `/tmp/pi-clipboard-*.png` attachment, and Claude rendered `[Image]`. A direct request for `--type text` failed as intended.

This proves that an image-only broker can replace raw host Wayland access for image paste in both tools. It does not yet solve the separate requirement for a restricted Wayland socket when nested Niri needs to display a window.

## Limits

This is not production code. It has enough framing, MIME filtering, size limiting, and logging to test the real client behavior, but no lifecycle integration with `bin/sandbox`. The final broker should bind a per-sandbox socket, verify the connecting process, avoid exposing `xclip`, and clean up reliably when the sandbox exits.
