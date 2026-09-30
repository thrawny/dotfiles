# Keyboard rules

These are the intended rules for my keyboard-driven environments, including Hyprland, AeroSpace, Herdr, and Ghostty. They guide new bindings, rather than declaring every existing binding correct. Deliberate exceptions and known mismatches are separate below.

## Modifier ownership

`Cmd` means Command on macOS and Super on Linux, after device remapping. Prefer matching physical modifier positions across keyboards, but keep device-specific swaps in the device configuration.

| Modifier | Owner |
| --- | --- |
| Alt | Desktop and window manager |
| Alt+Cmd | Desktop and window manager, including mixed-modifier chords |
| Cmd | Custom application shortcuts, except the named reservations below |
| Ctrl and unmodified keys | Native application, terminal, and modal-editor conventions |

This is not a requirement to replace every application's native Ctrl shortcut. Selected Mac-style Cmd shortcuts on Linux can coexist with native Ctrl bindings. Ghostty must be excluded from generic Cmd-to-Ctrl translation so Herdr receives its Cmd keys.

## Terminal layers

- The WM owns terminal windows, including launching, focusing, moving, closing, and fullscreen.
- Herdr owns terminal workspaces, tabs, panes, and agent navigation. Its assigned Cmd shortcuts take precedence over programs running inside its panes.
- Ghostty renders the terminal and forwards input. Selection, clipboard operations, and font zoom are allowed; it should not provide a competing pane or tab interface or intercept Herdr's shortcuts.
- Programs inside Herdr retain ordinary input, native Ctrl shortcuts, and modal bindings, subject to the explicit exceptions below. In particular, unshifted Ctrl+H/J/K/L must reach them.

Unbind conflicting terminal defaults rather than moving a Herdr shortcut merely to accommodate Ghostty. On macOS, check native menu shortcuts too; Ghostty's keybinding configuration alone cannot release every key.

## Consistency

Use the same chord for equivalent operations in Hyprland and AeroSpace where supported. Match intent without requiring identical layouts or adding compatibility machinery solely for parity. Document meaningful differences; an unsupported action can remain unbound.

Prefer the same base key for related actions across layers. Enter creates, W closes, M switches focus, and U/I navigate previous/next where those actions exist. These are guidelines, not a requirement to redesign every existing shortcut.

Prefer consistent extra modifiers. Shift commonly moves rather than focuses, expands the scope, or selects a secondary action. Keep the exact meaning explicit rather than treating Shift as a universal rule.

For example, Alt+W closes a WM window, Cmd+W closes a Herdr pane, and Cmd+Shift+W closes a Herdr tab. Similar keys do not imply identical object types.

## Deliberate exceptions and reservations

These are intentional departures from the ownership defaults, not blanket permission to consume more app keys.

| Keys | Reservation or exception | Reason |
| --- | --- | --- |
| Cmd+Space | OS launcher | Keep a familiar global launcher shortcut. |
| Cmd+Tab | OS app switching | Reserve it rather than assigning it to Herdr navigation. |
| Cmd+Shift+3/4/5, Print variants | OS screenshots | Keep screenshot chords available across environments. Exact capture behavior can differ. |
| Media, volume, and brightness keys | OS hardware controls | These remain global. |
| Cmd+Q | Application quit, where supported | Preserve the conventional quit action rather than reusing it for pane or tab operations. |
| Ctrl+A in Herdr | Prefix | Keep prefix-based access alongside direct Cmd shortcuts. This is an explicit exception to Ctrl passthrough. Ctrl+A twice, or Ctrl+A then A, sends a literal Ctrl+A to the pane. |
| Ctrl+Shift+H/L in Herdr | Previous/next tab | Keep the familiar tab shortcuts without taking unshifted Ctrl+H/L from pane programs. Cmd+H/L do the same and follow the ownership rule. |
| Right Alt+P and right Super+P on Linux | Global dictation | Right-side modifiers deliberately override normal ownership. Use left Cmd/Super+P for Herdr's project picker. |

Ghostty's macOS Minimize, Zoom Split and Hide Ghostty menu shortcuts are disabled to release Cmd+M, Cmd+Shift+Enter and Cmd+H to Herdr. That implements the ownership rule; it is not another exception.

## Known mismatches and audit gaps

These are follow-up work, not approved exceptions. Recording them does not authorize changing bindings as part of an unrelated task.

- Hyprland uses Super+L to toggle the workspace layout. A WM layout action belongs on an Alt-based chord. Until it moves, Herdr's Cmd+L next-tab binding only works on macOS.
- Linux xremap translates Alt+Super+I to Ctrl+Shift+I for developer tools outside Ghostty. This conflicts with WM ownership of Alt+Cmd.
- Ghostty removes selected default bindings rather than clearing them all. Audit the effective defaults on both platforms, including native menu shortcuts, before claiming it only handles transport, selection, clipboard, and zoom.

Known platform differences are not necessarily ownership violations. Hyprland's Alt+number selects by current workspace order, while AeroSpace uses fixed workspace names. Alt+F requests layout-aware maximization in Hyprland and AeroSpace fullscreen on macOS. AeroSpace deliberately leaves several actions unbound, including workspace cycling and scratchpads. Treat these as differences to account for, not evidence of exact cross-platform behavior.

## When changing bindings

Check the proposed key against its owner, the reservations, and every layer that can intercept it. Distinguish an intentional exception from an implementation mismatch. Record a new exception with its platform or app, chord, and reason; do not silently promote an existing conflict into policy.

The configuration remains the source for the complete binding inventory:

- [Hyprland bindings](../config/hypr/lua/binds.lua)
- [AeroSpace bindings](../config/aerospace/aerospace.toml)
- [Herdr bindings](../nix/home/shared/herdr.nix)
- [Ghostty shared settings](../nix/home/shared/ghostty.nix) and [macOS settings](../nix/home/darwin/ghostty.nix)
- [Linux device and app remapping](../nix/home/nixos/xremap.nix)
