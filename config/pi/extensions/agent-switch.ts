import { execFileSync } from "node:child_process";
import path from "node:path";
import type {
	ExtensionAPI,
	ExtensionContext,
} from "@mariozechner/pi-coding-agent";

type TrackEvent =
	| "session-start"
	| "session-end"
	| "prompt-submit"
	| "stop"
	| "notification";

type TrackPayload = {
	agent: "pi";
	session_id: string;
	cwd: string;
	event: TrackEvent;
	transcript_path?: string;
};

const START_TIMEOUT_MS = 800;

function sessionIdFromFile(
	sessionFile: string | null | undefined,
): string | null {
	if (!sessionFile) return null;
	const base = path.basename(sessionFile);
	const ext = path.extname(base);
	return ext.length > 0 ? base.slice(0, -ext.length) : base;
}

function sessionIdFromContext(
	ctx: ExtensionContext,
	ephemeralId: string,
): string {
	return sessionIdFromFile(ctx.sessionManager.getSessionFile()) ?? ephemeralId;
}

function normalizedSessionName(
	sessionName: string | null | undefined,
): string | null {
	const trimmed = sessionName?.trim();
	return trimmed ? trimmed : null;
}

function runTrack(
	event: TrackEvent,
	payload: TrackPayload,
	sessionName?: string | null,
): { ok: true } | { ok: false; error: string } {
	try {
		const args = ["track", event];
		const normalizedName = normalizedSessionName(sessionName);
		if (normalizedName) {
			args.push("--session-name", normalizedName);
		}
		execFileSync("agent-switch", args, {
			input: JSON.stringify(payload),
			encoding: "utf8",
			stdio: ["pipe", "ignore", "pipe"],
			timeout: START_TIMEOUT_MS,
		});
		return { ok: true };
	} catch (error) {
		const message = error instanceof Error ? error.message : String(error);
		return { ok: false, error: message };
	}
}

export default function (pi: ExtensionAPI) {
	const ephemeralSessionId = `pi-ephemeral-${process.pid}-${Date.now().toString(36)}`;
	let disabled = false;
	let warned = false;

	function track(
		ctx: ExtensionContext,
		event: TrackEvent,
		sessionId?: string | null,
	) {
		if (disabled) return;

		const resolvedSessionId =
			sessionId ?? sessionIdFromContext(ctx, ephemeralSessionId);
		if (!resolvedSessionId) return;

		const payload: TrackPayload = {
			agent: "pi",
			session_id: resolvedSessionId,
			cwd: ctx.cwd,
			event,
		};
		const sessionFile = ctx.sessionManager.getSessionFile();
		if (sessionFile) {
			payload.transcript_path = sessionFile;
		}

		const result = runTrack(event, payload, pi.getSessionName());

		if (!result.ok) {
			disabled = true;
			if (!warned && ctx.hasUI) {
				warned = true;
				ctx.ui.notify(
					`agent-switch integration disabled: ${result.error}`,
					"warning",
				);
			}
		}
	}

	pi.on("session_start", async (_event, ctx) => {
		track(ctx, "session-start");
	});

	pi.on("agent_start", async (_event, ctx) => {
		track(ctx, "prompt-submit");
	});

	pi.on("agent_end", async (_event, ctx) => {
		track(ctx, "stop");
	});

	pi.on("session_switch", async (event, ctx) => {
		const previousSessionId = sessionIdFromFile(event.previousSessionFile);
		if (previousSessionId) {
			track(ctx, "session-end", previousSessionId);
		}
		track(ctx, "session-start");
	});

	pi.on("session_fork", async (event, ctx) => {
		const previousSessionId = sessionIdFromFile(event.previousSessionFile);
		if (previousSessionId) {
			track(ctx, "session-end", previousSessionId);
		}
		track(ctx, "session-start");
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		track(ctx, "session-end");
	});
}
