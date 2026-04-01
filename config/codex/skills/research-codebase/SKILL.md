---
name: research-codebase
description: Research the current repository and write a self-contained report under `docs/research/` with concrete file references. Use when the user says `/research-codebase`, asks a codebase question that deserves a written artifact, or wants structured investigation rather than an ephemeral answer.
---

# research-codebase

Investigate the repository and write a durable research document.

## Workflow

1. Treat the user's question as the research topic.
2. Read every referenced file fully before searching more broadly.
3. Break the question into concrete code paths, components, and patterns to inspect.
4. Search the codebase directly and read the most relevant files completely.
5. Prefer live code over docs; use docs only as supplementary history.
6. Synthesize findings with explicit file paths and line references.
7. Write the result to `docs/research/YYYY-MM-DD_HH-MM-SS_<topic>.md`.
8. Share the document path and a concise answer summary.

## Document structure

Use this default structure:

```markdown
---
date: [ISO8601 with timezone]
researcher: [name]
git_commit: [commit hash]
branch: [branch]
repository: [repo name]
topic: "[research topic]"
tags: [research, codebase]
status: complete
last_updated: [YYYY-MM-DD]
last_updated_by: [name]
---

# Research: [topic]

## Research Question

## Summary

## Detailed Findings

## Code References

## Architecture Insights

## Open Questions
```

## Guardrails

- Always cite concrete repository paths.
- Keep the document self-contained enough that a later reader can start from it.
- Append follow-up research to the same document when continuing an existing investigation.
