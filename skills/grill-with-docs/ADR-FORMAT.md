# Architecture decision records

Offer an ADR only when all three conditions hold:

1. **Hard to reverse** — changing it later has meaningful cost.
2. **Surprising without context** — a future maintainer would reasonably ask why.
3. **A real trade-off** — credible alternatives existed.

If a condition is missing, keep the decision in the conversation rather than inflating the ADR collection.

Follow the repository's existing location and format. Otherwise default to `docs/adr/NNNN-short-slug.md`. Scan the directory for the highest `NNNN-*.md` and increment it.

```md
# ADR NNNN: <Decision title>

## Status

Accepted

## Context

<Forces, constraints, and problem that made the decision necessary.>

## Decision

<Chosen direction.>

## Consequences

<Positive and negative consequences; what becomes easier or harder.>

## Alternatives considered

- <Alternative>: <why it was not chosen>
```

Get confirmation before creating the ADR unless the user has already clearly approved recording the decision.
