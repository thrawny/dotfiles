---
name: moto-snooze
description: Park a moto worker that waits on something, stop what it started, and report snooze to the driver.
argument-hint: "<what the task waits on>"
disable-model-invocation: true
---

# Snooze

The user runs this in a moto worker's pane when the task has to wait, for example on a review or on another team. Get the worker ready to park, then report `snooze` to the driver, which runs `moto snooze`. Never run `moto snooze` on yourself: it closes your own pane mid-turn.

1. **Know what the task waits on.** The user's argument says it:

   $ARGUMENTS

   If that is empty, ask the user. Done when you have it in one line.

2. **Stop what you started.** Your scope is what this session started: background shells, servers, Herdr tabs you opened for a stack, and workers you spawned with `moto spawn` (`moto list` shows them as "started by" you). Stop each one, and close spawned workers with `moto close <agent>`. Keep running only what the user asks to keep, and note why for each. Done when everything you stopped has exited and everything still running is on that keep list.

3. **Leave a clean tree.** `moto snooze` refuses a worktree with uncommitted changes, so check `git status`. For uncommitted changes, ask the user whether to commit them (and push, if they say so) or throw them away, and do what they choose. Discard work only on the user's explicit word. Done when `git status` shows a clean tree.

4. **Report.** End with `moto report snooze "<what it waits on>"`. Add the PR URL if there is one, and anything you left running and why.
