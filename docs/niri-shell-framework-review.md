# Niri desktop shell framework review

Research snapshot: 2026-08-16. This revisits the earlier recommendation to keep
Waybar and the existing GTK utilities. That was the right low-change conclusion
for an Omarchy feature review; it is not the best answer to the newer goal of a
cohesive, personally authored shell, especially when Waybar itself has become a
source of friction.

## Decision

**Use Quickshell for a staged custom-shell experiment.** It is the best fit here,
not an unqualified winner for everyone. The intended architecture should be:

> Rust owns state, policy, Niri actions, persistence, and external APIs. QML owns
> presentation, animation, composition, and transient interaction.

Do not rewrite `quotabar` or `agent-switch` in QML. Give them stable JSON and IPC
interfaces, build a Quickshell bar and panels over those interfaces, and keep the
current GTK and Waybar frontends until the replacement has survived normal
laptop, dock, multi-monitor, suspend, and Niri-restart use.

Quickshell wins for this particular plan because it is deliberately a toolkit for
bars, widgets, locks, launchers, and other shell surfaces; Qt Quick is built around
declarative components, models, state, transitions, animation, and custom visual
composition; and there is now a healthy Niri-specific example ecosystem. It is
also the architecture Omarchy and DankMaterialShell use: a cohesive QML interface
over lower-level services and command-line backends.

The important qualifications are:

