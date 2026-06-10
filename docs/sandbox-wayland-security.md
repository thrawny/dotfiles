# Sandbox Wayland exposure — security finding & next steps

Analysis of `~/dotfiles/bin/sandbox` (bwrap wrapper). Written 2026-06-10.

## Finding

The sandbox hides all host runtime sockets with `--tmpfs /run/user/$UID`, then
re-binds a few back in. One of them is the host compositor socket:

```bash
# Expose Wayland socket so wl-paste (used by pi/claude for image paste) works
if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
  args+=(--ro-bind-try
    "/run/user/${UID}/${WAYLAND_DISPLAY}"
    "/run/user/${UID}/${WAYLAND_DISPLAY}")
fi
```

This binds the **host niri socket** (`wayland-1`) into the sandbox. Verified at
runtime: this session is `SANDBOX=1` yet successfully bound the host
compositor, spawned a nested niri on it, and could read host protocol globals.

**`--ro-bind` provides zero protocol-level protection here.** Read-only applies
to the socket *inode* (can't unlink/replace the file); it does not restrict
`connect()` or the bidirectional byte stream. The proof is that the sandbox
author uses `--ro-bind` and `wl-paste` still works — the connection is fully
live. A read-only bind of a socket is, for protocol purposes, a full bind.

## Why this is a sandbox escape

The Wayland protocol isolates clients *from each other* but assumes every
client is as trusted as the user. niri advertises (confirmed via
`wayland-info`):

| Global | Capability granted to anything on the socket |
|---|---|
| `zwlr_virtual_pointer_manager_v1` | Move/click the **real** pointer |
| `zwp_virtual_keyboard_manager_v1` | Type into **any host window** |
| `zwlr_screencopy_manager_v1` | Screenshot **any host window** |
| `zwlr_data_control_manager_v1` / `ext_data_control_manager_v1` | Read/monitor the **clipboard** in the background |

niri's own [Security Model](https://github.com/YaLTeR/niri/wiki/Security-Model)
names exactly these as "unsafe protocols."

Severity: **critical / full escape.** Input injection alone is game over —
a sandboxed process can type into your unsandboxed terminal and run arbitrary
commands on the host (and `niri-cu`, built this session, is a ready-made tool
for it). Screencopy leaks anything on screen; data-control leaks anything you
copy (passwords, tokens).

The escape is *latent*: it depends on the sandboxed process choosing to use the
socket. The whole point of the sandbox is to contain code you don't fully
trust (AI agents, their dependencies, prompt-injected instructions), so "it
won't choose to" is not a boundary.

## Root cause

Only **one** of the three capability classes is actually wanted: clipboard
read, for `wl-paste` image paste. Input injection and screencopy are pure,
unwanted collateral from binding the raw socket to get clipboard access.

## Recommendations (ranked)

### 1. Default: stop binding the host socket (closes the escape completely)

Delete the `--ro-bind-try $WAYLAND_DISPLAY` block. Zero new moving parts, fully
closes input-injection + screencopy + clipboard leakage.

**Cost:** `wl-paste` image paste stops working. This is defensible — clipboard
*read* is itself an exfiltration channel, and image paste has a fallback (save
the image to a file under a writable bind like `~/code` or `/tmp` and reference
the path).

```diff
-    # Expose Wayland socket so wl-paste (used by pi/claude for image paste) works
-    if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
-      args+=(
-        --ro-bind-try
-        "/run/user/${UID}/${WAYLAND_DISPLAY}"
-        "/run/user/${UID}/${WAYLAND_DISPLAY}"
-      )
-    fi
```

### 2. If clipboard image-paste must keep working: filtering proxy

The feature fundamentally needs `wlr-data-control` (that is what lets a
windowless CLI read the clipboard). You cannot make clipboard-read "safe" — but
you can drop the *worst* capabilities (input injection, screencopy) while
keeping it.

- niri's built-in **security-context** is all-or-nothing on the unsafe set — it
  blocks data-control too, so it does **not** preserve `wl-paste`. (See option 3
  for where it *is* the right tool.)
- Instead run a **filtering Wayland proxy** (e.g. `wayland-proxy-virtwl`, or a
  small `wl-mitm`-style filter) on the host that exposes a new socket with
  `zwlr_virtual_pointer_manager_v1`, `zwp_virtual_keyboard_manager_v1`,
  `zwlr_screencopy_manager_v1`, and `wlr-layer-shell` **stripped**, but
  `wl_data_device` / data-control allowed. Bind the **proxy's** socket into the
  sandbox instead of the host socket, and set `WAYLAND_DISPLAY` to it.

**Cost:** a long-running proxy process per session; more complexity. Residual
risk: clipboard read remains.

### 3. For sandboxed GUI / computer-use work: nested compositor

Never expose the host socket for this. Run a **nested compositor inside the
sandbox** and point the agent at *its* `WAYLAND_DISPLAY` — the pattern proven
in the niri-cu session (`just nested` in `~/code/niri-cu`). The agent gets a
full, controllable desktop that physically cannot reach the host. This is the
correct containment story before letting an agent drive a GUI autonomously.
(If a sandboxed app needs to *display* on the host but not inject/capture,
niri's security-context socket is the right tool — it's compositor-enforced and
needs no proxy.)

## Adjacent exposures (same runtime-socket block)

The Wayland question surfaced two neighbors worth a look — niri's own security
note says sandboxing "must also remove IPC socket access and restrict D-Bus":

- **D-Bus session bus** (`--ro-bind-try /run/user/$UID/bus`, for `notify-send`).
  The session bus can reach host services and, depending on what's on the bus,
  launch host apps / open files — a known escape surface. Consider a filtering
  proxy (`xdg-dbus-proxy`, the Flatpak model) that allows only the notification
  interface, or drop it and use a different notify path.
- **PipeWire** (`--ro-bind-try /run/user/$UID/pipewire-0`). Grants audio and,
  via portals, potentially screen capture. Lower priority than Wayland but it's
  another capture channel.

Both are lower severity than the Wayland input-injection escape; fix Wayland
first.

## Note on the overall model

The sandbox is `--ro-bind / /` (entire host filesystem readable) plus an
explicit deny-list (`~/.ssh`, `~/.aws`, `~/.gnupg`, gh, kube, docker sock,
incus) and `.secrets*` redaction. That is a denylist, not an allowlist —
protection depends on the deny-list staying complete. Worth a periodic audit
that no new secret-bearing path (new tool configs, tokens in dotfiles) sits
outside the deny-list. Out of scope for the Wayland fix, but the same
"exposed by default" pattern that produced the Wayland hole.

## Decisions needed

1. Is `wl-paste` image paste worth keeping? **No → option 1** (delete the
   block, done). **Yes → option 2** (filtering proxy).
2. Will the sandbox ever drive GUI apps? If yes, adopt **option 3** (nested
   compositor) for that work regardless of 1.
3. Triage D-Bus and PipeWire exposure separately once Wayland is closed.

## Next steps

- [ ] Decide #1 above.
- [ ] If option 1: apply the diff, confirm image paste fallback is acceptable.
- [ ] If option 2: pick a proxy, wrap it so it starts per-session, bind its
      socket, set `WAYLAND_DISPLAY`; verify `niri-cu screenshot`/`type` against
      the host socket **fail** from inside the sandbox afterward.
- [ ] Regression check either way: from inside the sandbox,
      `niri-cu type --text x` and `niri-cu screenshot` against the host must
      error (no manager global) — that is the test that the escape is closed.
- [ ] (Adjacent) Decide on `xdg-dbus-proxy` for the session bus and whether
      PipeWire stays.
```
