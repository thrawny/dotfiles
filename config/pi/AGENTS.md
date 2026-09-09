# Pi Config Instructions

When changing files under `config/pi/`, run from the repository root:

```bash
just pi
```

This lints/formats Pi extension files with Oxlint/Oxfmt and runs the Pi extension TypeScript typecheck.

`agents-local.ts` loads untracked `AGENTS.local.md` files from the git worktree root down to the current directory, falling back to `CLAUDE.local.md`. Pi needs `/reload` after one is edited.
