import { execFileSync } from "node:child_process";
import {
	accessSync,
	constants,
	mkdirSync,
	readFileSync,
	unlinkSync,
	watch,
} from "node:fs";
import os from "node:os";
import path from "node:path";
import type {
	ExtensionAPI,
	ExtensionContext,
} from "@earendil-works/pi-coding-agent";

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

// The agent-switch sidebar propagates a thread rename by dropping
// `<session_id>` (content = new name) in this directory; we watch it and
// apply the name to the live session so pi's own picker shows it too.
const RENAMES_DIR = path.join(
	process.env.XDG_STATE_HOME ?? path.join(os.homedir(), ".local", "state"),
	"agent-switch",
	"renames",
);

function commandOnPath(command: string): boolean {
	for (const directory of (process.env.PATH ?? "").split(path.delimiter)) {
		if (!directory) continue;
		try {
			accessSync(path.join(directory, command), constants.X_OK);
			return true;
		} catch {
			// Keep searching PATH.
		}
	}
	return false;
}

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
	if (!commandOnPath("agent-switch")) return;

	const ephemeralSessionId = `pi-ephemeral-${process.pid}-${Date.now().toString(36)}`;
	let disabled = false;
	let warned = false;
	let currentSessionId: string | null = null;

	// Sidebar rename hand-off: apply a pending rename dropped for this
	// session, if any. Called on session_start (covers resume) and from the
	// directory watcher (covers live renames).
	function applyPendingRename() {
		if (!currentSessionId) return;
		const file = path.join(RENAMES_DIR, currentSessionId);
		try {
			const name = readFileSync(file, "utf8").trim();
			unlinkSync(file);
			if (name) pi.setSessionName(name);
		} catch {
			// No pending rename (or unreadable) — nothing to do.
		}
	}

	try {
		mkdirSync(RENAMES_DIR, { recursive: true });
		watch(RENAMES_DIR, { persistent: false }, (_eventType, filename) => {
			if (filename === currentSessionId) applyPendingRename();
		});
	} catch {
		// Watcher is best-effort; session_start still applies pending renames.
	}

	function track(
		ctx: ExtensionContext,
		event: TrackEvent,
		sessionId?: string | null,
	) {
		if (disabled) return;

		const resolvedSessionId =
			sessionId ?? sessionIdFromContext(ctx, ephemeralSessionId);
		if (!resolvedSessionId) return;
		if (sessionId == null) currentSessionId = resolvedSessionId;

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

	pi.on("session_start", async (event, ctx) => {
		const previousSessionId = sessionIdFromFile(event.previousSessionFile);
		if (previousSessionId) {
			track(ctx, "session-end", previousSessionId);
		}
		track(ctx, "session-start");
		applyPendingRename();
	});

	pi.on("before_agent_start", async (_event, ctx) => {
		track(ctx, "prompt-submit");
	});

	pi.on("agent_settled", async (_event, ctx) => {
		track(ctx, "stop");
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		track(ctx, "session-end");
	});
}
