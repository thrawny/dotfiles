import type {
	ExtensionAPI,
	ExtensionCommandContext,
	SessionEntry,
} from "@earendil-works/pi-coding-agent";

const HANDOFF_TIMEOUT_MS = 5 * 60 * 1000;
const HANDOFF_POLL_MS = 25;
const STATE_LIMIT = 4_000;

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null;
}

function textFromContent(content: unknown): string {
	if (typeof content === "string") return content.trim();
	if (!Array.isArray(content)) return "";
	return content
		.filter(
			(block): block is { type: "text"; text: string } =>
				isRecord(block) &&
				block.type === "text" &&
				typeof block.text === "string",
		)
		.map((block) => block.text)
		.join("\n")
		.trim();
}

function assistantResult(
	entries: SessionEntry[],
	startIndex: number,
): { text: string; complete: boolean } | undefined {
	for (let index = entries.length - 1; index >= startIndex; index--) {
		const entry = entries[index];
		if (entry.type !== "message" || !isRecord(entry.message)) continue;
		if (entry.message.role !== "assistant") continue;
		const text = textFromContent(entry.message.content);
		const stopReason = entry.message.stopReason;
		return {
			text,
			complete: stopReason === undefined || stopReason === "stop",
		};
	}
	return undefined;
}

export function buildHandoffRequest(
	goal: string,
	repositoryState: string,
): string {
	return `The user requested a handoff to a fresh session with this goal:

${goal}

Write a focused transfer note for another coding agent with no access to this chat. Use your full current context, including any context available through native compaction. Do not call tools and do not continue the implementation.

Use these headings exactly:

## Next goal
## Current state
## Decisions and rationale
## Files and artifacts
## Verification
## Constraints and preferences
## Live state
## Immediate action

Rules:
- Target 1000 tokens; never exceed 1500.
- Include only facts relevant to the next goal.
- Preserve exact paths, symbols, commands, errors, and test results when useful.
- Reference plans, commits, diffs, and issues instead of duplicating them.
- Record rejected approaches only when that prevents repeated work.
- If a section has nothing relevant, write "(none)".
- Output only the transfer note.

Repository snapshot supplied by the handoff extension:
${repositoryState}`;
}

export function buildFreshSessionPrompt(
	goal: string,
	note: string,
	parentSession: string,
	repositoryState: string,
): string {
	return `## Task

${goal}

${note}

## Working tree at handoff

${repositoryState}

## Source history

Parent session: \`${parentSession}\`

A bounded \`history_query\` tool can retrieve a specific missing fact from that parent or another Pi, Codex, or Claude session. Use it only when a concrete missing fact blocks progress. Do not reconstruct or broadly reread the previous session.`;
}

function bounded(text: string): string {
	if (text.length <= STATE_LIMIT) return text;
	return `${text.slice(0, STATE_LIMIT)}\n[truncated]`;
}

async function repositorySnapshot(
	pi: ExtensionAPI,
	ctx: ExtensionCommandContext,
): Promise<string> {
	const [status, diff] = await Promise.all([
		pi.exec("git", ["status", "--short", "--branch"], {
			cwd: ctx.cwd,
			timeout: 3_000,
		}),
		pi.exec("git", ["diff", "--stat", "HEAD"], {
			cwd: ctx.cwd,
			timeout: 3_000,
		}),
	]);
	if (status.code !== 0) return "Not in a Git worktree, or Git status failed.";
	const statusText = status.stdout.trim() || "Working tree clean.";
	const diffText =
		diff.code === 0 && diff.stdout.trim() ? diff.stdout.trim() : "";
	return bounded(
		["```text", statusText, diffText && `\nDiff stat:\n${diffText}`, "```"]
			.filter(Boolean)
			.join("\n"),
	);
}

async function waitForHandoffNote(
	ctx: ExtensionCommandContext,
	startIndex: number,
	timeoutMs = HANDOFF_TIMEOUT_MS,
): Promise<string | undefined> {
	const deadline = Date.now() + timeoutMs;
	while (Date.now() < deadline) {
		const result = assistantResult(ctx.sessionManager.getBranch(), startIndex);
		if (result && ctx.isIdle()) {
			return result.complete && result.text ? result.text : undefined;
		}
		await new Promise<void>((resolve) => setTimeout(resolve, HANDOFF_POLL_MS));
	}
	return undefined;
}

export default function handoffExtension(pi: ExtensionAPI) {
	pi.registerCommand("handoff", {
		description: "Generate a focused handoff and open a parent-linked session",
		getArgumentCompletions: () => null,
		handler: async (args, ctx) => {
			if (!ctx.model) {
				ctx.ui.notify("No model selected.", "error");
				return;
			}
			const parentSession = ctx.sessionManager.getSessionFile();
			if (!parentSession) {
				ctx.ui.notify(
					"The current session has not been persisted yet.",
					"error",
				);
				return;
			}
			const goal =
				args.trim() || "Continue the current work from the next logical step.";
			const snapshot = await repositorySnapshot(pi, ctx);
			const startIndex = ctx.sessionManager.getBranch().length;
			const previousTools = pi.getActiveTools();

			ctx.ui.notify(
				"Generating handoff from the current agent context…",
				"info",
			);
			let note: string | undefined;
			try {
				pi.setActiveTools([]);
				pi.sendMessage(
					{
						customType: "handoff-request",
						content: buildHandoffRequest(goal, snapshot),
						display: false,
					},
					{ triggerTurn: true },
				);
				note = await waitForHandoffNote(ctx, startIndex);
			} finally {
				pi.setActiveTools(previousTools);
			}

			if (!note) {
				ctx.ui.notify(
					"The handoff note was cancelled, incomplete, or timed out.",
					"error",
				);
				return;
			}

			const prompt = buildFreshSessionPrompt(
				goal,
				note,
				parentSession,
				snapshot,
			);
			const result = await ctx.newSession({
				parentSession,
				withSession: async (newSession) => {
					newSession.ui.setEditorText(prompt);
					newSession.ui.notify(
						"Handoff ready — review it, then press Enter to continue.",
						"info",
					);
				},
			});
			if (result.cancelled) {
				ctx.ui.notify("New session creation was cancelled.", "warning");
			}
		},
	});
}
