import type {
	ExtensionAPI,
	ExtensionContext,
} from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";

type ThinkingLevel = "off" | "minimal" | "low" | "medium" | "high" | "xhigh";
type LoopIntervalUnit = "seconds" | "minutes" | "hours" | "days";

type ModelOverride = {
	query: string;
	thinkingLevel?: ThinkingLevel;
};

type Loop = {
	id: number;
	prompt: string;
	everyMs: number;
	createdAt: number;
	lastRunAt: number | null;
	timer: NodeJS.Timeout;
	modelOverride?: ModelOverride;
};

const LOOP_TOOL = "loop";

const thinkingLevelSchema = Type.Union([
	Type.Literal("off"),
	Type.Literal("minimal"),
	Type.Literal("low"),
	Type.Literal("medium"),
	Type.Literal("high"),
	Type.Literal("xhigh"),
]);

const intervalUnitSchema = Type.Union([
	Type.Literal("seconds"),
	Type.Literal("minutes"),
	Type.Literal("hours"),
	Type.Literal("days"),
]);

const loops = new Map<number, Loop>();

let nextLoopId = 1;
let currentCtx: ExtensionContext | null = null;
let activeLoopRunId: number | null = null;
let activeLoopToolTargetId: number | null = null;
let activeLoopRestore: {
	modelId?: string;
	provider?: string;
	thinkingLevel: ThinkingLevel;
} | null = null;
let restoringAfterLoopRun = false;
let loopEnabled = false;
let piRef: ExtensionAPI | null = null;

function textResult(
	text: string,
	details: Record<string, unknown> = {},
	isError = false,
) {
	return {
		content: [{ type: "text" as const, text }],
		details,
		isError,
	};
}

function syncLoopToolActivation() {
	if (!piRef) return;
	const active = piRef.getActiveTools().filter((name) => name !== LOOP_TOOL);
	if (!loopEnabled) {
		piRef.setActiveTools(active);
		return;
	}
	piRef.setActiveTools([...active, LOOP_TOOL]);
}

function formatInterval(ms: number): string {
	const totalSeconds = Math.max(1, Math.floor(ms / 1000));
	if (totalSeconds % 86_400 === 0) return `${totalSeconds / 86_400}d`;
	if (totalSeconds % 3_600 === 0) return `${totalSeconds / 3_600}h`;
	if (totalSeconds % 60 === 0) return `${totalSeconds / 60}m`;
	return `${totalSeconds}s`;
}

function formatRelative(ms: number): string {
	if (ms <= 0) return "now";

	const totalSeconds = Math.ceil(ms / 1000);
	const hours = Math.floor(totalSeconds / 3600);
	const minutes = Math.floor((totalSeconds % 3600) / 60);
	const seconds = totalSeconds % 60;

	if (hours > 0) {
		if (minutes > 0) return `${hours}h ${minutes}m`;
		return `${hours}h`;
	}
	if (minutes > 0) {
		if (seconds > 0) return `${minutes}m ${seconds}s`;
		return `${minutes}m`;
	}
	return `${seconds}s`;
}

function normalize(value: string): string {
	return value.toLowerCase().replace(/[^a-z0-9]+/g, "");
}

function intervalToMs(value: number, unit: LoopIntervalUnit): number {
	if (unit === "seconds") return value * 1000;
	if (unit === "minutes") return value * 60_000;
	if (unit === "hours") return value * 3_600_000;
	return value * 86_400_000;
}

function toModelOverride(
	model: string | undefined,
	thinkingLevel: ThinkingLevel | undefined,
): ModelOverride | undefined {
	const query = model?.trim();
	if (!query && !thinkingLevel) return undefined;
	return {
		query: query || "current",
		thinkingLevel,
	};
}

function formatModelOverride(
	modelOverride?: ModelOverride,
	currentModelId?: string,
): string {
	if (!modelOverride) return "";
	const modelName =
		modelOverride.query === "current" || !modelOverride.query
			? currentModelId
			: modelOverride.query;
	const modelPart = modelName ? ` · model ${modelName}` : "";
	if (!modelOverride.thinkingLevel) return modelPart;
	if (modelOverride.thinkingLevel === "off") {
		return `${modelPart} · thinking off`;
	}
	return `${modelPart} · ${modelOverride.thinkingLevel} thinking`;
}

