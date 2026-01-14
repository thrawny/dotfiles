---
globs: "**/*.go"
alwaysApply: false
---

# Go Formatting

After completing edits to Go files, run:

```bash
golangci-lint fmt --enable golines <files>
```

This rule applies when no project-specific formatting instructions exist.
