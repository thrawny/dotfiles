# Pi Extensions

Global Pi extensions live here and are symlinked to `~/.pi/agent/extensions`.

Place extension files as `*.ts` or directories with `index.ts`.

Examples:

- `my-extension.ts`
- `my-extension/index.ts`

Current custom extensions include:

- `agent-switch.ts` — forwards Pi lifecycle events to `agent-switch track`
- `agents-local.ts` — loads private `AGENTS.local.md` files from the current git worktree
- `background-bash.ts` — adds `background: true` to `bash` using zmx with completion wake-ups, non-destructive timeout wake-ups, and 12-hour session retention
- `commands.ts` — loads repository/global Markdown commands
- `impeccable.ts` — integrates impeccable command metadata when available
- `rules.ts` — loads Markdown rule files as project guidance
- `schedule/` — scheduling extension entrypoint
- `show-tools.ts` — `/show-tools` for debugging active tool state
- `status-line.ts` — custom status line integration
- `teleport.ts` — Pi session teleport helpers
- `wayvoice.ts` — `ctrl+space` and `/voice` integration for inserting wayvoice transcripts into the Pi editor

## Local repository instructions

Pi officially loads `AGENTS.md`/`CLAUDE.md` context files. For private machine-local notes, `agents-local.ts` adds support for untracked `AGENTS.local.md` files from the current git worktree root down to the current directory. If a directory has no `AGENTS.local.md`, it falls back to `CLAUDE.local.md`. Reload Pi with `/reload` after editing one.

Official alternatives are `.pi/APPEND_SYSTEM.md` or `.pi/SYSTEM.md`, but those are project Pi resources rather than an `AGENTS.local.md`/`CLAUDE.local.md` convention.

## wayvoice integration

`wayvoice.ts` talks to the wayvoice daemon over its Unix socket:

```text
${XDG_RUNTIME_DIR:-/tmp}/wayvoice.sock
```

Override with environment variables:

- `PI_WAYVOICE_SOCKET` — socket path
- `PI_WAYVOICE_SHORTCUT` — Pi shortcut, default `ctrl+space`

On trigger, the extension checks `status`. If idle, it sends a JSON `toggle` request with overrides. If already recording/transcribing, it sends a plain stop `{"cmd":"toggle"}` request.

Request shape:

```ts
{
  cmd: "toggle",
  overrides: {
    prompt: string,
    extra_keywords: string[],
    replacements: Record<string, string>,
    inject_mode: "stdout"
  }
}
```

Response shape:

```ts
{
  status?: string,
  text?: string,
  error?: string
}
```

If `text` is present, the extension inserts it with `ctx.ui.pasteToEditor()`.

## Agent Switch integration

`agent-switch.ts` forwards Pi lifecycle events to `agent-switch track` so session state is shared with tmux/niri switchers.

### Requirements

- `agent-switch` installed and on `PATH`
- daemon running (`agent-switch serve` or `agent-switch serve --niri`)

### Event mapping

| Pi event                          | `agent-switch` event                        |
| --------------------------------- | ------------------------------------------- |
| `session_start`                   | `session-start`                             |
| `session_shutdown`                | `session-end`                               |
| `before_agent_start`              | `prompt-submit`                             |
| `agent_settled`                   | `stop`                                      |
| `session_switch` / `session_fork` | `session-end` (old) + `session-start` (new) |

### Minimal extension example

```ts
import { execFileSync } from "node:child_process";
import path from "node:path";
import type {
	ExtensionAPI,
	ExtensionContext,
} from "@earendil-works/pi-coding-agent";

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
	pi.on("before_agent_start", async (_event, ctx) =>
		track(ctx, "prompt-submit"),
	);
	pi.on("agent_settled", async (_event, ctx) => track(ctx, "stop"));
}
```

For a complete robust implementation (session IDs, cwd tracking, timeout, and graceful disable-on-error), see `agent-switch.ts`.
