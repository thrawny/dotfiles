### Screenshot and Testing

- When using playwright mcp to take screenshots, always take raw (png) screenshots

### Coding Style Guidelines

**Simplicity First**: Write simple, readable code that solves the immediate problem without over-engineering. Avoid premature abstractions, unnecessary design patterns, and hypothetical future-proofing. Favor straightforward solutions that a junior developer could understand and modify. Remember: code is read far more often than it's written, and the best abstraction is often no abstraction. When in doubt, choose clarity over cleverness - inline code can be clearer than complex abstractions, and some duplication is better than the wrong abstraction.

**Fail Fast, Don't Hide Errors**: Avoid the try-catch-log anti-pattern where errors are caught, logged, and execution continues as if nothing happened. This hides problems and makes debugging harder. Instead, let errors propagate to where they can be properly handled or fail fast to expose issues early. Only catch errors when you can genuinely recover from them or need to add context before re-throwing. Silently swallowing exceptions with just a log statement creates systems that appear to work but are actually failing - making issues harder to diagnose and fix. When in doubt, let it crash and fix the root cause rather than papering over problems.

**Early Returns and Guard Clauses**: Use early returns and guard clauses to handle edge cases and invalid inputs at the beginning of functions. This reduces nesting, makes preconditions explicit, and keeps the happy path at the lowest indentation level. Instead of wrapping your entire function in an if-else pyramid, check for invalid states early and return immediately. This makes code more readable by presenting the main logic prominently rather than burying it in nested conditions. The primary business logic should be easy to follow without having to mentally track multiple levels of conditionals.

**Avoid Redundant Comments**: Don't write comments that merely restate what the code already says. Comments like `// increment counter` above `counter++` add noise without value. Particularly avoid documenting parameters and return types in comments when they're already specified through type hints or annotations - this creates maintenance burden and potential for inconsistency. Comments should explain _why_ something is done when the business reason isn't obvious, not _what_ is being done. Good variable names and clear code structure eliminate the need for most comments. If you feel code needs extensive comments to be understood, consider refactoring it to be clearer instead.

### Notifications

Use `notify "message"` to alert the user when:
- A long-running task completes (builds, tests, deployments)
- You're waiting for user input after completing a task
- An error requires their attention

The title is automatically set to the current directory name.

### Development Server Management

Use the `zmx` skill.

### Sandbox and Code Execution

When sandbox is enabled, use `python` directly (not `uv run`) for running arbitrary code. The sandbox constrains filesystem writes to the project directory and blocks network access, making it safe to execute. The project's `.venv/bin/python` is used automatically via direnv, so all project packages are available.

Tools that need cache/network access (`go`, `npm`, `cargo`, `uv`, `nix`, `docker`, `make`, `just`) are excluded from the sandbox via `excludedCommands` and controlled by permission rules instead.

### Searching for Documentation

**Start with context7 mcp**: A good tool for retrieving the latest official documentation and code examples for software libraries.
Fall back to web search and web fetch.
