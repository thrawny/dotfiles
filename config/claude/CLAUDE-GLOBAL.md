### Screenshot and Testing

- When using playwright mcp to take screenshots, always take raw (png) screenshots

### Coding Style Guidelines

**Simplicity First**: Write simple, readable code that solves the immediate problem without over-engineering. Avoid premature abstractions, unnecessary design patterns, and hypothetical future-proofing. Favor straightforward solutions that a junior developer could understand and modify. Remember: code is read far more often than it's written, and the best abstraction is often no abstraction. When in doubt, choose clarity over cleverness - inline code can be clearer than complex abstractions, and some duplication is better than the wrong abstraction.

**Fail Fast, Don't Hide Errors**: Avoid the try-catch-log anti-pattern where errors are caught, logged, and execution continues as if nothing happened. This hides problems and makes debugging harder. Instead, let errors propagate to where they can be properly handled or fail fast to expose issues early. Only catch errors when you can genuinely recover from them or need to add context before re-throwing. Silently swallowing exceptions with just a log statement creates systems that appear to work but are actually failing - making issues harder to diagnose and fix. When in doubt, let it crash and fix the root cause rather than papering over problems.

**Early Returns and Guard Clauses**: Use early returns and guard clauses to handle edge cases and invalid inputs at the beginning of functions. This reduces nesting, makes preconditions explicit, and keeps the happy path at the lowest indentation level. Instead of wrapping your entire function in an if-else pyramid, check for invalid states early and return immediately. This makes code more readable by presenting the main logic prominently rather than burying it in nested conditions. The primary business logic should be easy to follow without having to mentally track multiple levels of conditionals.

**Avoid Redundant Comments**: Don't write comments that merely restate what the code already says. Comments like `// increment counter` above `counter++` add noise without value. Particularly avoid documenting parameters and return types in comments when they're already specified through type hints or annotations - this creates maintenance burden and potential for inconsistency. Comments should explain _why_ something is done when the business reason isn't obvious, not _what_ is being done. Good variable names and clear code structure eliminate the need for most comments. If you feel code needs extensive comments to be understood, consider refactoring it to be clearer instead.

### Development Server Management

- Use `tmux-dev-server-control` CLI for managing development server sessions in tmux
- Auto-generates session names: `{foldername}-{command-slug}` (e.g., `asset-simulator-uv-run-main-py`)
- Commands: `start [-d <directory>] <command>`, `stop <session>`, `logs <session>`, `list`, `status`, `monitor <session>`
- Validates commands against allowlist (npm, go, python, docker, etc.)
- Enforces workspace boundaries (default: ~/code) and requires git repositories
- Shows actual error output when commands fail immediately

### Searching for Documentation

**Always start with context7 mcp**: It is a really good tool to retrieve the latest official documentation and code examples for all kinds of software.
Fall back to web search and web fetch.
