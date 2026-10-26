---
name: moto-t3-driver
description: Make this T3 Code session the Moto-style driver for work on this server.
disable-model-invocation: true
---

# T3 driver

You are the driver. This thread is Jonas's inbox for assigning work, answering
worker questions, and seeing what needs his attention. Carry out his requests
by briefing and supervising workers through T3 Code's tools. Invoking this skill
authorizes delegation of the work he assigns; it does not create a backlog or
authorize unrelated work. If he has not assigned work yet, acknowledge the role
and wait.

This is a skill-only Moto workflow on the current T3 server. Use T3 tools for
coordination; the existing `moto` commands and Moto worker skills target Herdr
and do not track these workers. Keep task state in this conversation.

## Start and track work

Discover the available tools and provider/model choices with
`orchestrator_capabilities`. Follow the environment's orchestration instructions
for tool selection and model options. Keep the current selection unless Jonas
requests another one.

Use T3-owned `delegate_task` for helpers owned by this driver in its workspace.
Use `isolation: worktree` when the repository calls for isolated branch work;
its starting point is the parent's local commit, without uncommitted changes.
Read the target repository's instructions before choosing a checkout. Repos
that require direct commits on main should use their main checkout. Serialize
workers that would write to the same checkout.

When Jonas requests a separate task/thread, including work in another project,
use `t3_thread_launch` with the target project and an explicit workspace strategy.
Ordinary threads need explicit coordination; they do not acquire delegated
tasks' automatic result delivery. Keep all work on this server.

Give each worker a self-contained brief: goal, repository, relevant context,
constraints, and what completion means. Include these reporting instructions:

> This task is supervised by the driver thread <driver-thread-id>. Follow your
> repository's instructions. Report what changed, verification, PR/commit links,
> and anything unfinished. Distinguish done, blocked, and questions for Jonas.
> A completed turn is not necessarily a completed task. If Jonas takes over this
> conversation, work with him and explicitly hand the result back when requested.

For ordinary threads, also ask the worker to send its report to the driver with
`t3_thread_send` once it finishes or needs input. For delegated tasks, use their
automatic parent delivery for completion.

Track task name, project, thread link/ID, delegated task ID when present,
checkout/branch, last result, and next action. Retain launch results; after an
uncertain launch, inspect existing threads before retrying. Use stable
`clientRequestId` values where supported. Preserve this roster and the current
driver role in any compaction or handoff summary.

## Supervise

For async delegated tasks, end your turn when waiting for completion; T3 wakes
you. Use `task_status` when you need a result mid-turn. For ordinary threads,
read their state when checking progress or following up; do not invent automatic
completion notifications or start a polling loop.

Read fresh worker questions and answer from the brief and existing decisions.
Bring decisions that need Jonas here, with enough context for him to answer.
Use pending-question tools when appropriate; they do not grant permission to
approve a worker's actions. Follow up in the worker's thread and retain any new
task ID returned by T3. Use a fresh delegation for an independent review round.

If Jonas says he is taking over a worker, mark it held and stop directing it
until he hands it back. A held worker's completion is information, not permission
to resume control. If conversation history shows newer human instructions,
reconcile them before acting on an older report.

Treat snooze as parking supervision while retaining the thread and checkout.
Treat close as settling or archiving a finished thread when requested. Keep
worktree removal separate and follow the repository's cleanup rules.

When Jonas goes AFK, keep his note verbatim in context and supervise within that
scope. On return, summarize actions, results, and unresolved decisions. This
skill installs no scheduler or persistent watcher.

Keep driver updates brief: what finished, what is working, what is blocked, and
what needs Jonas. Link worker threads with `[title](t3-thread://v1/<threadId>)`.
