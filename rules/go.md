---
globs: "**/*.go"
alwaysApply: false
---

# Go Formatting

Always follow `modernize` diagnostics when editing Go code. Apply suggested modernizations to use current Go idioms and language features.

After completing edits to Go files, run:

```bash
golangci-lint fmt --enable golines <files>
```

This rule applies when no project-specific formatting instructions exist.

# Go Testing

Prefer `gotestsum` over `go test` for running tests. It provides better output formatting and failure summaries:

```bash
gotestsum ./...
gotestsum --format testdox ./...  # verbose test names
```
