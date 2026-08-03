# Mission control — ubiquitous language

Glossary for the thread/mission-control domain. Terms are added as they are resolved (wayfinder tickets, grilling sessions). Vocabulary only — no implementation.

## Terms

**Thread** — a unit of agent work: registry entry + zmx session (+ optionally a worktree). Not spatial; a thread at rest has zero windows.

**Area** — a niri workspace understood as a domain of work (e.g. "kanel"). Threads belong to an area; threads visit the area's workspace while engaged. (Name provisional — user: "project / area / domain, name tbd".)

**Visibility** *(derived axis — never stored)* — whether a thread currently has windows on some workspace. Values: **summoned** (windows present) / **parked** (no windows). Derived from compositor facts; park/summon are spatial verbs that only touch windows and never write registry state. (Decided in ticket 03, 2026-08-03: "park" as a lifecycle state was an artifact of the fzf prototype.)

**Lifecycle** *(stored axis — registry-owned)* — the thread's position in its life: **live** → **settled** → (archived — existence under grilling). Settle/archive/unsettle are registry verbs, orthogonal to visibility.

**park** — spatial verb: hide the thread's windows ("I don't want to see you now"). The thread stays live.

**summon** — spatial verb: materialize the thread's windows here. Runtime alive → bring/show windows; runtime dead → resurrect (recreate from the registry manifest + harness resume). Also clears settled (summoning is an act of engagement).

**Resurrection** — recreating a thread's runtime from its registry manifest (spawn terminal, cd to manifest cwd, harness resume). Always lazy — happens through summon, never in bulk at boot. Resumed ≠ identical: conversation restored, scrollback and in-flight state gone.

**settle** — lifecycle verb: mark work as done-for-now; thread leaves the default list but remains fully recoverable. Settle promises **recoverability, not warmth**: worktree, registry row, and conversation are kept; the runtime may go cold. The destruction gradient: park destroys nothing → settle may let warmth lapse, keeps all state → archive reclaims state, leaves a tombstone.

**Reaper** — internal action (not a user verb) that may terminate the runtime of a long-settled thread, relying on resurrection for the way back. Invisible: summon behaves identically on warm and reaped threads.

**Auto-settle** — daemon-written transition into settled when all hold: runtime idle or dead, no unread activity, no needs-input, quiet for 36h. Attention always blocks auto-settle. Silent, reversible from the settled view.

**Un-settle** — leaving settled. Exactly two triggers: summon (engagement) and agent hand-raise (any attention-worthy event). Symmetry rule: attention-worthy events un-settle; attention-free time settles. Viewing the settled list is neither.

**Attention** *(derived axis — fused, Codex-style)* — one value per thread, priority-ordered: **Needs input** (agent waiting on permission/answer) > **Unread** (activity since `last_read_at` AND not currently working) > **Working** (running; never unread by definition) > **Idle** (read and quiet). "Attention-worthy" means Needs input or Unread — these block auto-settle and trigger un-settle.

**Read marker** — the single stored `last_read_at` per thread. Advances on summon or opening the thread's detail; viewing a list never advances it. A working thread cannot be unread; only finished work demands reading.

**Runtime** — the living processes of a thread (agent + shell), wherever they are hosted (today: inside the thread's windows; possibly a zmx session later). Liveness is derived, never stored, and is **relative to the runtime's host**: a laptop reboot kills local runtimes only; a remote thread's ssh+zmx runtime survives it.

**archive** — lifecycle verb, defined by contract independent of runtime substrate: terminate the runtime, reclaim the worktree (refcount + confirm), tombstone the registry row. Transcript pointer and branch ref survive.

**Tombstone** — the registry remnant of an archived thread: identity, transcript pointer, branch ref. Enough to unarchive.

**unarchive** — restore a tombstoned thread to live: registry entry back, worktree re-creatable from the branch; honest that the old processes don't return.
