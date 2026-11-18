# The moto model

moto runs tasks for one user. A driver session hands each task to a worker session. This file is the model that moto's code, skills and briefs follow. Every rule elsewhere either follows from it or is mechanism.

## 1. Who decides

- The user decides new tasks, new tickets, merges, and when a task ends.
- The driver picks each task's flow and model when it starts the task. The user can overrule it. The driver asks only when it is unsure.
- Otherwise the driver acts without asking only on bookkeeping that follows from clear evidence and can be undone. Examples: a ticket status, a label, closing a task whose PR merged, snoozing.
- A worker owns only the work in its brief.

## 2. Owners

Every task has exactly one owner at a time: the user, the driver, or the worker that started it. The same rules apply at every level.

- The user takes a task by typing in its pane. An answer to the worker's question counts too.
- The user gives the task back only on purpose: they name a flow, wrap it, snooze it, or say "back to the driver". There is no time limit.
- Messages from the driver, from a parent worker, and the commands moto types itself never take a task.

## 3. Reports

A report means "this task changed state, and its owner must act". The kinds are:

| Kind | Meaning |
|---|---|
| `done` | The deliverable is ready. Once per deliverable. |
| `question` | The worker needs an answer only the owner has. |
| `blocked` | The worker cannot go on. |
| `wrap` | The user ended the work. |
| `snooze` | The user parked the task until something happens. |

A revision in conversation with the user is not a report.

From a task it owns, the driver hears only these: done, question, blocked, wrap, snooze, a closed pane, and one stall signal. The stall signal is a turn that ended with no report and no background work, or a worker waiting at an approval prompt. Phase handoffs stay between the worker and moto.

While the user owns a task, the driver hears only a report sent with `--to-driver`, a wrap, a snooze and a closed pane.

## 4. Questions

While the user owns a task, the worker asks in its pane only. It sends no `question` report.

## 5. Flows

Every task has a flow. A flow sets what the worker may do without asking, and where it stops. The flow definitions live outside this repository. Research uses an "answer" flow, whose stop is the first answer.

When the user takes a task, its flow pauses. When the user names a flow, the worker gives the task back and runs that flow from where the work stands.

## 6. What ends a task

A task ends when its PR merged, the user wrapped it, or the user closed its pane. A `done` never ends a task.

## 7. Decisions made ahead of time

A scheduled job or an away note may start only what it names. Anything else it finds becomes a proposal for the user.

## 8. Changing moto

When something looks wrong, name the case first:

- (a) The code does not match the model. Fix the code.
- (b) The model is wrong or unclear. Change the model, which may delete rules.
- (c) A clear rule was ignored. Shorten the rule or move it. Never add a stronger copy.

The commit message names the case. Dates and incidents go in commit messages, never in rule text.

## Where the mechanism lives

moto adds nothing that Herdr already shows or does by itself.

- `moto --help`: commands, state files, and how the watch works.
- `skills/moto/SKILL.md`: the worker's side of each command.
- `moto doc-sizes`: warns when this file or another moto doc grows past its limit.
