# Surface content: sidebar, waybar, jump bind

Type: grilling
Status: open

Reframed 2026-08-03 (surface pivot, see map): the picker is now a GTK layer-shell **sidebar** in agent-switch — Mod+S summons it, exclusive zone on the left, per-area content. Ticket 03 resolved the vocabulary (lifecycle, attention tiers, verbs); this ticket designs what the sidebar shows and how it behaves.

## Question

- **Sidebar interaction model**: toggled-only (Mod+S summon with exclusive keyboard, Esc dismiss, space reclaimed) vs always-visible dashboard option (keyboard on-demand; refocus-by-bind is the weak spot since niri focus actions target windows, not layer surfaces)
- **Sidebar rows**: what a row carries; ordering — attention tiers as sort key (Needs input > Unread > Working > Idle from 03), stable within tiers; settled threads behind a reveal (successor to fzf `ctrl-s`); tombstones view for unarchive
- **Per-workspace illusion**: content follows focused workspace via niri event stream; behavior on non-area workspaces (hide vs global view)
- **Waybar**: what remains — aggregate counts (`2 waiting · 3 running`, FleetView-style), per-state glyphs, or nothing (sidebar subsumes)
- **Jump-to-next-needing-me**: which Mod-bind, and what it does when nothing waits (research: cheapest high-value unclaimed primitive)

Constraints from research: the primary/glanceable surface never reorders on activity — ranking lives only in the summoned sidebar; dim the running, brighten the finished-unread; no numeric badges per row; attention transitions may jump the queue, attention states never; the currently-open thread is never hidden by a filter. Colorblind constraint (user): blue/orange + structure, never red/green pairs.

Open from the pivot discussion: is "rename" also an area verb (workspace naming)? Thread-rename landed in 03.
