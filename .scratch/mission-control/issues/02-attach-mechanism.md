# Attach mechanism

Type: prototype
Status: claimed

## Question

What is the default attach verb, concretely? Build throwaway prototypes in ghostty + niri and decide by feel.

Scoping refined 2026-08-03 (discussion before build):

- **Model refinement**: workspaces are *areas of work* (projects — the niri-project role) that threads visit; threads stay non-spatial. The enemy is the ever-expanding strip of session terminals per workspace.
- **Summon-to-me only** (decided 2026-08-03): no "go to the window" sub-verb — cross-area pulls aren't a real workflow (a kanel thread doesn't get summoned into the dotfiles area), so one verb suffices.
- **Prior art is nirius scratchpads**: `nirius scratchpad-show-or-spawn --app-id …` (Mod+O/P today) and `nirius workspace-scratchpad` (Mod+Q) already implement summon-to-me + dismiss-to-hidden. The thread verb is this pattern keyed by *thread* instead of app-id, with a picker choosing the target.
- **Prototype — the full loop, no zmx needed**: picker over `niri msg windows` (windows with running agent sessions) → summon pulls the window to the current workspace (move-or-spawn); dismiss (one keystroke from inside the thread) sends it back to the scratch/hidden state. Works against today's real sessions.
- **Managed scratch ≠ the strip**: parked windows are invisible except via the picker — spatial-absence-at-rest implemented with windows instead of zmx headlessness. Known costs, accepted for the prototype: window lifetime = compositor-session lifetime (parked threads die on reboot; pi/claude resume anyway), and scratch grows unbounded until lifecycle verbs close things. zmx remains the durability layer for persistence + remote — now decoupled from the attach verb entirely.
- Window↔thread identification: env handshake + window title (needed for move-or-spawn dedup and for the picker's labels).
- Still worth shipping regardless: the in-place-from-shell CLI (`fzf → exec attach`, ~5 lines) for when you're already in a terminal.

## Prototype (built 2026-08-03, mechanics verified in nested niri via niri-cu)

- `bin/thread-summon` — fzf picker (floating ghostty, Mod+S). Rows join `agent-switch list` (sessions are keyed by niri window id — the window↔thread identification problem was already solved by agent-switch hooks; no env handshake needed) with `niri msg --json windows`. Row: `agent  state  project-dir  [here|ws N|parked]  title`. `THREAD_SUMMON_ALL=1` lists all windows (testing).
- `bin/thread-dismiss` — one keystroke (Mod+Shift+S): focused window in nirius scratchpad → `scratchpad-show` bounces it back to hidden; otherwise `scratchpad-toggle` parks it (first-time adoption).
- Summon paths, all verified: parked → `nirius scratchpad-show --id` (appears floating + focused on current workspace); visible elsewhere → `niri msg action move-window-to-workspace --window-id` + focus; already here → focus only (dedup).
- **Pin-to-workspace falls out for free**: `nirius scratchpad-toggle` on a summoned window un-adopts it into a normal window — the map's "heavy engagement" verb needs no new code.
- Observations for the blueprint:
  - nirius's scratch state is the *bottom-most workspace*, not true invisibility — parked windows are reachable by scrolling down. Same mental model as Mod+Q workspace-scratchpad; acceptable, but "spatial absence at rest" is approximate.
  - The bottom-most workspace is recomputed as workspaces appear/close, so scratch membership must be tracked by nirius state (`list-scratchpad`), never by workspace position.
  - `nirius move-to-current-workspace` has no `--id`; exact-window moves need raw niri IPC. Move-by-idx across multiple outputs is unverified (single-output test).
  - Parked windows land floating when summoned; moved (never-parked) windows arrive tiled. Feels like lightweight-attach vs already-engaged split — evaluate in feel test.

Open: feel verdict on real desktop (`just switch`, then Mod+S / Mod+Shift+S), keybind ergonomics, picker row polish.
