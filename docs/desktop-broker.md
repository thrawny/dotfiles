# Desktop broker

`bin/desktop-broker` lets sandboxed applications request a host desktop operation without access to raw niri or Hyprland IPC. Its only operation is `open-url`.

Fullscreen Pi handles link clicks itself. Its URL opener therefore runs inside the sandbox, where the niri socket is hidden. `bin/niri-open-url` now sends sandbox requests to the broker instead of launching a new Helium window. On the host, the existing router still chooses the nearest Helium window, then the named `web` workspace.

## Activate

Run `just switch` on the host, then check:

```sh
systemctl --user start desktop-broker.socket
systemctl --user status desktop-broker.socket
```

Restart existing sandboxes so they receive the new socket-directory mount. Then Ctrl-click a link in fullscreen Pi, or run this inside the sandbox:

```sh
bin/niri-open-url https://example.com
```

The socket belongs to the graphical session. Systemd starts a single broker process on the first connection. The process stays running, serializes URL opens, and waits for each router invocation to finish. This avoids overlapping focus/clipboard operations and keeps newly launched browser children alive after a request. The service stops with the graphical session.

The socket lives at `$XDG_RUNTIME_DIR/desktop-broker/broker.sock`. `bin/sandbox` read-only binds the containing directory, so replacing the socket does not strand existing sandboxes on an old socket inode. If the socket is unavailable or a request fails, the client reports an error. It does not retry or launch a second browser window, since a timed-out request may already have opened the URL.

Inspect service failures with:

```sh
journalctl --user -u desktop-broker.service
```

## Protocol and limits

One newline-terminated JSON request and response per Unix connection, at most 16 KiB each:

```json
{"version":1,"operation":"open-url","target":"https://example.com"}
```

Success:

```json
{"version":1,"ok":true,"result":null}
```

Failure:

```json
{"version":1,"ok":false,"error":"unsupported operation"}
```

Accepted targets:

- HTTP and HTTPS URLs.
- Existing `.html` and `.htm` files under `~/dotfiles`, `~/dotfiles-worktrees`, `~/code`, or `~/work/*/code`.
- Local `file:` URLs for those HTML files, without query strings or fragments. The client converts relative paths to absolute paths before sending them. Files must exist at the same path on the host; sandbox-private `/tmp` files are not supported.

The broker resolves symlinks before checking HTML roots. It rejects unknown versions, operations, extra fields, control characters and other URL schemes. Requests cannot specify executables, environment variables, compositor commands or window IDs. It checks Linux peer credentials against its UID, bounds request reads to two seconds, and bounds router execution to 40 seconds. URLs and opener output are not written to its logs.

The host service uses Nix-store copies of both scripts and a fixed tool PATH. It must not execute the sandbox-writable checkout in response to a request. Source changes to host behavior need `just switch`; client/router changes in the checkout are immediate.

This grants permission to open browser content and change focus. It is not full desktop isolation: the sandbox's existing raw Wayland mount remains unchanged for image paste. Clipboard APIs, raw IPC forwarding, current-workspace queries, and new Hyprland routing are not implemented. Future operations should get an explicit schema and handler in `dispatch`, using the same versioned envelope rather than a generic command facility.

## Tests and prior discussion

Run `just test-desktop-broker`. Tests use isolated sockets and a fake opener, never the live desktop.

The earlier discussion is Pi session `01a05d1e-b654-7bb1-a427-5be12bad6d6a`, September 1, 2026. Find it with `agent-history query 01a05d1e-b654-7bb1-a427-5be12bad6d6a open-url`. Its throwaway implementation is on branch `prototype/clipboard-broker`, commit `7527eb4`. This implementation keeps the narrow host-operation design but does not import its clipboard features.
