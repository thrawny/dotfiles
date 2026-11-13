"""Track the worker sessions a driver session starts in Herdr.

The driver is a Claude session that hands each task to a worker: a Claude
session in its own Herdr tab, usually in its own worktree. This command is the
driver's toolbelt. It starts workers, lists them with their live Herdr state,
takes reports from workers, waits until a worker needs the driver, and cleans
up after a merge. A task blocked for a while can be snoozed: its worktree and
workspace go away, its branch stays, and wake brings them back on the same
Claude session, in a linked worktree at the old path and its own workspace.
Wake refuses rather than fall back to the main checkout: when the branch is
gone, when the main checkout has the branch checked out, or when the session
ran outside the worktree. Close removes a worktree only when the task's
checkout is a linked worktree. A task in a main checkout loses only its tab,
or only its pane when another task works in the same tab.
When the user resumes a worker's session in a new pane, moto attach moves the
task to that pane, so moto stops calling it gone. Claude's SessionStart hook
runs moto attach --hook, which records each worker's session id, including the
new one after /clear, and does that move by itself.

When the user closes a worker's pane by hand, the watch tells the driver once
the pane has stayed gone for PANE_GONE_GRACE, even while the user is talking
to the worker, and marks
the task closed_at. moto list shows the mark, a later attach clears it, and
close counts a pane that closed after the user's last turn in it as the user
being done with it.

The watch stays quiet about a turn end that is not the driver's business: the
user talking to a worker, a worker whose background shells still run, or a
turn it already reported. It logs each one as an absorb event instead. Each
moto watch is one pass, printed as JSON. The moto-watch Claude Code mod, which
moto focus loads into the driver, runs a pass every few seconds and prompts the
driver with the news. Notes that scheduled jobs left ride along.

The user ends a worker's work by running the moto-wrap skill in its pane, which
reports wrap, a done that also lists what still runs. The moto-snooze skill
parks a worker that waits on something: it reports snooze with what the task
waits on, and the driver runs moto snooze, since a worker that snoozes itself
closes its own pane mid-turn. Both hand the task to the driver at once, so the
driver hears of them even while the user is talking to the worker.

A worker is with the user while the user typed in its pane within the user
window, user_window_minutes in MOTO_HOME/settings.toml, 30 by default. The
window counts from the user's last prompt, not from the worker's last report.
Prompts from the driver, from the worker's parent and its children's reports,
and the /handoff, /takeoff and /compact commands moto submits are not the
user's typing. A wrap or snooze report and a wake end the window early. The
watch tells the driver once when a worker is with the user, and once when the
window has passed and the turn the user started has ended, with the worker's
latest state: its last report, or a turn that ended without one.

While a worker is with the user, moto watch skips its turn ends and its
question and blocked reports, which are the user's, and types nothing into its
pane: no handoff, no carry on, no /compact. The window never makes the worker
stop. Each new user prompt settles an open question or blocked report that came
before it, so the sidebar shows no question the user answered. Its done reaches the driver as if it had passed --to-driver,
because a done is when the driver updates tickets and notes. When the user asks
the worker to pass something else on, the worker runs moto report --to-driver.
A worker that another worker started uses the same flag to reach the driver
instead of its parent, and the user window does not apply to it.

The user also runs those skills in Claude sessions they started by hand, which
no task owns. A wrap or snooze from one adopts the session first: it
becomes a task built from its Herdr pane, its git checkout and its Claude
session id, logged as an adopt event, and the report lands as usual. moto made
none of that session's surroundings, so close and snooze close only its tab,
and remove its checkout only when it is a linked worktree that no other tab
works in.

moto list shows which workers are with the user, with the time since the
user's last prompt, and what happened since the last report in those and in
snoozed tasks, because the driver sees none of it: the user's turns in the worker's
pane, the user's new commits on its branch, and the last change to its PR.

moto afk records that the user is away, with their note word for word, and
moto back ends it with a brief of what happened meanwhile. moto stores and
shows the note but never reads it; the driver's own instructions decide what
it allows. moto log-action records what the driver did, for that brief.

Tasks live in $XDG_STATE_HOME/moto/tasks.json. herdr-decorator reads the same
file to show a worker's open question under its sidebar row.

Every command that changes a task also appends a line to events.jsonl in the
same folder, which nothing rewrites: a task's history outlives the task.
close and drop copy the whole task into their line before deleting it.
close refuses a worker that is mid-turn, that the user typed to since its last
report, or that is with the user, because a done report can be stale by then.
moto log prints those lines.

moto handoff moves a worker to a fresh session in the same pane. It checks that
the worker is idle, submits /handoff to its pane as typed, with no [driver] tag,
so the handoff mod runs it, then waits for the session start hook to record the
new session and for the takeoff turn to end. It logs a handoff event with both
session ids and the goal, and then sends the brief from stdin, tagged as moto
tell tags it. While a handoff runs, a marker on the task makes the watch absorb
the handoff turn and the takeoff turn, since neither needs the driver.

A worker that reaches a phase boundary, such as from grilling to implementing,
runs moto report phase with the next phase. moto decides then, from the context
size in the reporting session's transcript, and the reply says what to do.
Under handoff_tokens, or with the size unknown, the worker carries on in the
same turn and the watch types nothing. Over it, the worker ends its turn and the
watch starts moto handoff in the background. When the user is typing to the
worker, moto does not hand it off: the worker carries on and tells the user that
/handoff would start a fresh session. The driver gets one line either way, and a
handoff that fails leaves it a note. A worker that ends a turn
without a report over compact_tokens gets /compact, at most once per
COMPACT_GROWTH tokens of growth. Both limits live in MOTO_HOME/settings.toml.
A phase report from a worker another worker started goes to that worker.

moto link puts every moto skill in ~/.claude/skills as symlinks, outside Home
Manager: the generic ones from moto/skills in dotfiles, and the work ones from
skills/ in MOTO_HOME. A work skill replaces a generic one of the same name.

moto job runs work on a clock: a job file in MOTO_HOME/jobs names a time,
a cheap check, and whether the result wakes the driver or starts a worker.
Without a brief, the job follows the .md file of the same name beside it.
moto job loop is the scheduler, and its state is jobs.json beside tasks.json.

moto when waits once on a condition: a shell command the job loop runs every
so often, which fires when it exits 0. Its brief then goes to the driver, or
prompts the task --wake names, waking it first if it is snoozed, and the check
is gone. A check that errors several runs in a row tells the driver, and one
that has not passed by its expiry, a week by default, tells the driver it gave
up. Checks live in when.json beside jobs.json, never in MOTO_HOME. moto job
list shows them, moto job rm cancels one, and moto snooze --until-check parks
a task with the check that wakes it. For a task that waits on a pull request,
--until-pr (on snooze and on when) builds that check: it passes once the PR is
closed or merged, has a review decision, a review or comment newer than the
snooze, a conflict with its base, or a failed required CI check, and its output
says which. For a PR that something else merges once it is approved with CI
green, add --automerge: the check then ignores an approval, and counts only
reviews and comments from someone other than the PR's author. A merge ends it
quietly, with no wake: the check exits SETTLED_EXIT, and the job loop closes the
snoozed task as moto close does, or tells the driver if the close is refused.
To change what a snoozed task waits on, run moto snooze on it again with
--until-pr (and --automerge) or --until-check, and an optional new reason: it
cancels every check that would wake the task, adds the new one and updates the
reason, and the task stays snoozed. Nothing wakes, opens a pane or is sent, and
the session, worktree state and snooze record stay. The new check goes in first,
so one that errors or already passes leaves the old one running. moto when
--wake only adds a check.

A worker can start workers of its own, which the driver's watch leaves to it,
apart from what the user does in one: a wrap or snooze, or closing its
pane, which reach the driver as for any task. The watch carries a child's done,
question and blocked reports to its parent instead: it prompts the parent's
pane with each one, tagged as in [child done], once the parent is not mid-turn,
even while the user talks to the parent. A parent that is gone, snoozed or closed cannot take them, so the
driver gets them. moto tell and wake from a
worker's pane reach only the tasks it started, and tag the message with the
worker's name instead of [driver]. A worker that hands work off instead runs
moto spawn --to-driver: the task gets no parent, the driver watches it as its
own, and requested_by records the worker that asked for it.

fork-window starts a fork of a worker or the driver with MOTO_FORK set. A fork
is neither: the hooks skip it, and every command that changes a task or speaks
for the driver refuses to run in it.

A session that works inside MOTO_HOME takes a role, because MOTO_HOME's
CLAUDE.md cannot tell the driver from a worker there. A role is a Markdown file
in MOTO_HOME/roles. moto spawn --role starts a worker in MOTO_HOME, or a folder
in it, with MOTO_ROLE set in its tab, and the task keeps the role through snooze
and wake. moto focus starts the driver with MOTO_ROLE=driver. Claude's
SessionStart hook runs moto role --hook, which hands the session its role file
as context on every start, resume, clear and compact.

MOTO_ROLE lives in the tab's shell, so a driver restarted from a shell older
than its role has none. The hook then takes the driver role for a session in
MOTO_HOME that no task owns, the rule that records the driver's pane. spawn
and wake set MOTO_WORKER in a main-checkout tab, so a worker in MOTO_HOME
never passes for the driver before its task names its pane. Claude Code saves
hook context over 10,000 characters to a file and shows only a preview, so a
longer role file comes as an order to Read it in full.
"""
