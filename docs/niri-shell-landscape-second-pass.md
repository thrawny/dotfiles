# Niri shell landscape: independent second pass

Research snapshot: 2026-08-16. This is a fresh decision pass over complete
shells, shell frameworks, bars/panels, and native application approaches. It
supersedes the simple “Quickshell wins” interpretation of the earlier review;
the earlier document remains useful for its architecture notes and migration
inventory.

## Bottom line

Three conclusions survive a deliberately neutral comparison:

1. **DankMaterialShell (DMS) is the strongest ready-made Niri shell today.** It
   is current, Niri-oriented, Nix-friendly, and has a real plugin surface.
2. **Quickshell is the strongest foundation for a visually ambitious bespoke
   shell.** It has the best combination of arbitrary layer surfaces, Qt Quick's
   composition/animation model, active development, and substantial Niri shell
   examples.
3. **Neither conclusion proves that this setup should replace everything with
   DMS or Quickshell now.** `agent-switch` and `quotabar` already contain useful
   Rust state, policy, provider, cache, and Niri logic. GTK4 is already capable
   of the difficult sidebar interaction. A fair decision is therefore a small
   frontend comparison over stable Rust contracts, not a wholesale rewrite.

The recommended experiment is a two-way vertical slice:

- the existing Rust/GTK4 path;
- standalone Quickshell over the same Rust contracts.

Run a separate, bounded DMS plugin feasibility spike to learn whether its
supported extension boundary can host the desired experience without a fork.
Keep AGS 3/Gnim in reserve if TypeScript ergonomics become the primary decision
criterion; neither independent evaluator ranked it above Quickshell, and its
Niri integration adds another unsettled dependency to this first test.

Do not include Ignis Python in that implementation contest unless the prototype
is explicitly disposable. Its current release is the final Python generation
before a Rust rewrite, so success would create a known migration rather than
select a durable foundation.

## How this pass avoided anchoring

Two evaluators received the same neutral prompt in fresh sessions. They were
forbidden from reading the existing review, PR, or its commits; each had to set
and disclose criteria before ranking; both were asked to use primary sources and
inspect the current checkout plus the public `quotabar` and `agent-switch`
repositories. They were not told that Quickshell, DMS, GTK, Python, or
TypeScript was preferred.

The evaluators chose meaningfully different weights. One emphasized Niri and
multi-output correctness (20%), extension boundaries (15%), reliability (15%),
and agent maintainability (15%). The other put equal top weight on Niri
correctness and agent-authored maintainability (20% each), followed by
reliability (15%), Nix and visual ceiling (12% each), integration cost (10%),
project health (6%), and portability (5%). This is useful: agreement is less
likely to be an artifact of one scoring rubric.

## Independent result

Both evaluators independently reached the same category winners:

- **best immediate direction:** retain the modular desktop, productionize the
  Rust service/UI boundaries, and test the existing GTK4 sidebar against a
  Quickshell client;
- **best finished shell:** DMS;
- **best custom full-shell framework:** Quickshell;
- **best low-risk fallback:** the current Waybar configuration after Nix
  packaging and systemd supervision fixes.

This is stronger validation than simply repeating the earlier recommendation.
It confirms that Quickshell leads its category, while rejecting the inference
that category leadership justifies moving the whole desktop there now. One
evaluator included a DMS plugin in the frontend prototype; the other kept DMS as
a later product-adoption branch. The synthesis below uses a small feasibility
spike rather than implementing full parity in DMS.

## Corrections and new facts since the first pass

### Ignis is capable, but the released Python line is ending

