# Lifecycle verbs for non-spatial threads

Type: grilling
Status: resolved

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

## Answer (grilled 2026-08-03, confirmed)

Full vocabulary lives in `../CONTEXT.md`. The model:

**Three axes, two derived:**

1. **Visibility** (derived from compositor/host facts, never stored): summoned / parked. Park and summon are spatial verbs; "park as a lifecycle state" was an artifact of the fzf prototype.
2. **Lifecycle** (stored in registry): live → settled → archived (tombstone).
3. **Attention** (derived, fused Codex-style): Needs input > Unread > Working > Idle, from hook-authored status + one stored `last_read_at` (advances on summon/peek, never on list viewing). A working thread can never be unread.

**Verb contracts** (substrate-independent — the zmx-vs-window question was flagged as unvalidated design fiction and spun out to [08](08-thread-runtime-substrate.md)):

- **park** — hide windows. Destroys nothing.
- **summon** — bring the thread here: show windows if the runtime is warm, resurrect from the registry manifest + harness resume if cold. Clears settled, marks read. Resurrection is always lazy (through summon), never bulk-at-boot. Liveness is host-relative: remote ssh+zmx runtimes survive a laptop reboot.
- **settle** — registry bit + hide. Promises **recoverability, not warmth**: worktree/registry/conversation kept, runtime may be cooled later by an internal reaper. Destruction gradient: park (nothing) → settle (warmth may lapse) → archive (state reclaimed).
- **archive** — terminate runtime, reclaim worktree (refcount + confirm on the one one-way door), tombstone with transcript pointer + branch ref. Exists because settle keeps resources alive forever — archive is the reclaim verb. **Manual-only in v1; unarchive ships before any automation**; the future automation is merge-removes-confirmation (ownership-keyed: worktree branch == PR head, terminal state required), never merge-triggers-archive.
- **rename** — registry title edit, no lifecycle interaction, available on settled threads and tombstones. Area rename out of scope here.

**Transitions:**

- **Auto-settle**: daemon-written stored transition (not picker-time derivation — that's what caused the 02 wrinkle, now dissolved). Condition: runtime idle or dead AND no attention (unread/needs-input always block) AND 36h quiet. Silent, reversible from the settled view.
- **Un-settle**: exactly two triggers — summon (engagement) and agent hand-raise. Symmetry rule: attention-worthy events un-settle; attention-free time settles; viewing is neither.
- **Reboot**: registry + harness resume is the only durability layer (zmx is processes too). Nothing auto-spawns; threads show live-with-dead-runtime and resurrect on summon.

**Flows into 04 (registry)**: resume manifest (harness, harness session id, cwd, host, area, title), `last_read_at`, settled bit, tombstones. Everything else derived — no stored visibility, no stored liveness, no stored attention.
