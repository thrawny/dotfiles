# Pi Extensions

Global Pi extensions live here and are symlinked to `~/.pi/agent/extensions`.

Place extension files as `*.ts` or directories with `index.ts`.

Examples:
- `my-extension.ts`
- `my-extension/index.ts`

## Agent Switch integration

`agent-switch.ts` forwards Pi lifecycle events to `agent-switch track` so session state is shared with tmux/niri switchers.

### Requirements

- `agent-switch` installed and on `PATH`
- daemon running (`agent-switch serve` or `agent-switch serve --niri`)

### Event mapping

| Pi event | `agent-switch` event |
|---|---|
| `session_start` | `session-start` |
| `session_shutdown` | `session-end` |
| `agent_start` | `prompt-submit` |
| `agent_end` | `stop` |
| `session_switch` / `session_fork` | `session-end` (old) + `session-start` (new) |

### Minimal extension example

```ts
import { execFileSync } from "node:child_process";
import path from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";

function sessionId(ctx: ExtensionContext): string {
  const file = ctx.sessionManager.getSessionFile();
  if (!file) return `pi-${process.pid}`;
  const base = path.basename(file);
  const ext = path.extname(base);
  return ext ? base.slice(0, -ext.length) : base;
}

export default function (pi: ExtensionAPI) {
  function track(
    ctx: ExtensionContext,
    event: "session-start" | "session-end" | "prompt-submit" | "stop",
  ) {
    execFileSync("agent-switch", ["track", event], {
      input: JSON.stringify({
        agent: "pi",
        event,
        session_id: sessionId(ctx),
        cwd: ctx.cwd,
      }),
      encoding: "utf8",
      stdio: ["pipe", "ignore", "pipe"],
    });
  }

  pi.on("session_start", async (_event, ctx) => track(ctx, "session-start"));
  pi.on("session_shutdown", async (_event, ctx) => track(ctx, "session-end"));
  pi.on("agent_start", async (_event, ctx) => track(ctx, "prompt-submit"));
  pi.on("agent_end", async (_event, ctx) => track(ctx, "stop"));
}
```

For a complete robust implementation (session IDs, cwd tracking, timeout, and graceful disable-on-error), see `agent-switch.ts`.