The released Ignis implementation remains an unusually good Niri framework on
paper: Python, GTK4, a first-party Niri service, built-in desktop services, and
an official Home Manager module. Its Niri model includes workspaces, windows,
keyboard layouts, focused output, and commands
([Niri service](https://ignis-sh.github.io/ignis/stable/api/services/niri.html));
the service catalogue includes audio, Bluetooth, network, notifications, tray,
UPower, MPRIS, wallpaper, and more
([service index](https://ignis-sh.github.io/ignis/stable/api/services/index.html)).

The strategic fact is decisive, however: the `v0.6.0` release explicitly calls
itself the final Python release before a Rust rewrite and recommends that
`v0.5.1` users stay there until the rewrite is complete
([release](https://github.com/ignis-sh/ignis/releases/tag/v0.6.0)). The visible
Rust experiment is not yet a released, feature-complete alternative. Ignis
Python is therefore a reasonable pinned existing system, but a poor default for
a new multi-year shell in August 2026.

### Quickshell now has generic workspace support, not full Niri integration

Quickshell `v0.3.0` added a generic `WindowManager` module over
`ext-workspace-v1` ([type documentation](https://quickshell.org/docs/v0.3.0/types/Quickshell.WindowManager/)).
Niri has supported the protocol since `v25.08`. That corrects the earlier blanket
statement that Quickshell has no built-in Niri workspace path.

It still does not provide a Niri-specific model for windows, layouts, keyboard
state, overview, urgency, or compositor actions. Those require Niri IPC, local
adapter code, or a third-party bridge such as `qml-niri`. Quickshell remains a
low-level QML toolkit rather than a finished desktop API
([official overview](https://quickshell.org/about/)). It is also pre-1.0 and
uses private Qt APIs, so distributions must rebuild it for Qt ABI changes
([build requirements](https://github.com/quickshell-mirror/quickshell/blob/master/BUILD.md)).

### AGS has a Niri path, but not an upstream Astal one

AGS 3 is a serious bespoke-shell candidate, not merely a legacy JavaScript
widget tool. Current AGS uses TypeScript/JSX, GJS, GTK4, and Gnim; Astal supplies
backend libraries, and the CLI supplies scaffolding, generated types, bundling,
and an official Nix template
([overview](https://aylur.github.io/ags/),
[Nix guide](https://aylur.github.io/ags/guide/nix.html)). This is the best option
when agent-readable TypeScript, static refactoring, and GTK continuity matter
more than QML's visual model.

Upstream Astal still has no Niri library in its published library list
([references](https://astal.dev/guide/libraries/references)). The
`libastal-niri` used by
[Delta Shell](https://github.com/Sinomor/delta-shell) comes from the small
`sameoldlab/astal` `feat/niri` fork; the AUR package points directly at that
branch
([PKGBUILD](https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h=libastal-niri-git)).
AGS can also consume Niri IPC directly. The distinction matters: Niri support is
real community code, but not yet an upstream Astal compatibility promise.

AGS also has visible architectural churn: AGS v1, Astal-era v2, then the Gnim
runtime and reactive API in v3. The current direction is active and coherent,
but GJS/GObject introspection is not ordinary Node/DOM TypeScript; generated
types do not eliminate runtime GI and GTK semantics.

### DMS is more extensible than the first review credited

DMS `v1.5.3` is a complete Quickshell-and-Go product with first-class Niri
setup, Nix modules, and a backend/frontend socket boundary. Its documented plugin
system supports:

- bar and control-center widgets with popouts;
- headless daemon plugins;
- launcher providers;
- movable/resizable desktop widgets with optional keyboard focus;
- composite packages combining several of those roles.

Plugins have manifests, settings, dependency/startup checks, hot reload, and a
documented permission vocabulary
([plugin development](https://danklinux.com/docs/dankmaterialshell/plugin-development/)).
DMS is therefore the best product to pilot, and a plausible host for quota and
agent status widgets.

The unresolved boundary is the important one: the docs do not clearly expose an
arbitrary, continuously visible, exclusive-edge side panel as a plugin type. A
desktop widget or popout may not have the same focus, strut, output, and lifecycle
semantics as the desired `agent-switch` sidebar. Do not fork DMS to answer this;
make the plugin spike a strict go/no-go test.

### Noctalia v5 is no longer a Quickshell data point

Noctalia v5 is a ground-up native shell built directly on Wayland and OpenGL ES,
not the older Quickshell implementation. It has Niri integration, Nix modules,
and a broad Luau plugin system for bar widgets, panels, desktop widgets,
launcher providers, and services. Plugin code runs off the UI thread in isolated
VMs with time budgets and an explicit plugin API level
([plugin development](https://docs.noctalia.dev/noctalia/plugins/development/)).

That architecture is compelling, especially for third-party extension
isolation. The current release is still `v5.0.0-beta.8`, and its own docs warn
that plugin APIs may change before stable
([release](https://github.com/noctalia-dev/noctalia/releases/tag/v5.0.0-beta.8)).
Treat it as the strongest watchlist product, not a stable foundation today.

## Category-correct comparison

| Option | What it is | Strongest reason to choose it | Main reason not to choose it now | Verdict here |
| --- | --- | --- | --- | --- |
| **DMS** | Finished Quickshell + Go shell | Best current Niri product, Nix integration, broad plugin API | Adopts many product decisions; persistent custom sidebar boundary unproven | **Best adoptable shell; prototype its plugin boundary** |
| **Custom Quickshell** | Low-level Qt Quick shell toolkit | Best visual composition, arbitrary surfaces, deepest Niri example ecosystem | QML/JS, pre-1.0 churn, no full first-party Niri model | **Best bespoke visual-shell foundation** |
| **AGS 3 / Gnim / Astal** | TypeScript/JSX shell framework over GTK/GI services | Best agent-authored TypeScript ergonomics; GTK4 continuity | Community/forked Niri layer; GJS/GI weakens normal TS guarantees; recent architecture churn | Best paper challenger; not in the first prototype |
| **Rust + GTK4/Relm4** | Native applications and layer surfaces | Existing code and tests, exact `niri-ipc`, strongest types and process isolation | More UI boilerplate; custom animation/composition costs more | **Equal-footing prototype, not merely a fallback** |
| **Ignis Python** | Python/GTK4 shell framework | Shortest high-level path with first-party Niri and services | Officially the final Python generation before rewrite | **Do not start a durable shell on it** |
| **Noctalia v5** | Finished native C++ shell with Luau plugins | Broad product, Niri support, unusually good plugin isolation | Beta and pre-stable plugin API | **Watch and retest at stable** |
| **Wayle** | Finished Rust/GTK4/Relm4 shell | Native, Niri-aware, Nix/HM, TOML and settings GUI | Custom modules are command-backed bar items, not a rich UI SDK | Good adoptable GTK product, weak custom host |
| **VibePanel** | Rust/GTK4 integrated panel | Strong Niri backend, notifications/OSD/quick settings, streaming custom modules | Bar/panel product, no arbitrary rich UI SDK, active pre-1.0 churn | Best featureful Waybar-scale trial |
| **ashell** | Rust/Iced bar plus settings/notifications/OSD | Low-effort Niri replacement with Nix/HM and streaming custom items | Not a general application/sidebar framework | Best compact ready-made bar fallback |
| **Ironbar** | Rust/GTK4 configurable bar | Rich declarative popouts, scripts/Lua, HM module | Explicitly alpha; partial Niri support; still bar-scoped | Flexible middle ground, not the consolidation target |
| **Eww** | Rust daemon with Yuck/GTK3 frontend | Mature widget DSL and shell-command integration | No Niri model; GTK3/Yuck awkward for application-like sidebar state | Good widgets, wrong service spine |
| **Fabric** | Python/GTK3 widget framework | Friendly signal-based Python with typing and many examples | No first-party Niri model; weaker Nix story; GTK3 | Inferior to Ignis for this Niri setup |

Finished Niri projects such as iNiR, Delta Shell, Exo, Glimpse, and GPUI Shell
remain valuable reference implementations. They do not currently offer a more
credible stable extension boundary than the shortlisted product/framework
options. Niri's maintained catalogue is the best discovery index
([awesome-niri](https://github.com/niri-wm/awesome-niri)).

## What the current setup changes

This is not a greenfield bar. The current configuration already has separate
compact and full output layouts, Niri workspaces/window/language, Walker,
xremap, Mako, SwayOSD, tray, network, audio, battery, caffeine, quota state, and
agent state. The migration must preserve output-local Niri semantics, not merely
redraw icons.

Two apparent “Waybar bugs” should be separated from framework choice first:

- Waybar is launched directly from Niri rather than supervised as a user service.
- `quotabar` is invoked from `~/.cargo/bin`, while an `agent-switch` click action
  invokes a debug binary under the source tree.

Those packaging and lifecycle gaps can produce missing/stale modules regardless
of renderer. Niri's own systemd guide recommends graphical-session-bound user
services because they provide logs and independent restart/reload behavior
([systemd setup](https://niri-wm.github.io/niri/Example-systemd-Setup.html)).

More importantly, the hard work is already below the bar:

- `quotabar` owns provider authentication/fetching, cache semantics, pacing, and
  a GTK popup. Keep that logic in Rust.
- `agent-switch` owns thread/session identity, hooks, daemon state, Niri
  correlation/actions, and a substantial GTK sidebar prototype. Keep that logic
  in Rust.

Before comparing frontends, give both programs a UI-neutral contract: protocol
version, initial snapshot, monotonically sequenced updates, capabilities,
semantic action verbs, reconnect/backoff rules, and explicit staleness. That work
survives every result in the table.

## Smallest fair prototype

Use identical fixtures, semantic theme tokens, icons, and backend contracts. The
GTK4 and Quickshell candidates must implement only:

1. a quota/agent bar chip;
2. a rich quota popout;
3. a 320-pixel persistent agent sidebar on a selected output;
4. Niri workspace, focused-window, and keyboard-layout state;
5. compact laptop and full external-output layouts.

Build the slice in Rust/GTK4 and standalone Quickshell. Separately, implement the
smallest DMS bar widget/popout that consumes the same fixtures, then stop as soon
as its documented API either proves or disproves a supported persistent-sidebar
path. Do not bend the desktop-widget API into an undocumented role and do not
fork DMS. Do not replace Walker, xremap, Mako, SwayOSD, lock, idle, or polkit in
this experiment.

Score what agents actually produce, not what the framework promises:

- cold implementation time and repair time from a fresh context;
- compile/type/LSP diagnostics and testability;
- correctness across eDP/external/mixed-scale hotplug;
- focused versus visible-active Niri workspaces;
- fullscreen, overview, keyboard focus, and popup dismissal;
- reconnect after Niri and backend restarts;
- idle CPU, RSS, GPU/frame behavior, and logs;
- Nix pinning and one-switch rollback to Waybar.

## Decision rule

- Choose **DMS** if its plugin boundary can host the desired sidebar and the
  product's launcher/notification/OSD/lock decisions are welcome.
- Choose **custom Quickshell** if the goal is a singular visual language and its
  prototype materially beats GTK/AGS on composition without losing reliability.
- Reopen **AGS 3** only if the Quickshell prototype fails mainly because agents
  cannot maintain QML safely; then test whether TypeScript's diagnostics offset
  the community Niri adapter and GJS/GI runtime boundaries.
- Keep **Rust/GTK4** if it meets the visual target. It has the lowest migration
  risk because the existing utilities already live there.
- Re-evaluate **Noctalia v5** after a stable release. Do not select the unfinished
  Ignis Rust rewrite or begin new durable work on Ignis Python in the meantime.

The safe commitment now is not to a renderer. It is to the Rust service contracts,
fixtures, theme tokens, Nix supervision, and parity tests. Quickshell remains the
front-runner for a custom integrated shell; DMS remains the front-runner for
adopting one; the vertical slice decides whether either beats what is already
working.
