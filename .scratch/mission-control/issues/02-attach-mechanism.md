# Attach mechanism

Type: prototype
Status: resolved

## Answer (2026-08-03, decided by feel on the real desktop)

The attach verb set is **park / summon / go-to**, implemented on nirius scratchpad + raw niri IPC, keyed by window id via agent-switch's session store:

- **Park** (Mod+Shift+S, `bin/thread-dismiss`): one keystroke, window floats into the nirius scratchpad (bottom-most workspace). Verdict: good — "I don't want to see you now", for long-running work.
- **Summon** (picker, `bin/thread-summon` on Mod+S): only *parked* threads are summoned to the current workspace; they arrive **tiled** (tiling also evicts nirius scratchpad membership, which fixes niriusd dragging summoned windows around).
- **Go-to**: threads *visible* in another workspace are visited, not pulled — this walked back the charted "summon-to-me only" premise; pulling an already-placed window felt wrong. Summon-to-me survives only as the exit from the parked state.
- Window↔thread identification was already solved: agent-switch keys sessions by niri window id (hooks). No env handshake needed; titles are display-only (shells/agents rewrite them).
- Verdict on the fzf surface: workable after the readability pass (aligned columns, state-sorted, sized floating window), but probably not the end state — if the picker needs live state or richer rows, build it into agent-switch as a GTK overlay.
- Feel-testing also surfaced the missing **settle** state ("work has been done, keep the thread around, out of sight") — recorded in [03 — Lifecycle verbs](03-lifecycle-verbs.md); a mark-based settle prototype rides along in the same scripts.

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
- Selection semantics (revised by feel on the real desktop, 2026-08-03): **parked → summon here; visible → go to it.** The first live session walked back "summon-to-me only" for visible windows — pulling a window that is already placed in another area felt wrong; `focus-window` jumps there instead. Summon-to-me survives only as the transition out of the parked state.
- Summoned threads arrive **tiled**, not floating (feel feedback): `scratchpad-show --id` then `move-window-to-tiling --id`.
- **Tiling doubles as un-adopt**: niriusd evicts a window from the scratchpad member list when it is tiled. This also fixes a real bug found by feel: a summoned window left as a scratchpad member gets dragged along by niriusd whenever the bottom-most workspace changes (e.g. when visiting the scratch workspace).
- Picker rows (round 2, after "mostly chaos" feedback): fixed-width aligned columns `PROJECT AGENT STATE WHERE TITLE(dim)` + header, sorted waiting → responding → idle, state colored orange/blue, `--nth` scoped so the hidden window id is not searchable, floating window sized 1250x480 via rule.
- Observations for the blueprint:
  - nirius's scratch state is the *bottom-most workspace*, not true invisibility — parked windows are reachable by scrolling down. Same mental model as Mod+Q workspace-scratchpad; acceptable, but "spatial absence at rest" is approximate.
  - The bottom-most workspace is recomputed as workspaces appear/close, so scratch membership must be tracked by nirius state (`list-scratchpad`), never by workspace position.
  - Shell prompts / agents rewrite window titles; titles are display-only, identity must stay window-id keyed.
  - fzf verdict: readable after round 2, but if more surface is wanted (live state refresh, richer rows), the fallback is building the picker into agent-switch as a GTK overlay.

Open: continued feel test on real desktop (`just switch`, then Mod+S / Mod+Shift+S), keybind ergonomics.