function loopMessage(loop: Loop): string {
	return [
		`[automatic loop #${loop.id}; every ${formatInterval(loop.everyMs)}]`,
		loop.prompt,
	].join("\n\n");
}

function sortedLoops(): Loop[] {
	return [...loops.values()].sort((a, b) => a.id - b.id);
}

function loopToDetails(loop: Loop) {
	return {
		id: loop.id,
		prompt: loop.prompt,
		everyMs: loop.everyMs,
		createdAt: loop.createdAt,
		lastRunAt: loop.lastRunAt,
		modelOverride: loop.modelOverride,
	};
}

function loopSummary(loop: Loop): string {
	const dueIn = formatRelative(
		Math.max(0, (loop.lastRunAt ?? loop.createdAt) + loop.everyMs - Date.now()),
	);
	const lastRun = loop.lastRunAt
		? `${formatRelative(Date.now() - loop.lastRunAt)} ago`
		: "never";
	return `#${loop.id} every ${formatInterval(loop.everyMs)} · next ${dueIn} · last ${lastRun}${formatModelOverride(loop.modelOverride, currentCtx?.model?.id)} · ${loop.prompt}`;
}

function formatLoopStatus(): string {
	const allLoops = sortedLoops();
	if (allLoops.length === 0) return "No active loops in this session.";
	return [
		`Active loops (${allLoops.length})`,
		...allLoops.map(loopSummary),
	].join("\n");
}

function clearLoop(loop: Loop) {
	clearInterval(loop.timer);
	loops.delete(loop.id);
	if (activeLoopRunId === loop.id) activeLoopRunId = null;
	if (activeLoopToolTargetId === loop.id) activeLoopToolTargetId = null;
}

function clearAllLoops() {
	for (const loop of loops.values()) {
		clearInterval(loop.timer);
	}
	loops.clear();
	activeLoopRunId = null;
	activeLoopToolTargetId = null;
}

