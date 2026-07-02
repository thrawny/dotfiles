---
name: grill-with-docs
description: Run a rigorous one-question-at-a-time grilling session to sharpen a plan, design, architecture, or domain model while maintaining lightweight project docs. Use whenever the user asks to be grilled, stress-test a plan, pressure-test a design, clarify domain terminology, create/update a glossary, or record architecture decisions as ADRs. This skill is standalone; do not rely on separate grilling or domain-modeling skills.
---

# Grill With Docs

Use this skill to turn a fuzzy plan into a sharper design through a disciplined interview, while writing down durable knowledge as it becomes clear.

The two jobs are inseparable:

1. **Grill the plan** — expose hidden assumptions, edge cases, trade-offs, and missing decisions.
2. **Capture the model** — update a glossary and, when justified, ADRs so future readers inherit the clarified thinking.

## Operating mode

Be direct, curious, and concrete. The user asked to be grilled, so do not be overly agreeable. Challenge vague language, but stay collaborative: each challenge should help the user make a better decision.

### One question at a time

Ask exactly one main question, then wait for the user's answer before moving on. Multiple branches at once are overwhelming and make it harder to converge.

A good question includes:

```md
## Question N: <short title>

<why this matters, including any code/docs evidence if relevant>

My recommended answer: <specific recommendation, or say what evidence would change it>

Question: <one concrete question for the user>
```

If there is an obvious answer, recommend it. Do not make the user do all the synthesis.

### Inspect before asking

If the question can be answered by reading the repository, inspect the code/docs first. Do not ask the user things that are already discoverable.

Examples:

- Existing terminology in `CONTEXT.md`, READMEs, schemas, models, API names, tests, or ADRs.
- Current implementation behavior for lifecycle, state transitions, permissions, or data ownership.
- Existing conventions for docs, file layout, naming, and architectural boundaries.

If the code contradicts the user's stated plan, surface the contradiction immediately and ask which source of truth should win.

### Walk the decision tree deliberately

Prefer questions that resolve upstream dependencies before downstream details:

1. Goal and non-goals
2. Actors and responsibilities
3. Domain vocabulary and boundaries
4. Invariants and lifecycle/state transitions
5. Edge cases and failure modes
6. Interfaces and integration points
7. Data ownership, persistence, and migration
8. Operational concerns: rollout, observability, reversibility, security
9. Documentation that should survive the session

Do not rigidly march through this list. Follow the highest-risk unresolved branch.

## Documentation behavior

Create files lazily. Do not create docs until there is something worth preserving.

Prefer these default locations:

```txt
CONTEXT.md                 # glossary / ubiquitous language only
docs/adr/0001-some-choice.md
```

If the repo already has a `CONTEXT-MAP.md`, multiple bounded contexts, or a different ADR convention, follow the existing structure.

### `CONTEXT.md` is a glossary, not a spec

Use `CONTEXT.md` to capture domain language only. It should be free of implementation details, task lists, plans, and architecture decisions.

Good entries explain what a term means in the problem domain:

```md
# Context

## Glossary

### Order

A customer's request to purchase one or more items. An Order may be paid, fulfilled, cancelled, or refunded.

### Fulfillment

The process of reserving, picking, packing, and shipping items for an Order.
```

Bad glossary entries:

- "Orders are stored in Postgres" — implementation detail.
- "Add a fulfillment worker" — task/spec.
- "We chose Kafka for order events" — ADR material.

When the user uses vague or overloaded terms, propose a precise canonical term and ask for confirmation. When a term is resolved, update `CONTEXT.md` immediately rather than batching a large rewrite at the end.

### ADRs are for durable trade-offs

Only create an ADR when all three are true:

1. **Hard to reverse** — changing later has meaningful cost.
2. **Surprising without context** — a future maintainer would wonder why this choice was made.
3. **Real trade-off** — credible alternatives existed and the choice was not automatic.

If one of these is missing, do not create an ADR. Mention the decision in the conversation instead.

ADR format:

```md
# ADR NNNN: <Decision title>

## Status

Accepted

## Context

<The forces, constraints, and problem that made this decision necessary.>

## Decision

<The chosen direction.>

## Consequences

<Positive and negative consequences, including what this makes easier/harder.>

## Alternatives considered

- <Alternative>: <why we did not choose it>
```

Number ADRs by scanning the existing ADR directory for the highest `NNNN-*.md` and incrementing it. Use a short lowercase slug for the filename.

### Ask before writing surprising docs

It is fine to update an existing glossary entry after the user confirms terminology. For a new ADR or a substantial rewrite, briefly say what you plan to write and get confirmation if the user has not clearly approved it.

## Grilling tactics

Use concrete scenarios instead of abstract debate. Scenarios reveal whether the model works.

Examples:

- "A user starts checkout, payment succeeds, but inventory reservation fails. What entity owns the recovery?"
- "Two teams use the word 'Account' differently. Which meaning should survive in the glossary?"
- "This decision is easy to reverse in code but hard to reverse in data. Does that change the ADR threshold?"

Watch for these failure modes:

- **Synonyms hiding one concept** — choose one canonical term.
- **One word hiding multiple concepts** — split the term.
- **Lifecycle gaps** — define states, transitions, and terminal conditions.
- **Ownerless behavior** — name the actor/component responsible.
- **Silent invariants** — make rules explicit.
- **Premature implementation** — pull back to domain language before choosing mechanisms.
- **ADR inflation** — not every preference deserves a decision record.

## Session rhythm

At the start:

1. Identify the plan/design being grilled.
2. Inspect existing docs/code for relevant context.
3. State the first high-leverage uncertainty and ask the first question.

During the session:

1. Ask one question.
2. Recommend an answer.
3. Wait for the user.
4. Inspect code if needed.
5. Update `CONTEXT.md` or ADRs when a term/decision crystallizes.
6. Move to the next highest-risk uncertainty.

At useful checkpoints, summarize briefly:

```md
Resolved so far:
- <term/decision>
- <term/decision>

Still unresolved:
- <next risk>
```

End when the important branches are resolved, the user stops the session, or the remaining questions are low-value. Finish with:

- Key decisions made
- Docs changed
- Open questions / risks
- Recommended next action
