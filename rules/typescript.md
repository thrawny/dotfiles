---
globs: "**/*.{ts,tsx,js,jsx}"
alwaysApply: false
---

# TypeScript/JavaScript Formatting & Type Checking

After completing edits to TypeScript or JavaScript files, run formatting/linting:

```bash
biome check --write <files>
```

Then run type checking:

- Prefer project task runners when available (for example, `just typecheck` or a project-specific `just` TypeScript recipe)
- If there is no task runner recipe, run TypeScript directly:

```bash
tsc --noEmit
```

If the project keeps TypeScript in a subdirectory, use its config explicitly (for example, `tsc -p config/pi/extensions --noEmit`).

This rule applies when no project-specific instructions override it.
