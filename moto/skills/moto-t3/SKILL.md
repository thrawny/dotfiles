---
name: moto-t3
description: How a worker in a T3 Code thread reports to the T3 driver and hands work back. Load when a brief from the driver names this skill.
---

# moto for T3 workers

The T3 driver started this thread, and its brief names the driver thread. Who decides, who owns a task and what a report means are in `~/dotfiles/moto/MODEL.md`. Read it once. This skill is only how a T3 thread does what it says. The `moto` CLI tracks Herdr workers and does not know this thread, so don't run it.

## Report

End a turn with a report when the task changed state and its owner must act. Send it to the driver thread with `t3_thread_send`. Its first line is `report <kind>: <one line>`, where kind is done, question or blocked. Put the PR URL in a done line. Later lines may add what changed, how you verified it, and what is unfinished.

- Use `report <kind> to-driver: <one line>` when the report must reach the driver whoever owns the task: when it asks the driver to act, such as creating a ticket, and when Jonas asks you to pass something on.
- `wrap` and `snooze` belong to the moto-wrap and moto-snooze skills. Use those skills, not a bare report.
- A delegated task's result reaches the driver by itself. Send no report there.

The driver reads a turn that ends with no report and no background work as a stall. Run reviews, CI waits and deploy waits in the foreground with long, bounded timeouts, and don't end the turn while you wait. T3 doesn't resume a thread when a background task finishes.

## Jonas owns the task

The driver's messages start with `From the driver:`. Messages from other threads, a delegated helper's result, T3's own notices and scheduled prompts are not Jonas either. Any other message in this thread is Jonas typing, and he now owns the task, also when it answers your question. The exception is a grill flow: his answers to its questions do not take the task, pause the flow or need a "Flow paused" line, and your done from the grill ends that. Until he gives the task back:

- Answer and ask in this thread. Send no question or blocked report.
- A done reaches nobody, so don't send one. Report only with `to-driver`, or through moto-wrap or moto-snooze.
- If a flow your brief names still runs, it pauses. Add one line to your first reply: Flow paused. Name the flow to resume. If no flow runs, never mention a flow or a pause.

When Jonas names a flow or says "back to the driver", send the driver `handback <flow>: <where the work stands>`, with the flow he named, or the brief's flow when he named none. Then run that flow from where the work stands. After the hand-back, your reports reach the driver again.

## Flows

Your brief names the flow and the `flows.md` file that defines each one.

## Helpers

Start a helper you supervise with `delegate_task`, as the environment's orchestration instructions say. Its result comes back to you, and you cancel it with `task_cancel`. Leave a separate task to the driver: send a `to-driver` report that asks for it, instead of launching a top-level thread yourself.
