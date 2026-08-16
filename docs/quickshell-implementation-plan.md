# Custom Quickshell implementation plan

Planning snapshot: 2026-08-16. This plan assumes the decision is to build a
custom Quickshell frontend for Niri. DMS, iNiR, and other shells are references,
not codebases to fork.

## Intended outcome

The first production outcome is deliberately smaller than “replace the desktop”:

- a full external-monitor bar and compact laptop bar;
- a rich `quotabar` status/popover;
- an `agent-switch` status item and persistent sidebar;
- Niri workspaces, focused window, and keyboard layout;
- shared semantic theming;
- a searchable keybinding catalogue;
- a one-option rollback to the current Waybar stack.

Quickshell owns rendering, layout, animation, focusable surfaces, and interaction.
It does not own provider authentication, quota calculations, agent/thread
lifecycle, persistence, or Niri policy.

```text
Niri event stream ────────────────> NiriService.qml ───────┐
agent-switchd snapshot/events ────> AgentSwitchService.qml ├─> Quickshell surfaces
quotabar state/actions ───────────> QuotabarService.qml ───┘   bar, popovers, sidebar

Niri + xremap declarations ──> keybinding catalogue JSON ──> searchable palette
semantic palette ────────────> theme JSON/QML singleton ───> every surface
```

The existing components remain authoritative and independently restartable. A
Quickshell crash must not stop agent tracking, corrupt quota state, or alter
input handling.

## Repository ownership

### Dotfiles

This repository owns deployment and the frontend during the pilot:

```text
config/quickshell/thrawny/
├── shell.qml
├── qmldir
├── Common/
│   ├── Theme.qml
│   ├── Metrics.qml
│   └── Icons.qml
├── Services/
│   ├── NiriService.qml
│   ├── AgentSwitchService.qml
│   ├── QuotabarService.qml
│   └── KeybindCatalogService.qml
├── Models/
├── Components/
├── Surfaces/
│   ├── Bar/
│   ├── AgentSidebar/
│   └── Popovers/
└── Fixtures/
```

For a repo-backed Home Manager activation, the configuration should be an
out-of-store symlink so Quickshell hot reload sees edits immediately. Store-backed
and container builds should use the same source immutably. If the frontend later
becomes useful outside these dotfiles, extract it into a separate flake only
after the pilot passes its adoption gates.

The dotfiles also own:

- the pinned Quickshell and optional QML-plugin versions;
- Home Manager configuration and systemd supervision;
- the Waybar/Quickshell selector and rollback path;
- the semantic palette and generated keybinding catalogue;
- root `just` recipes for checking, mock-running, launching, switching, and
  reading logs.

### `agent-switch`

`agent-switch` continues to own thread identity, hook normalization, durable
state, ranking, lifecycle, Niri correlation, and semantic actions. Its current
newline-JSON request/response socket needs a frontend-grade versioned interface:

- handshake with protocol version and capabilities;
- complete initial snapshot;
- monotonically sequenced updates;
- server timestamp and state revision;
- subscription stream with reconnect/resume behavior;
- typed commands such as focus, summon, rename, mark-read, archive, and toggle;
- explicit errors rather than UI-shaped fallback strings;
- fixtures and contract tests for empty, malformed, stale, and large registries.

The current Waybar projection remains available during migration. The QML layer
must not reimplement ranking, persistence, hook handling, or direct Niri window
correlation.

### `quotabar`

`quotabar` continues to own credentials, provider APIs, caching, quota/pace
calculations, refresh policy, and notifications. Before multiple frontends rely
on it:

- version the existing provider-neutral state schema;
- include revision, generated-at, refreshed-at, and stale/error fields;
- package its binary and assets through Nix instead of `~/.cargo/bin`;
- expose explicit CLI or socket actions for refresh and provider selection;
- add a subscription socket only if watching the atomic state file proves
  insufficient.

Quickshell initially reads the state file and watches for replacement. Secrets
and provider-specific parsing never enter QML.

## Architectural rules

1. **QML services are adapters, not authorities.** They normalize an external
   contract and expose narrow properties/signals to components.
2. **No business logic in shell commands.** Processes may transport state or
   invoke typed actions; they must not become untested pipelines of `jq`, `sed`,
   and polling.
3. **Minimize JavaScript.** Prefer QML properties, models, bindings, required
   properties, enums, and small pure helpers. Avoid a mutable global JS state
   bus.
4. **Every service has fixtures.** UI work must be possible without live Niri,
   API credentials, or running agents.
5. **Output identity is explicit.** Connector name, description, scale, laptop
   status, and chosen layout are data—not scattered string comparisons.
6. **Surfaces do not own persistence.** Restarting or hot-reloading Quickshell
   reconstructs the full UI from backend snapshots.