- Quickshell is young: the latest tagged release in this snapshot is
  [`v0.3.0`](https://github.com/quickshell-mirror/quickshell/releases/tag/v0.3.0).
  Expect API and packaging churn.
- Quickshell's own documentation describes it as relatively low-level and says a
  configuration is “practically programming,” not merely styling a bar
  ([official overview](https://quickshell.org/about/)). It is not the easy option.
- Quickshell has no built-in Niri workspace integration. Its first-party list
  names Hyprland, i3, and Sway; Niri support comes from shell code or a third-party
  plugin.
- A toolkit does not make a UI tasteful. Quickshell makes bespoke motion, layout,
  and drawing more natural than GTK CSS, but visual quality still comes from a
  coherent component and theme system.

If the actual goal shrinks to “replace the buggy bar with the least work,” choose
**ashell**, not Quickshell. If the goal becomes “install a finished integrated
Niri desktop,” try **DankMaterialShell** or **Wayle** before building one.

## What “best” and “modern” mean here

All of Quickshell, GTK4/Astal, Ignis, Ironbar, ashell, and Wayle use current
Wayland-capable stacks. Quickshell is not uniquely modern because it uses QML.
The decision turns on a more useful set of criteria:

1. Can one visual system cover a bar, popovers, sidebar, command palette, OSD,
   notifications, and future utilities?
2. Can Niri and the existing Rust tools remain authoritative rather than moving
   domain logic into UI scripts?
3. Is visual iteration fast enough to make a personal shell enjoyable to build?
4. Can the system stay declarative and pinned through Nix?
5. Is there enough active work and real Niri code to learn from?
6. Can the migration be reversed without losing the current desktop?

GitHub popularity is only supporting context. At this snapshot Eww has about
12.6k stars, DankMaterialShell 7.6k, AGS 3.1k, Quickshell 2.8k, Ironbar 1.4k,
ashell 1.1k, Astal 1.0k, Wayle 0.9k, and Ignis 0.7k. Quickshell is therefore not
the largest project by raw stars. Its stronger signal is the combination of
active upstream development, several substantial shell configurations, and two
prominent Niri-first shells. Repository counts were read from the projects linked
below on 2026-08-16 and should not be treated as a quality score.

## Comparison

| Option | Product shape | Niri story | Authoring experience | Integrated-shell ceiling | Fit here |
| --- | --- | --- | --- | --- | --- |
| **Quickshell** | Low-level shell toolkit | Community implementations; no first-party Niri module | QML/JavaScript, hot reload, LSP; powerful but a real programming project | Excellent | **Best foundation for a bespoke shell** |
| **Ignis** | GTK4 shell framework | Built-in Niri service with windows, layouts, workspaces, and keyboard state | Python, GTK4, Sass; approachable and direct | Excellent | **Best framework runner-up** |
| **AGS + Astal** | TypeScript/JS scaffolding over GTK4 and service libraries | Build an adapter or use community shell code | GJS, TypeScript, JSX, GTK4; familiar web-like language, GTK semantics | Excellent | Strong if TypeScript/GTK familiarity matters more than QML |
| **Eww** | Widget/window host | External Niri helper or scripts | Yuck DSL, SCSS, command output | Good for widgets; awkward as the service spine of a desktop | Great for a few widgets, not this consolidation goal |
| **Ironbar** | Configurable Rust/GTK4 bar with popovers | Officially partial Niri support | Config, hot-loaded CSS, scripts/Lua; extend core in Rust | Intentionally stops short of a full shell | Good conservative Waybar replacement |
| **ashell** | Ready-to-run Rust bar and settings panel | Niri is supported | TOML configuration, custom command modules, IPC | Bar, OSD, notifications, settings; not a general UI framework | **Best low-effort bar replacement** |
| **Custom Rust + GTK4** | Applications written from scratch | Whatever is implemented | Maximum type safety and control; slowest visual iteration and most boilerplate | Unlimited in theory, expensive in practice | Keep for backends and specialized fallback UIs |
| **DankMaterialShell** | Finished Quickshell + Go desktop shell | Explicitly optimized for Niri | Configure or contribute to an existing product | Complete | Best reference; adopt only if its product decisions fit |
| **Wayle** | Finished Rust + GTK4/Relm4 shell | Niri-specific modules are present | TOML, settings GUI, CLI; core changes in Rust | Complete | Best ready-made GTK/Rust trial, but still young |

### Quickshell

Quickshell is based on Qt Quick and configured in QML. It supplies layer-shell
surfaces plus system integrations and primitives for files, processes, sockets,
PipeWire, Bluetooth, PAM, greetd, UPower, power profiles, MPRIS, and system tray
items ([official scope](https://quickshell.org/about/)). Qt Quick itself provides
the component model, visual canvas, input, models/views, delayed creation, and
animation facilities that make it well suited to a cohesive visual shell
([Qt Quick reference](https://doc.qt.io/qt-6/qtquick-index.html)).

The upside over GTK4 is not that Qt is categorically newer or prettier. It is that
QML makes custom composition and animation the normal path, while GTK applications
usually compose a fixed widget catalogue and style the result with GTK's subset of
CSS. That distinction matters for animated workspace indicators, morphing status
chips, connected bar-to-panel transitions, and a shared visual language across
many shell surfaces. GTK4 remains a modern, capable toolkit and may be preferable
for conventional application UIs.

The largest risk is building a monolith whose JavaScript becomes the business
layer. Omarchy demonstrates both the appeal and the blast radius of one shell
process: its Quattro shell replaces the bar, launcher, notification daemon, OSD,
lock/idle UI, background, and polkit surface. The safer lesson is the visual
integration, not that every responsibility must move into QML.

### Ignis

[Ignis](https://github.com/ignis-sh/ignis/tree/97b7b5b17a16f574092b1584d7f5e24417455571)
is the most credible direct alternative. It is a Python-configured GTK4 framework
with widgets, reactive variables, utilities, and built-in services for audio,
backlight, Bluetooth, MPRIS, NetworkManager, notifications, system tray, UPower,
and other shell concerns. Unlike Quickshell and Astal, it has a first-party
[Niri service](https://github.com/ignis-sh/ignis/blob/97b7b5b17a16f574092b1584d7f5e24417455571/docs/api/services/niri.rst)
covering windows, window layout, workspaces, and keyboard layouts. The snapshot's
latest release is [`v0.6.0`](https://github.com/ignis-sh/ignis/releases/tag/v0.6.0).

Choose Ignis instead if built-in Niri support and staying in GTK4 outweigh QML's
visual model. It is likely the shortest path from the existing GTK utilities to a
custom integrated shell. Its disadvantages here are moving more orchestration
into dynamic Python, a smaller example ecosystem, and less direct reuse from the
Quickshell shells currently driving Niri shell design.

### AGS and Astal

[Astal](https://github.com/Aylur/astal/blob/1ea6cf6cdb67e8679f6e3e8434e76103559194da/docs/guide/introduction.md)
is a set of Vala/C libraries intended to underpin lightweight widgets or complete
desktop shells. Current [AGS](https://github.com/Aylur/ags/blob/bbee2f18939f1ec7ff720e717cf305e73635628f/docs/guide/quick-start.md)
is a CLI/scaffolding experience around Astal, Gnim, TypeScript/JSX, GJS, and GTK4;
it also supplies a Nix flake template. This is a modern and flexible stack, but the
project has undergone several architectural generations, and there is no Astal
Niri service in the reviewed tree. Niri integration is application code.

Choose it over Quickshell when TypeScript/JSX is substantially more comfortable
than QML and GTK4's widget model is desired. Do not choose it merely because JSX
looks familiar: GJS/GObject/GTK behavior still differs meaningfully from a browser
frontend stack.

### Eww

[Eww](https://github.com/elkowar/eww/tree/48f5aa8b379adf29da0b0bb9ca04164f65d8bdaa)
is a popular Rust widget system configured with a Lisp-like Yuck language and
SCSS. It is excellent when a UI can consume command output and remain mostly a
collection of independent widgets. Niri's curated list even includes a separate
`eww-niri-workspaces` bridge. Its Wayland frontend still uses GTK3 and
gtk-layer-shell in the official installation documentation, and its latest tagged
release remains [`v0.6.0` from 2024](https://github.com/elkowar/eww/releases/tag/v0.6.0),
although repository development continues.

It does not solve the core architectural goal as cleanly as Quickshell or Ignis.
The more the desktop needs keyboard focus, connected popovers, services, IPC,
stateful selection, and cross-surface transitions, the more external scripts and
state plumbing accumulate around Eww.

### Ironbar and ashell

[Ironbar](https://github.com/JakeStanger/ironbar/tree/9b4fadc3883e52cb753bde23c244934558b0f43d)
is the strongest configurable-bar middle ground. Version
[`0.19.0`](https://github.com/JakeStanger/ironbar/releases/tag/v0.19.0) uses Rust,
GTK4, and gtk4-layer-shell, supports hot-loaded GTK CSS, rich popovers, custom
widgets, scripts, and Lua. Its own documentation calls Niri support partial and
explicitly says it should not step on the toes of full custom-shell solutions. It
also still labels the project alpha and subject to breaking changes. This would
reduce the scope of a migration, but it does not provide the integrated canvas the
user is now interested in.

[ashell](https://github.com/MalpenZibo/ashell/tree/c9f2019c8ed275eab30f37459bbb4a916cb141f9)
is less of a framework and more of a finished replacement. It supports Niri,
multiple monitors, workspaces, tray, notifications, OSD, media, privacy status,
audio, brightness, Wi-Fi, VPN, Bluetooth, power profiles, custom command modules,
and an IPC CLI. Its current release is
[`0.9.0`](https://github.com/MalpenZibo/ashell/releases/tag/0.9.0). This is the
recommended fallback if the Quickshell experiment stops being fun: it removes a
large amount of Waybar configuration without committing to authoring a desktop
shell.

### Finished shells: DMS, Wayle, and Noctalia

[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell/tree/d4fecfcd5c020f1e819df174ed4b0fb1f6187b8c)
is the most relevant production reference. It is a complete Quickshell and Go
shell optimized for Niri and several other compositors. Its repository separates
QML modules, services, widgets, and shared resources from a Go backend and CLI—the
same boundary recommended for `quotabar` and `agent-switch`. It ships NixOS and
Home Manager modules. Treat it as an architecture and behavior catalogue, not a
base to fork wholesale.

[Wayle](https://github.com/wayle-rs/wayle/tree/a1723060b6a959b954832ce8ec92398b12f79b29)
is the most interesting non-QML ready-made shell in this snapshot: Rust,
GTK4/Relm4, TOML, a settings GUI, and built-in bar, notifications, OSD, wallpaper,
and device controls, with compositor modules for Niri. It is also very new
([`v0.7.0`](https://github.com/wayle-rs/wayle/releases/tag/v0.7.0)). Try it if the
preference changes from building the UI to configuring one while staying close to
the Rust/GTK ecosystem.

[Noctalia v5](https://noctalia.dev/blog/announcing-noctalia-v5) is a caution
against equating Quickshell with the final form of every shell. Noctalia's current
generation is a native C++ rewrite, not the earlier Quickshell version; its team
cites control, memory, packaging, and toolkit-upgrade stability as reasons for
leaving Qt. It is a finished configurable product rather than a framework for the
small custom utilities discussed here. Its experience is a reason to keep the
QML layer thin and the provider interfaces independent of Quickshell.

## Why the existing utilities make Quickshell a better bet

The current Waybar is already more than stock status modules. It has separate
laptop/external-output layouts and custom integrations for quota state,
agent-switch state, caffeine, Niri workspaces/window/language, tray, network,
audio, battery, and clock
([current configuration](https://github.com/thrawny/dotfiles/blob/6e00c1a853a1ec7eb09651cb8a72b9664e936913/nix/home/nixos/waybar.nix#L284-L451)).
The migration therefore needs to preserve behavior, not just draw a row of icons.

`quotabar` is a particularly clean first integration. Its Rust process already
fetches provider data, owns authentication and cache semantics, atomically writes
[`~/.cache/quotabar/state.json`](https://github.com/thrawny/quotabar/blob/561bcbd340bc153aa9b48d9aab5b9cdee3ccfcf9/src/cache.rs#L8-L47),
and exposes a Waybar JSON view
([README](https://github.com/thrawny/quotabar/blob/561bcbd340bc153aa9b48d9aab5b9cdee3ccfcf9/README.md#L22-L42)).
Quickshell can initially read that state file and call the existing command. Later,
if live updates need to be event-driven, add a small subscription socket without
changing ownership of provider logic.

`agent-switch` already owns daemon state, ranking/lifecycle behavior, Niri IPC,
and agent integrations in Rust. Its documented CLI includes JSON list/focus views
and a daemon socket
([architecture](https://github.com/thrawny/agent-switch/blob/8c0b58b520ea79e41042a08ba99603472158b8e9/README.md#L3-L10),
[CLI and socket](https://github.com/thrawny/agent-switch/blob/8c0b58b520ea79e41042a08ba99603472158b8e9/README.md#L144-L152)).
The GTK prototypes are large because they mix a rich interface with application
plumbing. A read-only QML sidebar backed by a versioned snapshot plus explicit
verbs is a good experiment; migrating ranking, lifecycle, Niri actions, or
persistence into QML is not.

This split also keeps Waybar, GTK, a future native shell, and tests viable as
alternate clients. Quickshell becomes a replaceable frontend, not a new owner of
the user's data or workflows.

## Niri examples worth studying

Niri's own integration guide points users toward complete shells, and the
[awesome-niri catalogue](https://github.com/niri-wm/awesome-niri) lists bars,
widgets, custom shells, and the QML bridge ecosystem. The most useful references
for this project are:

- **DankMaterialShell:** study
  [`NiriService.qml`](https://github.com/AvengeMedia/DankMaterialShell/blob/d4fecfcd5c020f1e819df174ed4b0fb1f6187b8c/quickshell/Services/NiriService.qml),
  its compositor abstraction, `Modules/DankBar`, shared `Widgets`, and `Common`
  theme resources. This is the production architecture reference.
- **iNiR:** a large Niri-first Quickshell configuration with a useful
  [architecture map](https://github.com/snowarch/iNiR/blob/fdb723afbde6396985fa0b67accaa6f96a05c393/ARCHITECTURE.md).
  Use it as a behavior catalogue; its own architecture note is candid about its
  personal-project origins.
- **niriha:** a small
  [14-file Quickshell example](https://github.com/tahfizhabib/niriha/tree/c467819961b1ac15916b281aa24e13a257a55f4a/.config/quickshell/niriha)
  with a bar, control center, notifications, and simple Niri IPC bindings. It is
  much easier to read than the full shells, but still early and opinionated.
- **qml-niri:** a native
  [Qt/QML Niri IPC plugin](https://github.com/imiric/qml-niri/tree/93e603901bed2c4465d5675ae43fd52b7f7c4adf)
  exposing windows, workspaces, focus, urgency, layouts, and keyboard state. It is
  promising, but still a young third-party dependency. Its Nix flake provides a
  Quickshell build containing the plugin; system-wide and `QML_IMPORT_PATH`
  installation are also documented. Hide it behind a local `NiriService.qml` so
  replacing it does not touch every widget.

Do not copy one configuration wholesale. Use DMS for boundaries, iNiR for feature
coverage, niriha for readable mechanics, and qml-niri as an optional adapter.

## Proposed shape

```text
config/quickshell/thrawny/
├── shell.qml
├── Common/
│   ├── Theme.qml
│   └── Icons.qml
├── Services/
│   ├── NiriService.qml
│   ├── QuotabarService.qml
│   ├── AgentSwitchService.qml
│   └── KeybindCatalogService.qml
└── Modules/
    ├── Bar/
    ├── AgentSidebar/
    └── CommandPalette/
```

The QML services are adapters, not authorities. Each should expose a small typed
view of one external interface, reconnect after producer or Niri restarts, and
have a mock fixture for UI work. The semantic palette proposed in the Omarchy
review should feed `Theme.qml` so Niri, the shell, terminals, and mutable editor
themes share roles without forcing identical rendering.

The keybinding catalogue belongs in this architecture too. Keep a higher-level
normalized schema as the desired end state, but begin with adapters that read the
resolved Niri binds and the xremap source into one searchable dataset. A
Quickshell command palette can then search descriptions, chord segments, apps,
and tags and dispatch only actions explicitly marked safe. That solves
discoverability without making Quickshell the source of truth for input handling.

## Migration plan

### Phase 0: stable contracts

1. Record the current Waybar behavior as a parity checklist: full and compact
   output layouts, Niri workspaces, window title, keyboard layout, tray, network,
   audio, battery, clock, caffeine, quota state, and agent state.
2. Version the `quotabar` state schema and expose an event-driven update mechanism
   only if file watching is insufficient.
3. Give `agent-switch` a versioned snapshot/subscription interface and explicit
   action verbs. Avoid a UI-shaped protocol.
4. Decide whether `NiriService.qml` starts with `niri msg --json`/event-stream
   parsing or the `qml-niri` plugin. Keep the adapter boundary identical either
   way.

### Phase 1: bar pilot

Build only:

- Niri workspaces and focused window;
- clock and tray;
- `quotabar` status and its existing popup action;
- `agent-switch` status and a read-only sidebar;
- the current Molokai-derived theme;
- separate compact/full layouts selected by output.

Run it in parallel without an exclusive zone during development. Make switching
between Waybar and Quickshell a single Home Manager option; do not remove Waybar,
GTK popups, Mako, SwayOSD, Walker, or the lock/idle stack.

### Phase 2: earn consolidation

After the bar is reliable, add the searchable Niri+xremap keybinding catalogue and
the curated action palette. Then consider audio/network/Bluetooth panels,
notifications, OSD, and launcher functionality one at a time. Retire an existing
utility only when the replacement is better in daily use and has a trivial
rollback.

Lock, idle, polkit, and notification-daemon ownership should be late migrations.
They have larger security and recovery consequences than a bar or sidebar and do
not need to share a process merely to share a theme.

## Go/no-go checks

Adopt the Quickshell bar as the default only after it passes all of these:

- seven ordinary working days without a shell restart being needed;
- correct compact/full behavior on the Z13 panel, external displays, hot-plug,
  lid changes, and fractional scaling;
- clean reconnection after Niri, `quotabar`, or `agent-switch` restarts;
- no stale quota/agent state and no polling loop materially worse than today;
- correct tray menus, keyboard focus, popup dismissal, and fullscreen behavior;
- suspend/resume and dock/undock without duplicate surfaces;
- measured idle CPU and memory acceptable on both machines;
- `just switch` can select Waybar again without manual cleanup.

If the experiment fails because QML or Quickshell itself is the friction, try the
same provider contracts with Ignis. If it fails because authoring a shell is too
large a hobby project, install ashell or trial DMS/Wayle. None of those outcomes
wastes the backend-contract work.

## Final recommendation

Proceed with Quickshell, but frame the work as **a frontend pilot over stable Rust
services**, not “rewrite the desktop.” It is the most compelling option for the
integrated, personal, visually expressive system now being considered. Ignis is
the best true framework alternative and has better built-in Niri support; ashell
is the best pragmatic bar replacement; DMS and Wayle are the best adopt-rather-
than-build trials.

The first implementation should stop after one excellent bar, one `quotabar`
integration, and one read-only `agent-switch` sidebar. If that slice is pleasant
to build and more reliable than the current bar, the larger shell has earned the
right to exist.
