---
name: moto-wrap
description: End a session's work, stop what it started, and report wrap to the driver. For a moto worker or a session the user started by hand.
disable-model-invocation: true
---

# Wrap

The user runs this in a session whose work is over: a moto worker, or a session they started by hand, which `moto report` makes a task so the driver can clean up after it. Close out the work in order, then report `wrap` to the driver. Leave the task's tickets as they are: the driver updates them.

1. **Check the agreed work is finished.** Compare what you did against your brief, if the driver gave you one, and against everything you agreed with the user. If any of it is unfinished, stop and ask the user how to proceed, then start again from this step. Done when every agreed item is finished or the user has said what to do with it.

2. **Stop what you started.** Your scope is what this session started: background shells, servers, Herdr tabs you opened for a stack, and workers you spawned with `moto spawn` (`moto list` shows them as "started by" you). Stop each one, and close spawned workers with `moto close <agent>`. Leave tasks you handed off with `moto spawn --to-driver` (shown as "requested by" you) running, since the driver watches and closes them. Keep running only what the user asks to keep, and note why for each. Done when everything you stopped has exited and everything still running is on that keep list.

3. **Settle unsaved work.** Look for uncommitted changes (`git status`) and for commits on no remote (`git log --oneline HEAD --not --remotes`). Commits in a merged PR count as saved: `gh pr view --json state,headRefOid` shows `MERGED` with your `HEAD`. For anything unsaved, ask the user whether to commit it (and push, if they say so), keep it as it is, or throw it away, and do what they choose. Discard work only on the user's explicit word. Done when nothing is unsaved or the user has chosen for every piece.

4. **Report.** End with `moto report wrap "<summary>"`. The summary covers what got done, the PR URL if there is one, what still runs and why, and anything left over, such as unsaved work the user kept or a follow-up.
