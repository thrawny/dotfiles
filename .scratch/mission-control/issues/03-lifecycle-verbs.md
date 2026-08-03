# Lifecycle verbs for non-spatial threads

Type: grilling
Status: open

## Question

Re-derive the thread lifecycle now that threads aren't spatial. "Settle" was defined as *close the workspace* — that meaning is gone. Decide:

- The states (active / parked / archived? is read-unread a separate axis or fused into status, Codex-style: a running thread can never be unread?)
- The transitions, and which are automatic (PR merged → what, keyed on **ownership**: worktree branch == PR head branch, terminal state required)
- What each verb does to the zmx session and the worktree

Constraints carried from research: every verb reversible from its destination; ship the unarchive path before any auto-archive; verbs silent for high-frequency actions, undo toast only where the row disappears.

## Input from the attach prototype feel test (2026-08-03)

User's verb sketch after living with park/summon/go-to ([02](02-attach-mechanism.md)):

- **park** — good as-is: "I don't want to see you now", for when the agent will work a long time. Window hidden, thread stays in the picker.
- **settle** — the missing verb, wants building: "work has been done", keep the thread around but move it out of the picker's default view. Should also happen automatically after ~1–2 days of inactivity.
- **archive** — unsure if needed; mostly "forget this happened".

Prototype riding on the 02 scripts (mechanism: **nirius marks**, user's suggestion):

- `bin/thread-settle` (Mod+Ctrl+S) = park + nirius mark `settled`.
- Picker hides settled threads by default; `ctrl-s` inside fzf reveals them; summoning a settled thread clears the mark.
- Auto-settle is *derived at picker time* (no daemon): session idle and `state_updated` older than 36h ⇒ shown as settled. Known wrinkle: a summoned auto-settled thread stays classified settled until real agent activity bumps `state_updated` — the mark axis and the derived axis don't fully compose yet.
- Marks live in niriusd ⇒ compositor-session lifetime, same as the whole windows-as-threads prototype. The real registry must own the settled bit.

Still to grill: read-unread axis, transitions on PR merge/ownership, what each verb does to zmx session + worktree, whether archive exists at all.
