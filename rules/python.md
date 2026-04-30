---
globs: "**/*.py"
alwaysApply: false
---

# Python Formatting

After completing edits to Python files, run:

```bash
ruff check --fix <files> && ruff format <files>
```

Pre-existing type errors can be ignored.

This rule applies when no project-specific formatting instructions exist.
