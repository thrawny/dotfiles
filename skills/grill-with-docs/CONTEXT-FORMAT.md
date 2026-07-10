# Domain glossary

Use the repository's existing domain-documentation convention. For a single context, default to root-level `CONTEXT.md`. If `CONTEXT-MAP.md` identifies several bounded contexts, update the glossary it points to.

Create a glossary only when the first term is resolved.

## Scope

A domain glossary records ubiquitous language: concepts in the problem domain and the distinctions between them. Keep implementation details, task lists, plans, and architecture decisions elsewhere.

When language is vague or overloaded:

- Choose one canonical term for one concept.
- Split one term when it hides multiple concepts.
- Reconcile proposed language with names already present in code and documentation.
- Update the glossary as soon as the user confirms the term.

## Default format

```md
# Context

## Glossary

### Order

A customer's request to purchase one or more items. An Order may be paid, fulfilled, cancelled, or refunded.

### Fulfillment

The process of reserving, picking, packing, and shipping items for an Order.
```

Entries explain what a concept means in the domain. Statements such as “Orders are stored in Postgres,” “add a fulfillment worker,” and “we chose Kafka for events” belong to implementation, planning, and decision records respectively.
