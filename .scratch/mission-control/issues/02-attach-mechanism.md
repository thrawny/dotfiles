# Attach mechanism

Type: prototype
Status: open

## Question

What is the default attach verb, concretely? Build throwaway prototypes in ghostty + niri and decide by feel.

Scoping refined 2026-08-03 (discussion before build):

- **Model refinement**: workspaces are *areas of work* (projects — the niri-project role) that threads visit; threads stay non-spatial. The enemy is the ever-expanding strip of session terminals per workspace.
- **Prototype step 1 — summon existing windows**: picker over `niri msg windows` (windows with running agent sessions), selection summons the thread. Pure niri IPC, works against today's real sessions, no zmx dependency. Expose BOTH sub-verbs on different keys to decide by feel: Enter = pull window to current workspace, Shift-Enter = go to the window where it lives (likely the light-thread vs heavy/pinned-thread split).
- **End-state constraint the prototype must not violate by design**: summon = move-existing-or-spawn-attached; dismiss = window closes, zmx session lives on headless. A thread at rest has zero windows — otherwise the strip just relocates to an attic workspace. Prototype step 1 can't implement dismiss (current sessions aren't zmx-backed); that's a known gap, not a design choice.
- **Dismiss ergonomics**: one keystroke from inside the summoned thread, or windows accumulate (research: parking verbs must be instant + reversible or users hoard).
- Candidate variants for step 2 (zmx-backed): window summon (spawn-or-move) vs picker-becomes-viewport (the floating picker window execs into `zmx attach`, retitles, un-floats — zero churn) vs in-place-from-shell CLI (free, ~5 lines, ships regardless).
- Window↔thread identification: env handshake + window title (needed for move-or-spawn dedup).
