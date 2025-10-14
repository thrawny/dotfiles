## Your task

Create a detailed, actionable implementation plan through an interactive, iterative process. Read all referenced files fully, ground your plan in the actual codebase, and separate automated from manual success criteria.

**Parameters**:
- `$1` - Plan name/topic (used for filename: docs/plans/{name}.md)
- `$2` - Optional ticket/spec file path to read

1. Inputs
   - If `$1` is provided, use it as the plan name for the output file.
   - If `$2` is provided, read it completely as the ticket/spec.
   - If arguments are missing, ask for: description or ticket path, constraints, requirements, and relevant links/research.
   - Fully read any files the user mentions before proceeding.

2. Initial analysis
   - Identify key components, constraints, and acceptance criteria from the provided context.
   - Explore the codebase directly (e.g., ripgrep for keywords, open related files) to validate assumptions.
   - Present an informed understanding with only the questions you cannot answer from the code.

3. Propose plan structure
   - Share a short outline of phases and goals; ask for confirmation or adjustments to order/granularity.

4. Write the plan
   - Create `docs/plans/{descriptive_name}.md` using the template below (use `$1` if provided, otherwise derive from discussion).
   - Include concrete file paths and code references whenever possible.
   - Keep scope clear by adding a "What We're NOT Doing" section.

5. Success criteria
   - Separate Automated vs Manual checks.
   - Automated examples are acceptable and may include: `make migrate`, `make test`, `npm run typecheck`, `npm run lint`, `go test ./...`, `golangci-lint run`.
   - Tailor checks to the repository when known.

6. Review and iterate
   - Present the file path and a concise summary of the plan.
   - Incorporate feedback and refine until the plan is complete and actionable.

### Plan file template

```markdown
# [Feature/Task Name] Implementation Plan

## Overview

[Brief description of what we're implementing and why]

## Current State Analysis

[What exists now, what's missing, key constraints discovered]

## Desired End State

[Specification of the desired end state and how to verify it]

### Key Discoveries
- [Important finding with file:line reference]
- [Pattern to follow]
- [Constraint to work within]

## What We're NOT Doing

[Explicitly list out-of-scope items]

## Implementation Approach

[High-level strategy and reasoning]

## Phase 1: [Descriptive Name]

### Overview
[What this phase accomplishes]

### Changes Required
#### 1. [Component/File Group]
**File**: `path/to/file.ext`
**Changes**: [Summary of changes]

```[language]
// Specific code to add/modify
```

### Success Criteria

#### Automated Verification
- [ ] Migration applies cleanly: `make migrate`
- [ ] Unit tests pass: `make test`
- [ ] Type checking passes: `npm run typecheck`
- [ ] Linting passes: `npm run lint` or `make lint`
- [ ] Go tests pass: `go test ./...`
- [ ] No linting errors: `golangci-lint run`

#### Manual Verification
- [ ] Feature works as expected when tested via UI/CLI
- [ ] Performance is acceptable under expected load
- [ ] Edge cases verified manually

---

## Phase 2: [Descriptive Name]
[Repeat structure]

## Testing Strategy
- Unit tests: [what to test, edge cases]
- Integration/E2E: [end-to-end scenarios]
- Manual steps: [explicit steps]

## Performance Considerations
[Any implications or optimizations]

## Migration Notes
[How to handle existing data/systems]

## References
- Original ticket: `[path/to/ticket.md]`
- Related research: `docs/research/[relevant].md`
- Similar implementation: `[file:line]`
```

Notes
- Always read mentioned files fully before planning.
- If you hit an unresolved question, pause to ask—don’t paper over gaps.
