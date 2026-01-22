# Global Codex Instructions

**Project-specific AGENTS.md files take precedence over these global defaults.**

## Code Quality Tools

After editing files, run the appropriate formatting/linting tools. These are fallback defaults when a project has no specific instructions.

### Go

```bash
golangci-lint fmt --enable golines <files>
```

### Python

```bash
ruff check --fix <files> && ruff format <files>
```

Pre-existing type errors can be ignored.

### Rust

```bash
cargo fmt
```

### TypeScript/JavaScript

```bash
biome check --write <files>
```

### Nix

```bash
nixfmt <files>
```

## Task Runners

If the project has a `Justfile`, prefer using `just` commands over raw tool invocations. Run `just` to see available recipes.
