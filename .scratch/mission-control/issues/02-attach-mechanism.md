# Attach mechanism

Type: prototype
Status: open

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
