rec {
  ephemeralTools = ''
    ## Ephemeral tools

    If a needed tool/library is missing, prefer reproducible one-offs over ad hoc scripts or global installs.

    Prefer `, <cmd> ...` for one-off CLI tools by executable name.
    Examples: `, magick in.png out.jpg`, `, tesseract in.png stdout`.

    Use `nix shell nixpkgs#<pkg> -c <cmd> ...` when you need an explicit package, multiple tools, or comma fails.
    Use `nix run` only when the package's default app is exactly the command you need.

    For PDF-to-Markdown extraction, prefer `pymupdf4llm`.

    Use `uv run --with <pkg> python ...` for Python libs not available in the current environment.
    Examples: `uv run --with pillow python image.py`, `uv run --with pandas --with openpyxl python sheet.py`.

    For inline heredoc Python scripts that make HTTP requests, prefer `requests` via `uv run --with requests python` over Python stdlib modules like `urllib.request` or `http.client`.

    PDF example: `import pymupdf4llm; print(pymupdf4llm.to_markdown("document.pdf"))`.
  '';

  shellPortability = ''
    ## Shell portability

    Do not assign to a shell variable named `status`. In zsh, `status` is a read-only special parameter equivalent to `$?`.
    Use `exit_code`, `cmd_status`, or a command-specific name such as `review_status` instead.
  '';

  sandbox = ''
    ## Sandbox

    - When `SANDBOX=1`, host secrets/configs are intentionally unavailable; do not try to bypass the sandbox.
    - Never inspect or edit `.secrets*`; sandbox startup handles them. Use targeted `printenv VAR` checks; `env`/`printenv` are sandbox-redacted.
    - Docker commands should use the sandbox-provided `DOCKER_HOST`; do not access `/var/run/docker.sock`.
  '';

  backgroundTasks = ''
    ## Background tasks and long-running processes

    Run builds, tests, linters, and other gates in the foreground — their result decides your next step, so backgrounding them only adds latency and invites moving on without the verdict. Reserve background tasks for work that genuinely runs while you do something else: delegated agent turns (acpx/codex) and bounded readiness waits.

    Only background commands that provably exit. The completion notification only fires on process exit, so a never-terminating background command hangs silently forever.

    - Never background a persistent service or a supervisor/restart loop. Dev stacks and servers run in zmx (`zmx run -d`), which survives the session and is visible to other sessions. Inspect via `zmx history`; on observed failure restart once, never via a loop.
    - Readiness waits must be bounded and must match failure output as well as the ready banner: `timeout 300 bash -c 'until <ready-or-failed>; do sleep 2; done'`, or use the Monitor tool, which enforces a timeout.
    - Before ending a session or handing off, stop background tasks you started; anything deliberately left running must be named in the handoff.
  '';

  contextManagement = ''
    ## Context management

    When the conversation is summarized for compaction, always preserve: the current goal and immediate next action; decisions made and their reasoning; paths of files read or modified and commits created; test/gate results and unresolved errors; anything deliberately left running (dev servers, background agents, acpx sessions). Write the summary as terse bullets — the preserved facts only, no narrative or process recap; a session auto-handoff carrying detailed state is injected after compaction, so the summary does not need to be exhaustive.
  '';

  claudeGlobal = ''
    # Global Claude Code Instructions

    ${ephemeralTools}
    ${shellPortability}
    ${sandbox}
    ${backgroundTasks}
    ${contextManagement}
  '';

  codexGlobal = ''
    # Global Codex Instructions

    ${ephemeralTools}
    ${shellPortability}
    ${sandbox}
    ## Code Quality Tools

    After editing files, run the appropriate formatting/linting tools. These are fallback defaults when a project has no specific instructions.

    ### Go

    Always follow `modernize` diagnostics when editing Go code. Apply suggested modernizations to use current Go idioms and language features.

    ```bash
    golangci-lint fmt --enable golines <files>
    ```

    Prefer `gotestsum` over `go test` for running tests:

    ```bash
    gotestsum ./...
    ```

    ### Python

    Prefer Ruff for Python validation and formatting; Ruff is enough for routine syntax/parse checks and avoids writing `__pycache__` files.

    ```bash
    ruff check --fix <files> && ruff format <files>
    ```

    Do not run `python -m py_compile` or `compileall` as a routine validation step. Only use them if explicitly requested or investigating interpreter-specific bytecode behavior. Pre-existing type errors can be ignored.

    ### Rust

    ```bash
    cargo fmt
    ```

    ### TypeScript/JavaScript

    ```bash
    biome check --write <files>
    ```

    For type checking, prefer project task runners (for example `just typecheck`).
    If no task runner recipe exists, run:

    ```bash
    tsc --noEmit
    ```

    ### Nix

    ```bash
    nixfmt <files>
    ```
  '';

  piGlobal = ''
    # Global Pi Instructions

    Prefer `fd` over `find` for file discovery when available; it is faster, respects ignore files by default, and has friendlier syntax.

    ${ephemeralTools}
    ${shellPortability}
    ${sandbox}
  '';
}
