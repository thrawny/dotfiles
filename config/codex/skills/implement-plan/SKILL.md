---
name: implement-plan
description: Implement an approved plan from `docs/plans/` phase by phase and keep the plan file up to date. Use when the user says `/implement-plan`, asks to execute a written plan, or wants planned work implemented with verification and checkbox updates.
---

# implement-plan

Execute an approved plan from `docs/plans/` and keep the plan document accurate.

## Workflow

1. Resolve the requested plan path. If the user gives only a filename, look under `docs/plans/`.
2. Read the entire plan before changing code.
3. Read every referenced file completely before implementation.
4. If the user specifies a phase number, implement only that phase. Otherwise continue from the first unchecked work.
5. Trust existing checkmarks unless the repository clearly contradicts them.
6. Implement phase by phase. Finish one phase before moving to the next.
7. Run the plan's verification steps after each phase.
8. Update completed checkboxes directly in the plan file.
9. Keep a brief running summary of what changed.

## Mismatch handling

If the repository no longer matches the plan, stop and present the mismatch clearly:

```text
Issue in Phase [N]
Expected (from plan): ...
Found (in code): ...
Why this matters: ...

Question: Should I [option A] or [option B]?
```

## Guardrails

- Read referenced files fully before editing.
- Keep changes consistent with repository patterns.
- Do not paper over plan-vs-code drift.
- Use the plan's own success criteria rather than inventing unrelated checks.
