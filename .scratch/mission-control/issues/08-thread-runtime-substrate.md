# Thread runtime: window-hosted vs zmx-backed

Type: prototype
Status: open

## Question

Where does a thread's runtime live? Spawned from ticket 03 (2026-08-03), where the old "zmx is the persistence layer" assumption was flagged as design fiction — nothing built uses zmx yet.

- **Window-hosted** (today's prototypes): agent process runs directly in the ghostty window. Park must *hide* windows (closing kills the agent). Warm persistence ends at compositor restart.
- **zmx-backed** (brainstorm): process lives in a zmx session; windows are disposable attachments (`zmx attach`). Park could close windows losslessly; full "thread is not spatial" model.

## What to validate empirically

- Does an interactive harness TUI (pi, claude, codex) inside zmx attach/detach/re-attach cleanly (rendering, scrollback, resize)?
- Does agent-switch's window-keyed session tracking survive the indirection (window id changes across attachments)?
- What actually survives a compositor restart / logout under each model?

## Constraint from ticket 03

The cold-resurrection path (recreate from registry manifest + harness resume after reboot) is required **regardless** of substrate — zmx only buys warm persistence. Evaluate zmx on that narrower value, not as the durability story.

Refinement from ticket 03 (2026-08-03): liveness is host-relative — remote threads via ssh+zmx survive a laptop reboot, so zmx is essentially mandatory for remote runtimes. The likely shape is per-host substrate (window-hosted locally, zmx-backed remotely) behind the same verb interface; validate zmx locally only if it earns its keep.

Feeds ticket 04 (registry manifest shape differs: window ids vs zmx session names).
