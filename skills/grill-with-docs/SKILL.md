---
name: grill-with-docs
description: Relentless one-question interview for stress-testing a plan while sharpening domain language and recording durable architectural decisions. Use when the user wants a plan grilled, domain terms clarified, or trade-offs captured as ADRs.
---

# Grill With Docs

Turn a fuzzy plan into a sharper design through a disciplined interview. Resolve the highest-risk uncertainty, then preserve domain language and durable decisions as they crystallize.

## 1. Inspect before asking

Identify the plan or design being grilled, then inspect relevant code and existing documentation. Look for `CONTEXT.md`, `CONTEXT-MAP.md`, ADRs, schemas, models, APIs, tests, and repository conventions.

Answer discoverable questions through legwork. Put decisions to the user. If the implementation contradicts the stated plan, surface the contradiction and ask which source should win.

This step is complete when the known facts are established and the first unresolved decision is identified.

## 2. Ask one question

Ask exactly one main question and wait for the answer. Recommend a specific answer whenever the evidence supports one.

```md
## Question N: <short title>

<why this matters, including code or documentation evidence>

My recommendation: <specific answer, or what evidence would decide it>

Question: <one concrete question>
```

Each question should resolve one decision rather than opening several new branches.

## 3. Follow the riskiest branch

Resolve upstream decisions before their dependants. Common branches include:

1. Goal and non-goals
2. Actors and responsibilities
3. Domain vocabulary and boundaries
4. Invariants and lifecycle transitions
5. Edge cases and failure modes
6. Interfaces and integrations
7. Data ownership and migration
8. Rollout, observability, reversibility, and security

Follow the highest-risk unresolved branch instead of marching through this list mechanically. Use concrete scenarios to expose lifecycle gaps, ownerless behavior, silent invariants, overloaded terms, and hidden trade-offs.

## 4. Capture what crystallizes

Create documentation lazily and follow existing repository conventions.

- When domain language is resolved, read [CONTEXT-FORMAT.md](CONTEXT-FORMAT.md) and update the appropriate glossary immediately.
- When a decision appears hard to reverse, surprising without context, and born from a real trade-off, read [ADR-FORMAT.md](ADR-FORMAT.md) and offer to record it.

State the intended documentation change before creating an ADR or substantially rewriting existing documentation.

## 5. Repeat to a terminal state

After each answer, capture any crystallized knowledge and ask the next highest-value question. At useful checkpoints, summarize:

```md
Resolved:
- <term or decision>

Unresolved:
- <next material risk>
```

The session is complete when the material branches are resolved, the user stops it, or the remaining questions would not change the design. Finish with:

- Key decisions
- Documentation changed
- Open risks
- Recommended next action
