# Global Claude Code Instructions

### Development Server Management

Always use the `zmx` skill for development server and long-running process tasks. This is mandatory.

- If the user explicitly mentions `zmx`, load and apply the `zmx` skill immediately.
- Before starting, stopping, restarting, or monitoring a dev server, apply the `zmx` skill workflow.
- If the user asks for logs, status, history, wait-for-completion, attach/detach, or background execution, use `zmx`.
- Do not run long-lived server commands directly in a normal shell unless the user explicitly asks you not to use `zmx`.