7. **Replacement is incremental.** An existing component is retired only after
   its Quickshell replacement passes the same acceptance matrix and rollback is
   trivial.

## Niri integration decision

Keep all compositor access behind `NiriService.qml`. For the first implementation,
consume the official JSON event stream as one long-lived process: it supplies an
initial snapshot followed by deltas and avoids polling. The adapter should expose:

- outputs and their scale/identity;
- ordered workspaces per output, including active, focused, urgent, and named
  state;
- windows and the focused/per-output active window;
- keyboard layouts and active layout;
- overview state;
- typed Niri actions used by the shell.

The adapter must resnapshot after disconnect, tolerate unknown fields/events,
and publish one coherent revision to consumers. Do not let individual widgets
spawn their own `niri msg` processes.

During the skeleton milestone, compare this adapter with pinned `qml-niri` using
the same tests. Keep `qml-niri` only if it materially reduces code and passes
restart, hotplug, and version-pin checks. Because consumers see only the local
service interface, either implementation remains replaceable. If QML event
normalization becomes difficult to test, move only that adapter into a small
Rust sidecar using the pinned `niri-ipc` crate.

## Theme and component system

Create one data-first semantic palette rather than copying Molokai literals into
each UI:

- roles: background, surface, elevated surface, foreground, muted, accent,
  secondary accent, warning, error, success, outline, shadow;
- terminal colors remain a separate indexed set;
- spacing, radii, typography, animation durations, and motion curves are tokens;
- components consume semantic roles, never source palette names.

Nix should read the palette source and generate the shell-facing JSON/QML data,
Niri colors, and later other immutable consumers. Mutable Neovim and agent theme
trees retain their current ownership and may consume generated data separately.

Build a small component vocabulary before feature modules:

- status chip, icon button, badge, tooltip;
- popover frame and focus/dismiss behavior;
- list row, section header, empty/error/stale states;
- output-aware bar region;
- keyboard-focus boundary and accessible labels;
- loading, reconnecting, degraded, and unavailable states.

This is what makes later integrations look cohesive; a common color file alone
does not.

## Implementation batches

### Batch 0 — baseline and reversible deployment

Before drawing the new bar:

1. Record Waybar parity: full/compact output layouts, workspaces, window,
   language, tray, network, audio, battery, clock, caffeine, both quota providers,
   and agent state.
2. Add a Home Manager enum such as
   `dotfiles.desktop.shell = "waybar" | "quickshell"`, defaulting to Waybar.
3. Nix-package `agent-switch` and `quotabar`; remove the current
   `~/.cargo/bin/quotabar` and `target/debug/agent-switch` dependencies.
4. Supervise the agent daemon and selected bar through graphical-session-bound
   user services with restart-on-failure and journal logs.
5. Keep the current Waybar files intact and make rollback a single configuration
   change plus `just switch`.

Deliverable: no Quickshell UI yet, but the current desktop no longer depends on
source-tree/debug paths and has observable restart behavior.

### Batch 1 — Quickshell skeleton and mock mode

1. Add the directory structure, QML singleton/module declarations, and a minimal
   transparent test surface.
2. Pin Quickshell through Nix and wire the configuration through Home Manager.
3. Add a supervised user service, but keep it disabled by default.
4. Add root recipes such as `just shell-check`, `just shell-mock`,
   `just shell-dev`, and `just shell-logs`.
5. Add formatting/static checks and a fixture mode that renders without live
   services.
6. Run beside Waybar in overlay/no-exclusive-zone development mode so it cannot
   disturb the working desktop.

Deliverable: reproducible empty shell, hot reload, mock data, logs, and no effect
on the daily session.

### Batch 2 — Niri model and bar frame

1. Implement and test `NiriService.qml`.
2. Create exactly one bar surface per output.
3. Select compact/full layout from output metadata, not widget-local conditions.
4. Implement workspaces, focused window, and keyboard layout.
5. Verify active-visible versus keyboard-focused workspace state.
6. Handle output add/remove, scale changes, Niri restart, overview, fullscreen,
   and surface recreation.

Deliverable: a Niri-native skeleton bar that can run for a day alongside Waybar.

### Batch 3 — custom Rust integrations

1. Land the versioned `agent-switch` snapshot/subscription contract and fixtures.
2. Build the agent status chip and read-only sidebar against fixtures, then live
   events.
3. Add semantic agent actions only after rendering/reconnect behavior is stable.
4. Version `quotabar` state and build provider chips plus a rich quota popover.
5. Ensure backend death shows stale/degraded state while the rest of the shell
   remains usable.

Deliverable: the two differentiating features—quota UI and agent sidebar—work
without moving their domain logic into QML.

### Batch 4 — bar parity

Replace the remaining visible Waybar modules one at a time:

1. clock and calendar;
2. system tray, including menus;
3. PipeWire sinks/sources and volume controls;
4. network and VPN state;
5. battery and power profile;
6. caffeine state/action;
7. privacy and recording indicators where data is available.

Use Quickshell's native service APIs when mature. Hide each behind a local
service adapter so components never depend directly on framework-global objects.

Deliverable: functional parity with both current Waybar layouts. Mako, SwayOSD,
Walker, lock/idle, and wallpaper still remain external.

### Batch 5 — searchable keybinding catalogue

Create a normalized binding schema with stable ID, backend (`niri` or `xremap`),
trigger/chord, description, category, tags, scope, and dispatch metadata.

1. Export current Niri and xremap declarations into one generated JSON catalogue.
2. Prefer generating both configurations from the normalized declarations where
   their semantics match; keep an explicit raw escape hatch for complex xremap
   sequences and application-specific rules.
3. Build a searchable Quickshell palette over the resolved catalogue.
4. Search descriptions, key sequences, apps, tags, and chord prefixes.
5. Dispatch only entries explicitly marked safe; discovery must work even for
   non-dispatchable bindings.

Quickshell is the catalogue/search frontend, not the input engine. Niri and
xremap keep handling keys.

Deliverable: one place to discover every effective binding without weakening
the existing input model.

### Batch 6 — controlled cutover

1. Enable exclusive zones and disable Waybar through the shell selector.
2. Run the full acceptance matrix below.
3. Use Quickshell as the default for seven ordinary working days.
4. Keep Waybar packaged and configured for at least one further release cycle.
5. Record failures by service/surface and fix them without expanding scope.

Deliverable: Quickshell becomes the default bar/sidebar with a one-switch Waybar
rollback.

### Batch 7 — earn further consolidation

Only after the cutover is stable:

1. replace SwayOSD;
2. add capture, audio-sink, Wi-Fi QR, Taildrop, reminder, and similar action
   surfaces;
3. replace Mako with Quickshell notifications and history;
4. build a Quickshell launcher frontend over Elephant or another stable provider
   boundary, then consider retiring Walker;
5. integrate wallpaper/backdrop behavior;
6. consider lock UI last, while retaining a separately supervised idle/power
   policy.

Lock, authentication, idle, and polkit are intentionally late because their
failure and recovery consequences are larger than those of a bar or popover.

## Validation strategy

### Automated on every change

- QML formatting and lint/static diagnostics;
- Nix formatting and evaluation;
- backend contract tests and checked-in JSON fixtures;
- component startup against empty, normal, stale, malformed, and large fixture
  sets;
- a smoke launch that proves the QML module graph loads;
- `git diff --check` and root task-runner recipes only.

Do not make a live Wayland session or real credentials necessary for ordinary UI
checks.

### Manual acceptance matrix

- Z13 panel, each external output, and the current full/compact layouts;
- connect/disconnect, lid close/open, dock/undock, and mixed scaling;
- suspend/resume and Niri restart;
- kill/restart Quickshell, `agent-switchd`, and `quotabar` independently;
- focused versus visible-active workspaces, named workspace moves, urgency,
  overview, and fullscreen;
- tray menus, popup placement/dismissal, keyboard focus, and sidebar command mode;
- no duplicate exclusive zones or orphaned surfaces;
- quota and agent state never silently remain stale;
- acceptable idle CPU, RSS, and frame behavior;
- useful structured journal logs;
- `dotfiles.desktop.shell = "waybar"` restores the old UI without manual cleanup.

## Cutover gates

Quickshell becomes the default only when all of these are true:

- bar parity is documented and complete on both layout classes;
- no source-tree, debug-build, or `~/.cargo/bin` paths remain;
- every long-lived process is supervised and reconnects after dependency restart;
- seven normal working days require no manual Quickshell restart;
- hotplug, suspend, overview, fullscreen, tray, and focus tests pass;
- resource use is measured and acceptable on both machines;
- the backend protocols are versioned and covered by fixtures/tests;
- rollback remains a single Home Manager option.

## Recommended first implementation sequence

The first work should be three focused changes, in this order:

1. **Backend/deployment hygiene:** package `agent-switch` and `quotabar`, remove
   hard-coded paths, supervise current processes, and introduce the shell selector.
2. **Quickshell spine:** add the pinned empty shell, local component/service
   structure, fixture mode, root recipes, and Niri adapter.
3. **Decision slice:** implement workspaces/window/language, quota popover, and a
   read-only agent sidebar before porting generic battery/network/audio modules.

That slice tests the reasons to choose Quickshell—integrated composition, richer
popovers, and the agent sidebar—without spending time recreating commodity status
modules first. If it is not clearly better than the GTK/Waybar experience, stop;
all backend, packaging, theme, and keybinding-catalogue work remains useful.
