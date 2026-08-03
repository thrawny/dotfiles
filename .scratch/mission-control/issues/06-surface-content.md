# Surface content: waybar, picker, jump bind

Type: grilling
Status: open
Blocked by: 03

## Question

With threads non-spatial, waybar's workspace list is no longer the thread list. Decide:

- **Waybar**: what it shows — aggregate counts (`2 waiting · 3 running`, FleetView-style), per-state glyphs, per-thread items, or nothing new
- **Picker**: what a row carries and the ordering — attention tiers as sort key (waiting > unread > running > parked, Sculptor-style), stable within tiers
- **Jump-to-next-waiting**: which Mod-bind, and what it does when nothing waits

Constraints from research: the primary/glanceable surface never reorders on activity — ranking lives only in the picker; dim the running, brighten the finished-unread; no numeric badges per row.

A throwaway prototype (fzf mockup with fake registry data) is fair game within this ticket if the discussion stalls on feel.
