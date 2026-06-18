---
globs: "**/*.py"
alwaysApply: false
---

# Python Formatting

For routine Python validation and formatting, prefer Ruff. Ruff is enough for syntax/parse checks and avoids writing `__pycache__` files.

```bash
ruff check --fix <files> && ruff format <files>
```

Do not run `python -m py_compile` or `compileall` as a routine validation step. Only use them if explicitly requested or when investigating interpreter-specific bytecode behavior.

Pre-existing type errors can be ignored.

This rule applies when no project-specific formatting instructions exist.
