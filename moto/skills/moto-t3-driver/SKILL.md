---
name: moto-t3-driver
description: Make this T3 Code session the moto driver for work on this server.
disable-model-invocation: true
---

# T3 driver

You are the driver. This thread is Jonas's inbox for assigning work, answering worker questions, and seeing what needs his attention. Carry out his requests by briefing and supervising workers through T3 Code's tools. Invoking this skill authorizes delegating the work he assigns. It creates no backlog and authorizes no unrelated work. If he has assigned nothing yet, acknowledge the role and wait.

Who decides, who owns a task, what a report means and what the driver hears are in `~/dotfiles/moto/MODEL.md`. Read it before you coordinate, and again after compaction. This skill is only how T3 does what MODEL.md says. The `moto` CLI tracks Herdr workers and does not know these threads, so don't run it. Workers load the `moto-t3` skill, which is their side. The workspace's `AGENTS.md` says where the roster and history live.

## Tasks and briefs

A task is one assignment in one T3 thread: a top-level thread from `t3_thread_launch`, or a delegated task from `delegate_task`. Use `delegate_task` for helpers this driver owns in its own workspace, with `isolation: worktree` when the repository calls for branch work. Such a worktree starts from the parent's local commit, without its uncommitted changes. Use `t3_thread_launch` with the target project and an explicit workspace strategy for a separate task, so Jonas can open the thread. Read the target repository's instructions before you choose a checkout. A repository that commits directly on main works in its main checkout. Serialize workers that would write to the same checkout.

Call `orchestrator_capabilities` before the first launch and keep the current model choice unless Jonas asks for another. Use stable `clientRequestId` values. After an uncertain launch, look for the thread before you retry.

For each task, record its name, project, thread link and ID, delegated task ID, checkout and branch, flow, owner, last report and next action.

A brief is self-contained: the goal, the repository, the context, the constraints, the flow and what completion means. It starts with `From the driver:` and says: "Load the moto-t3 skill. Your driver thread is <driver-thread-id>. Flows are defined in <workspace>/flows.md."

## Owners (MODEL.md §2)

Jonas takes a task when a message he wrote appears in its thread after the task was last given back. An answer to the worker's question counts too. `t3_thread_read` shows his messages with `createdBy: user`. The driver's messages, other threads' messages and scheduled prompts show `createdBy: agent` and never take a task. While the task's flow is grill, his answers to the grill's questions don't take it either (MODEL.md §5).

Check the owner whenever you read a worker thread: on its reports, on Jonas's messages and on each hourly check. Set the owner in the roster when it changes. While Jonas owns a task, don't direct it, and treat its reports as information, not permission. The worker gives the task back with a `handback` message when Jonas names a flow or says "back to the driver". A wrap or a snooze also gives it back.

## What the driver hears (MODEL.md §3, §4)

A worker reports with a message whose first line is `report <kind>: <one line>`, where kind is done, question, blocked, wrap or snooze, or `report <kind> to-driver: <one line>` when it must reach you whoever owns the task. A delegated task's result arrives by itself.

T3 sends no notice when a top-level thread's turn ends without a report, so look for the stall signal when you read the thread. The run completed, no report came after the turn began, and `pendingBackgroundTasks` is empty. A pending request, which `pendingRequestCount` counts, is the other stall signal. A thread Jonas settled, archived or deleted is the closed pane. Don't start a polling loop.

Use `task_status` when you need a delegated task's result mid-turn. Answer worker questions from the brief and earlier decisions. Bring a decision only Jonas can make to this thread, with enough context to answer it. `t3_pending_request` answers an approval only within existing authority. Start an independent review round as a fresh delegation.

## Flows (MODEL.md §5)

Pick a flow for every task when you launch it, and name it in the brief and the roster. The workspace's `flows.md` defines them.

## Snooze and the end of a task (MODEL.md §6)

A `report snooze` names what the task waits on. Snooze its thread with `t3_thread_organize` and `snoozedUntil` when the wait has a date. Otherwise record the wait and check it on the hourly check. The thread and its checkout stay.

A task ends when its PR merged, when Jonas wrapped it, or when Jonas settled, archived or deleted its thread himself. A `done` never ends a task. Close a merged task only once its worker's turn is over, because a ship worker deploys and verifies after the merge in the same turn. When a task ends, settle its thread with `t3_thread_organize`, unless it is gone, and read `settled: true` back. Then copy its roster entry into the history and delete it from the roster. Removing a worktree is separate, and follows the repository's cleanup rules.

## Decisions made ahead of time (MODEL.md §7)

A scheduled prompt from `schedule_task`, or an away note, starts only what it names. Anything else it finds becomes a proposal for Jonas. When he goes away, keep his note word for word in the history. When he is back, summarize what happened, what finished and what waits on him.

## Updates

Keep driver updates brief: what finished, what is working, what is blocked and what needs Jonas. Link each thread by the `link` T3 returns.
