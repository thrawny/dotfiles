# Mission control for agent threads — map

Label: wayfinder:map

## Destination

Every design decision for "glue v1" mission control is resolved and captured in a blueprint-tier spec (`lab/mission-control.blueprint.md`) ready to hand to build sessions: registry schema, status producers, attach verb, surfaces (waybar / picker / jump bind), and lifecycle verbs.

## Notes

- Charted premises (decided during charting, 2026-08-03):
  - **Threads are not spatial.** A thread's identity is its registry entry + zmx session; niri stays stock and just displays windows. Workspace-per-thread rejected (a 20-minute maintenance thread must not cost a workspace). Refined 2026-08-03: workspaces remain meaningful as *areas of work* (the niri-project role) that threads visit while engaged; a thread at rest has zero windows.
  - **Attach model: lightweight attach by default + explicit "pin to workspace" for heavy engagements.** Exact mechanism deliberately left open → [02 — Attach mechanism](issues/02-attach-mechanism.md).
  - **Build the glue.** Custom Wayland compositor is the fallback, not the plan. t3code rejected as platform (no pi support; its chat UI replaces the terminal workflow) — may be played with for ideas.
- Read first: memory note `project_thread_environment_design.md` (design pillars + full sidebar/landscape research: stable-list/ranked-palette, read-unread primitive, derive-don't-reconcile, archive-on-merge rules).
- Skills: `/grilling` + `/domain-modeling` for grilling tickets, `/prototype` for 02 and 06, `/research` for research tickets, `/blueprint` for the final artifact.
- Preferences: subagents default to Opus 5, never Fable. pi is the primary harness; terminal-focused workflow (ghostty, nvim/hunk, zmx). Kanel work code stays inside kanel infra.

## Decisions so far

<!-- one line per closed ticket: gist + link -->

- [v1 scope cut](issues/01-v1-scope-cut.md) — local implementation with remote-shaped schema (host field day one, sync deferred to v2); harnesses pi + claude + codex (codex conditional met by research).
- [Codex status surface](issues/05-codex-status-surface.md) — build the codex producer on its hooks engine (11 events, headless-capable, 3 already wired in this repo); no status file exists; liveness via `$PPID` from SessionStart + `kill -0`; watch for content-hashed hook-trust invalidation.
- [Attach mechanism](issues/02-attach-mechanism.md) — verbs are park / summon / go-to on nirius scratchpad + niri IPC, window-id keyed via agent-switch; "summon-to-me only" softened: visible threads are visited, only parked threads summoned (arriving tiled); fzf picker workable but likely not final (GTK-in-agent-switch is the fallback); missing "settle" state fed into 03.

## Not yet specified

- Thread creation flow (picker → project / harness / host / worktree-vs-stable-checkout; tenancy via path convention) — sharpens after scope cut + registry design.
- Worktree GC / archive automation details — after lifecycle verbs.
- Hand-raise + ntfy phone approval — likely remote-phase; after scope cut.
- Transcript sync / cross-machine resume — after scope cut + registry design.
- Custom-compositor fallback criteria — what failure of the glue would trigger reconsidering it.
- t3code playtime notes — optional, off-route; anything stolen lands in Decisions via the ticket that uses it.

## Out of scope

- Adopting t3code as the platform — ruled out during charting (pi unsupported; chat UI replaces terminal workflow).
- Port-collision handling for concurrent dev stacks — deferred in the original design discussion, stays deferred.
- Building any web/desktop app surface — v1 surfaces are waybar, picker, and terminals only.
