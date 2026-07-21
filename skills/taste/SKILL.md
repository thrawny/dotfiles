---
name: taste
description: Jonas's code taste — brief implementers with the quality bar, or judge a diff's shape and decide accept vs send back.
disable-model-invocation: true
---

# Taste

Bug review answers "does it work?" — this skill answers the question Jonas would ask next: **is this the code that should exist?** Apply it as their proxy: hold the line they would hold, in their absence.

Two ways in: **briefing** an implementer before the work, and **judging** the diff after. Both use the same lens.

## The lens

**End-state.** Judge the change against the code that should exist, not the path that produced it. Compatibility shims with no current caller, mode flags with one mode, an old path kept "just in case" — that is the history showing through. The remedy is deletion, and deletion is always in scope for the change that introduced them.

**One home.** Every rule, constant, and behavior has exactly one home; a rule with two homes drifts. The tripwire is a second definition: searching a symbol's name should surface one definition, and finding two demands investigation — the same rule twice gets consolidated, while a coincidental resemblance (two rules that merely look alike today) is warranted and stays. This holds at repo scale too: work extends the house mechanism — the task-runner recipe, the shared module, the established pattern — rather than growing a parallel one beside it.

**Kind before reuse.** Plumbing — auth, db access, config, API clients, logging — goes to its lib home from the first line, one caller or not: a `getAuthSession(ctx)` helper inlined in a page file is ugly design from the beginning, reuse or no reuse, because its home already exists conceptually. Feature-local helpers (a `formatPrice`, a small transform) may live beside their one caller until the one-home tripwire fires.

**Deep modules.** A feature presents a small export surface — one entry point where one will do — with the substance behind it, and is tested through that surface. Sharding one concern into many exported pieces turns every internal detail into a public commitment and forces readers to bounce between files; fewer surfaces are easier to reason about, for agents and humans alike.

**Earned abstraction.** Generality is earned by the second real use, never anticipated. A framework for one feature, an option with one caller, an interface with one implementation — each is scaffolding for a future that may never come, paid for now. Placement is not generality: filing plumbing in its lib at first write is correct, not speculative.

**Fail fast.** Errors propagate to the boundary that can actually decide — the route handler, the CLI entry, the job runner — and get handled once there. Defensive checks, partial error states, and fallback values exist only for a specific, named need; they are never the default posture. A `try/catch` that logs and continues is a massive footgun — it converts a crash into silent wrong behavior.

**Net health.** The touched area comes out no worse than it went in: no new duplication, no new dead code, comments only for constraints the code cannot show.

## Briefing

Before delegating implementation, put the bar in the brief so rework never happens:

- Scout the repo's house mechanisms — task runner, shared modules, the existing pattern for the thing being built — and name them in the brief as the required extension points.
- Translate the relevant lens lines into task-specific instructions: "delete the old handler rather than branching on a flag", "the validation rule lives in X — extend it there".

Complete when the brief names the extension points and the deletions the task implies.

## Judging

Walk the diff's **additions** — every new file, function, flag, and dependency either passes the lens or produces a finding. Correctness is out of scope here (bug review owns it); shape is the whole job.

Every finding names the smaller shape: which lines collapse, where the one home is, what gets deleted. "Could be cleaner" is not a finding — the concrete alternative is.

Verdict per finding:

- **Send back** when the remedy is deletion or consolidation within the files the change already touches — that is rework of this change, always in scope.
- **Record** when the remedy reaches beyond the change — pre-existing debt gets a note for a future change, not scope creep now.

Complete when every addition is accounted for and each finding carries its smaller shape and verdict.
