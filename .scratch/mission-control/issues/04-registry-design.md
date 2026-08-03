# Registry design

Type: grilling
Status: open
Blocked by: 01, 03

## Question

The registry is the core build — durable truth for threads. Decide:

- **Schema**: thread id, host, dir, branch, harness, zmx session name(s), lifecycle state, read-bit (mark-read-on-open, server-side style), PR association
- **Storage**: sqlite vs jsonl vs dir-of-files
- **Write model**: single-writer daemon vs library + lock
- **Cross-host** (if [01](01-v1-scope-cut.md) puts remote in scope): how EC2 thread state reaches the laptop — push-on-event over ssh, periodic pull, syncthing, or a central store

Constraint from research: **derive, don't reconcile** — one authoritative producer per fact, no second projection to sync. Remote status over SSH is the gap no product ships; this is the part worth getting right.
