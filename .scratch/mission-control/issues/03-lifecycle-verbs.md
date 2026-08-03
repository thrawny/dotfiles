# Lifecycle verbs for non-spatial threads

Type: grilling
Status: open

## Question

Re-derive the thread lifecycle now that threads aren't spatial. "Settle" was defined as *close the workspace* — that meaning is gone. Decide:

- The states (active / parked / archived? is read-unread a separate axis or fused into status, Codex-style: a running thread can never be unread?)
- The transitions, and which are automatic (PR merged → what, keyed on **ownership**: worktree branch == PR head branch, terminal state required)
- What each verb does to the zmx session and the worktree

Constraints carried from research: every verb reversible from its destination; ship the unarchive path before any auto-archive; verbs silent for high-frequency actions, undo toast only where the row disappears.