function parseLoopIdFromPrompt(prompt: string): number | null {
	const match = prompt.match(/^\[automatic loop #(\d+); every [^\]]+\]/);
	if (!match) return null;
	const id = Number.parseInt(match[1], 10);
	return Number.isFinite(id) ? id : null;
}

async function findModel(ctx: ExtensionContext, query: string) {
	const trimmed = query.trim();
	if (!trimmed) return null;

	const providerMatch = trimmed.match(/^([^/]+)\/(.+)$/);
	if (providerMatch) {
		return ctx.modelRegistry.find(providerMatch[1], providerMatch[2]) ?? null;
	}

	const available = ctx.modelRegistry.getAvailable();
	const exactNormalized = normalize(trimmed);

	for (const model of available) {
		if (normalize(model.id) === exactNormalized) return model;
		if (normalize(model.name) === exactNormalized) return model;
	}

	for (const model of available) {
		if (normalize(model.id).includes(exactNormalized)) return model;
		if (normalize(model.name).includes(exactNormalized)) return model;
	}

	return null;
}

async function applyLoopOverride(loop: Loop, ctx: ExtensionContext) {
	if (!loop.modelOverride || !piRef) return;

	activeLoopRestore = {
		modelId: ctx.model?.id,
		provider: ctx.model?.provider,
		thinkingLevel: piRef.getThinkingLevel() as ThinkingLevel,
	};

	if (loop.modelOverride.query !== "current") {
		const model = await findModel(ctx, loop.modelOverride.query);
		if (!model) {
			ctx.ui.notify(
				`Loop #${loop.id}: model not found: ${loop.modelOverride.query}`,
				"warning",
			);
			activeLoopRestore = null;
			return;
		}

		const success = await piRef.setModel(model);
		if (!success) {
			ctx.ui.notify(
				`Loop #${loop.id}: no API key for ${model.provider}/${model.id}`,
				"warning",
			);
			activeLoopRestore = null;
			return;
		}
	}

	if (loop.modelOverride.thinkingLevel) {
		piRef.setThinkingLevel(loop.modelOverride.thinkingLevel);
	}
}

async function restoreAfterLoopRun(ctx: ExtensionContext) {
	if (!piRef || !activeLoopRestore || restoringAfterLoopRun) return;
	const restore = activeLoopRestore;
	activeLoopRestore = null;
	restoringAfterLoopRun = true;
	try {
		if (restore.provider && restore.modelId) {
			const model = ctx.modelRegistry.find(restore.provider, restore.modelId);
			if (model) {
				await piRef.setModel(model);
			}
		}
		piRef.setThinkingLevel(restore.thinkingLevel);
	} finally {
		restoringAfterLoopRun = false;
	}
}

function triggerLoop(loopId: number): "started" | "busy" | "missing" {
	const loop = loops.get(loopId);
	const ctx = currentCtx;
	if (!loop || !ctx) return "missing";
	if (activeLoopRunId !== null || !ctx.isIdle()) return "busy";

	loop.lastRunAt = Date.now();
	activeLoopRunId = loop.id;
	activeLoopToolTargetId = loop.id;
	ctx.ui.notify(
		`Running loop #${loop.id}: ${loop.prompt}${formatModelOverride(loop.modelOverride, ctx.model?.id)}`,
		"info",
	);
	piRef?.sendUserMessage(loopMessage(loop));
	return "started";
}

export default function (pi: ExtensionAPI) {
	piRef = pi;

	pi.on("session_start", async (_event, ctx) => {
		currentCtx = ctx;
		activeLoopRestore = null;
		loopEnabled = false;
		clearAllLoops();
		syncLoopToolActivation();
	});

	pi.on("session_shutdown", async () => {
		clearAllLoops();
		currentCtx = null;
		activeLoopRestore = null;
		loopEnabled = false;
		syncLoopToolActivation();
	});

	pi.on("before_agent_start", async (event, ctx) => {
		currentCtx = ctx;
		const loopId = parseLoopIdFromPrompt(event.prompt);
		if (loopId === null) return;
		const loop = loops.get(loopId);
		if (!loop) return;
		await applyLoopOverride(loop, ctx);
		return {
			systemPrompt: `${event.systemPrompt}\n\nThis is a recurring loop run for loop #${loop.id}. If the recurring task has finished and the loop should stop, call the loop tool with { action: "complete" } instead of continuing the loop.`,
		};
	});

	pi.on("agent_end", async (_event, ctx) => {
		currentCtx = ctx;
		activeLoopRunId = null;
		activeLoopToolTargetId = null;
		await restoreAfterLoopRun(ctx);
	});

	pi.registerCommand("loop", {
		description:
			"Enable the loop tool in this session and forward a loop request",
		handler: async (args, ctx) => {
			currentCtx = ctx;
			const input = args.trim();
			if (!input) {
				ctx.ui.notify(
					"Usage: /loop <natural language> (example: /loop check CI every 5m)",
					"info",
				);
				return;
			}

			loopEnabled = true;
			syncLoopToolActivation();
			ctx.ui.notify("Loop tool enabled for this session", "info");
			const message = `Use the loop tool for this request: ${input}`;
			if (ctx.isIdle()) {
				pi.sendUserMessage(message);
				return;
			}
			pi.sendUserMessage(message, { deliverAs: "followUp" });
		},
	});

	pi.registerTool({
		name: LOOP_TOOL,
		label: "Loop",
		description: `Create or manage recurring loops in the current session.

	CREATE (omit action):
	• { prompt, interval: { value, unit } } - create a loop
	• Optional overrides: { model, thinkingLevel }

	MANAGEMENT (set action):
	• { action: "list" } - list active loops
	• { action: "stop", loopId } - stop one loop
	• { action: "run_now", loopId } - trigger one loop immediately
	• { action: "stop_all" } - stop all loops
	• { action: "complete", reason? } - stop the currently running loop because the recurring task is finished`,
		parameters: Type.Object({
			action: Type.Optional(
				Type.String({
					description:
						"Loop action: omit to create, or set to 'list', 'stop', 'run_now', 'stop_all', or 'complete'.",
				}),
			),
			prompt: Type.Optional(
				Type.String({
					description:
						"For create: the recurring prompt to send each time, without the scheduling phrase.",
				}),
			),
			interval: Type.Optional(
				Type.Object({
					value: Type.Number({
						exclusiveMinimum: 0,
						description: "Positive interval amount.",
					}),
					unit: intervalUnitSchema,
				}),
			),
			loopId: Type.Optional(
				Type.Number({
					description:
						"For stop or run_now: the loop ID returned by list or create.",
				}),
			),
			model: Type.Optional(
				Type.String({
					description:
						"For create: optional model query such as gpt-5, anthropic/claude-sonnet-4-5, or current.",
				}),
			),
			thinkingLevel: Type.Optional(thinkingLevelSchema),
			reason: Type.Optional(
				Type.String({
					description:
						"For complete: why the recurring task is finished and the loop should stop.",
				}),
			),
		}),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			currentCtx = ctx;
			const action = params.action?.trim();

			if (!action) {
				const prompt = params.prompt?.trim() ?? "";
				if (!prompt) {
					return textResult("Loop prompt must not be empty.", {}, true);
				}
				if (!params.interval) {
					return textResult(
						"Loop interval is required when creating a loop.",
						{},
						true,
					);
				}

				const everyMs = intervalToMs(
					params.interval.value,
					params.interval.unit,
				);
				if (!Number.isFinite(everyMs) || everyMs <= 0) {
					return textResult(
						"Loop interval must be a positive duration.",
						{},
						true,
					);
				}

				const modelOverride = toModelOverride(
					params.model,
					params.thinkingLevel,
				);
				const loop: Loop = {
					id: nextLoopId++,
					prompt,
					everyMs,
					createdAt: Date.now(),
					lastRunAt: null,
					modelOverride,
					timer: setInterval(() => {
						triggerLoop(loop.id);
					}, everyMs),
				};

				loops.set(loop.id, loop);
				return textResult(
					`Started loop #${loop.id} every ${formatInterval(loop.everyMs)}${formatModelOverride(loop.modelOverride, ctx.model?.id)}: ${loop.prompt}`,
					{
						action: "create",
						loopId: loop.id,
						loop: loopToDetails(loop),
					},
				);
			}

			if (action === "list") {
				return textResult(formatLoopStatus(), {
					action,
					loops: sortedLoops().map(loopToDetails),
				});
			}

			if (action === "stop") {
				if (params.loopId === undefined) {
					return textResult(
						"loopId is required for action 'stop'.",
						{ action },
						true,
					);
				}
				const loop = loops.get(params.loopId);
				if (!loop) {
					return textResult(
						`Loop #${params.loopId} not found.`,
						{ action, loopId: params.loopId },
						true,
					);
				}

				clearLoop(loop);
				return textResult(`Stopped loop #${loop.id}.`, {
					action,
					loopId: loop.id,
				});
			}

			if (action === "run_now") {
				if (params.loopId === undefined) {
					return textResult(
						"loopId is required for action 'run_now'.",
						{ action },
						true,
					);
				}
				const loop = loops.get(params.loopId);
				if (!loop) {
					return textResult(
						`Loop #${params.loopId} not found.`,
						{ action, loopId: params.loopId },
						true,
					);
				}

				const result = triggerLoop(loop.id);
				if (result === "busy") {
					return textResult(
						`Loop #${loop.id} was not triggered because Pi is busy right now.`,
						{ action, loopId: loop.id, started: false },
						true,
					);
				}

				if (result === "missing") {
					return textResult(
						`Loop #${params.loopId} not found.`,
						{ action, loopId: params.loopId },
						true,
					);
				}

				return textResult(`Triggered loop #${loop.id}.`, {
					action,
					loopId: loop.id,
					started: true,
				});
			}

			if (action === "stop_all") {
				const count = loops.size;
				clearAllLoops();
				return textResult(`Stopped ${count} loop${count === 1 ? "" : "s"}.`, {
					action,
					count,
				});
			}

			if (action === "complete") {
				if (activeLoopToolTargetId === null) {
					return textResult(
						"No active loop run to complete.",
						{ action, completed: false },
						true,
					);
				}

				const loop = loops.get(activeLoopToolTargetId);
				if (!loop) {
					activeLoopToolTargetId = null;
					return textResult(
						"Loop already stopped.",
						{ action, completed: false },
						true,
					);
				}

				const reason = params.reason?.trim();
				clearLoop(loop);
				return textResult(
					reason
						? `Completed loop #${loop.id}: ${reason}`
						: `Completed loop #${loop.id}.`,
					{
						action,
						loopId: loop.id,
						completed: true,
						reason,
					},
				);
			}

			const validActions = ["list", "stop", "run_now", "stop_all", "complete"];
			return textResult(
				`Unknown action: ${action}. Valid: ${validActions.join(", ")}. Omit action to create a loop.`,
				{ action },
				true,
			);
		},
	});
}
