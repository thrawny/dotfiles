## Your task

Implement an approved plan from `docs/plans/` phase‑by‑phase. Read the plan and referenced files fully, make the required changes, verify using the plan’s success criteria, and update checkboxes in the plan file.

1. Inputs
   - If a plan path is provided, read it fully and note any existing checkmarks.
   - If not provided, ask for the plan path under `docs/plans/`.
   - Read the original ticket and all files mentioned in the plan completely.

2. Execute by phases
   - Implement each phase fully before moving to the next.
   - Keep changes minimal and consistent with repository patterns.
   - If the codebase reality differs from the plan, pause and present the mismatch clearly (see template below) and ask how to proceed.

3. Verification
   - After a phase, run the plan’s success checks.
   - Typical automated checks may include: `make check`, `make test`, `npm run typecheck`, `npm run lint`, `go test ./...`, `golangci-lint run` (use what the plan specifies).
   - For this repo, also consider: `uv run ruff check .`, `uv run ansible-lint ansible/`, `ansible-playbook ansible/main.yml --syntax-check` when relevant.
   - Fix issues before advancing; then mark plan checkboxes as complete.

4. Progress updates
   - Update the plan file’s checkboxes directly as work completes.
   - Keep a brief running summary of what changed.

5. Resuming work
   - If the plan already has checkmarks, trust them and continue from the first unchecked item unless something appears inconsistent.

### Mismatch template

```
Issue in Phase [N]
Expected (from plan): [what the plan says]
Found (in code): [actual situation]
Why this matters: [brief explanation]

Question: Should I [option A] or [option B]? If neither, please advise.
```

Notes
- Read referenced files fully before making changes.
- Keep momentum, but stop for clarifications when plan vs reality diverge.
