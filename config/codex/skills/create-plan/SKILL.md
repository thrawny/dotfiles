---
name: create-plan
description: Create a detailed implementation plan grounded in the live codebase and save it under `docs/plans/`. Use when the user asks for a plan, says `/create-plan`, wants phased implementation guidance, or needs concrete automated and manual success criteria before coding.
---

# create-plan

Create an actionable implementation plan that matches the actual repository state.

## Workflow

1. Treat the user's topic, filename, or ticket path as the plan input.
2. Read every referenced file completely before planning.
3. Explore the codebase directly to verify assumptions and find the relevant components.
4. Identify constraints, acceptance criteria, and unknowns from the repo and user context.
5. Ask only the questions that cannot be answered from the code.
6. If scope or ordering is ambiguous, share a short phase outline and confirm the direction before writing the full plan.
7. Write the plan to `docs/plans/<descriptive-name>.md`.
8. Use concrete file paths and code references whenever possible.
9. Separate automated verification from manual verification.
10. Present the plan path and a concise summary, then refine it if the user asks.

## Required sections

Include these sections unless the task is genuinely too small to justify one:

- `Overview`
- `Current State Analysis`
- `Desired End State`
- `Key Discoveries`
- `What We're NOT Doing`
- `Implementation Approach`
- Phase sections with concrete changes
- `Testing Strategy`
- `Performance Considerations` when relevant
- `Migration Notes` when relevant
- `References`

## Plan shape

Use this as the default structure and adapt only when the repository demands it:

```markdown
# [Feature/Task Name] Implementation Plan

## Overview

## Current State Analysis

## Desired End State

### Key Discoveries
- [Finding with file reference]

## What We're NOT Doing

## Implementation Approach

## Phase 1: [Name]

### Overview

### Changes Required
- **File**: `path/to/file`
- **Changes**: [Concrete edits]

### Success Criteria

#### Automated Verification
- [ ] [Command]

#### Manual Verification
- [ ] [Manual check]

## Testing Strategy

## References
```

## Guardrails

- Ground the plan in the real codebase, not assumptions.
- Read mentioned files fully before citing them.
- Keep out-of-scope work explicit.
- Prefer plans that another engineer could execute without re-discovering context.
