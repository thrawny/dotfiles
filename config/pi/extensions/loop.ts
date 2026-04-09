import type {
	ExtensionAPI,
	ExtensionContext,
} from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";

type ThinkingLevel = "off" | "minimal" | "low" | "medium" | "high" | "xhigh";

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

const loops = new Map<number, Loop>();

let nextLoopId = 1;
let currentCtx: ExtensionContext | null = null;
let activeLoopRunId: number | null = null;
let piRef: ExtensionAPI | null = null;
let restoringAfterLoopRun = false;
let loopCompleteToolRegistered = false;
let activeLoopToolTargetId: number | null = null;
let activeLoopToolPreviousTools: string[] | null = null;
let activeLoopRestore: {
	modelId?: string;
	provider?: string;
	thinkingLevel: ThinkingLevel;
} | null = null;

function clearLoop(loop: Loop) {
	clearInterval(loop.timer);
	loops.delete(loop.id);
}

function unregisterLoopToolIfUnused() {
	if (!piRef || loops.size > 0 || !loopCompleteToolRegistered) return;
	setLoopToolActive(false);
	piRef.setActiveTools(
		piRef.getActiveTools().filter((name) => name !== "loop_complete"),
	);
	loopCompleteToolRegistered = false;
}

function clearAllLoops() {
	for (const loop of loops.values()) {
		clearInterval(loop.timer);
	}
	loops.clear();
	activeLoopRunId = null;
	unregisterLoopToolIfUnused();
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

function parseDuration(input: string): { ms: number; rest: string } | null {
	const match = input.match(
		/^(\d+)\s*(s|sec|secs|second|seconds|m|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days)\b\s*(.*)$/i,
	);
	if (!match) return null;

	const value = Number.parseInt(match[1], 10);
	if (!Number.isFinite(value) || value <= 0) return null;

	const unit = match[2].toLowerCase();
	const rest = match[3].trim();

	const multiplier = unit.startsWith("s")
		? 1000
		: unit.startsWith("m")
			? 60_000
			: unit.startsWith("h")
				? 3_600_000
				: 86_400_000;

	return {
		ms: value * multiplier,
		rest,
	};
}

function parseThinkingLevel(input: string): {
	modelQuery: string;
	thinkingLevel?: ThinkingLevel;
} {
	const trimmed = input.trim();
	const bareLevels: Record<string, ThinkingLevel> = {
		off: "off",
		minimal: "minimal",
		low: "low",
		medium: "medium",
		high: "high",
		xhigh: "xhigh",
	};
	const bare = bareLevels[trimmed.toLowerCase()];
	if (bare) {
		return { modelQuery: "", thinkingLevel: bare };
	}
	if (/^no\s+thinking$/i.test(trimmed)) {
		return { modelQuery: "", thinkingLevel: "off" };
	}

	const patterns: Array<[RegExp, ThinkingLevel]> = [
		[/^(.*?)\s+no\s+thinking$/i, "off"],
		[/^(.*?)\s+thinking\s+off$/i, "off"],
		[/^(.*?)\s+off$/i, "off"],
		[/^(.*?)\s+minimal\s+thinking$/i, "minimal"],
		[/^(.*?)\s+minimal$/i, "minimal"],
		[/^(.*?)\s+low\s+thinking$/i, "low"],
		[/^(.*?)\s+low$/i, "low"],
		[/^(.*?)\s+medium\s+thinking$/i, "medium"],
		[/^(.*?)\s+medium$/i, "medium"],
		[/^(.*?)\s+high\s+thinking$/i, "high"],
		[/^(.*?)\s+high$/i, "high"],
		[/^(.*?)\s+xhigh\s+thinking$/i, "xhigh"],
		[/^(.*?)\s+xhigh$/i, "xhigh"],
	];

	for (const [pattern, thinkingLevel] of patterns) {
		const match = trimmed.match(pattern);
		if (match) {
			return {
				modelQuery: match[1].trim(),
				thinkingLevel,
			};
		}
	}

	return { modelQuery: trimmed };
}

function parseModelOverride(input: string): ModelOverride | undefined {
	const trimmed = input.trim();
	if (!trimmed) return undefined;

	const parsed = parseThinkingLevel(trimmed);
	if (!parsed.modelQuery) {
		if (!parsed.thinkingLevel) return undefined;
		return {
			query: "current",
			thinkingLevel: parsed.thinkingLevel,
		};
	}
	return {
		query: parsed.modelQuery,
		thinkingLevel: parsed.thinkingLevel,
	};
}

function parseQuotedLoopSpec(
	input: string,
): { ms: number; prompt: string; modelOverride?: ModelOverride } | null {
	const match = input.match(/^(\S+)\s*(.*?)\s+(["'])([\s\S]*?)\3$/);
	if (!match) return null;

	const duration = parseDuration(match[1]);
	if (!duration || duration.rest) return null;

	const middle = match[2].trim();
	const prompt = match[4].trim();
	if (!prompt) return null;

	const modelOverride = middle ? parseModelOverride(middle) : undefined;
	if (middle && !modelOverride) return null;

	return {
		ms: duration.ms,
		prompt,
		modelOverride,
	};
}

function parseSeparatedLoopSpec(
	input: string,
): { ms: number; prompt: string; modelOverride?: ModelOverride } | null {
	const parts = input.split(/\s+--\s+/);
	if (parts.length !== 2) return null;

	const left = parts[0].trim();
	const prompt = parts[1].trim();
	if (!left || !prompt) return null;

	const leftMatch = left.match(/^(\S+)(?:\s+(.*))?$/);
	if (!leftMatch) return null;

	const duration = parseDuration(leftMatch[1]);
	if (!duration || duration.rest) return null;

	const middle = (leftMatch[2] ?? "").trim();
	const modelOverride = middle ? parseModelOverride(middle) : undefined;
	if (middle && !modelOverride) return null;

	return {
		ms: duration.ms,
		prompt,
		modelOverride,
	};
}

function parseNaturalLoopSpec(
	input: string,
): { ms: number; prompt: string; modelOverride?: ModelOverride } | null {
	const usingMatch = input.match(/^(.*?)\s+(?:using|with)\s+(.+)$/i);
	const body = usingMatch ? usingMatch[1].trim() : input.trim();
	const modelOverride = usingMatch
		? parseModelOverride(usingMatch[2])
		: undefined;
	if (usingMatch && !modelOverride) return null;

	if (body.startsWith("every ")) {
		const parsed = parseDuration(body.slice(6).trim());
		if (!parsed?.rest) return null;
		return { ms: parsed.ms, prompt: parsed.rest, modelOverride };
	}

	const match = body.match(/^(.*)\s+every\s+(.+)$/i);
	if (!match) return null;

	const prompt = match[1].trim();
	const parsed = parseDuration(match[2].trim());
	if (!prompt || !parsed || parsed.rest) return null;
	return { ms: parsed.ms, prompt, modelOverride };
}

function parseLoopSpec(
	input: string,
): { ms: number; prompt: string; modelOverride?: ModelOverride } | null {
	return (
		parseQuotedLoopSpec(input) ??
		parseSeparatedLoopSpec(input) ??
		parseNaturalLoopSpec(input)
	);
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

function loopSummary(loop: Loop): string {
	const dueIn = formatRelative(
		Math.max(0, (loop.lastRunAt ?? loop.createdAt) + loop.everyMs - Date.now()),
	);
	const lastRun = loop.lastRunAt
		? `${formatRelative(Date.now() - loop.lastRunAt)} ago`
		: "never";
	return `#${loop.id} every ${formatInterval(loop.everyMs)} · next ${dueIn} · last ${lastRun}${formatModelOverride(loop.modelOverride, currentCtx?.model?.id)} · ${loop.prompt}`;
}

function showLoopStatus(ctx: ExtensionContext) {
	const allLoops = sortedLoops();
	if (allLoops.length === 0) {
		ctx.ui.notify("No active loops in this session", "info");
		return;
	}

	ctx.ui.notify(
		[`Active loops (${allLoops.length})`, ...allLoops.map(loopSummary)].join(
			"\n",
		),
		"info",
	);
}

function markLoopDue(loopId: number) {
	const loop = loops.get(loopId);
	const ctx = currentCtx;
	if (!loop || !ctx || activeLoopRunId !== null || !ctx.isIdle()) return;
	loop.lastRunAt = Date.now();
	activeLoopRunId = loop.id;
	activeLoopToolTargetId = loop.id;
	setLoopToolActive(true);
	ctx.ui.notify(
		`Running loop #${loop.id}: ${loop.prompt}${formatModelOverride(loop.modelOverride, ctx.model?.id)}`,
		"info",
	);
	piRef?.sendUserMessage(loopMessage(loop));
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

function parseLoopIdFromPrompt(prompt: string): number | null {
	const match = prompt.match(/^\[automatic loop #(\d+); every [^\]]+\]/);
	if (!match) return null;
	const id = Number.parseInt(match[1], 10);
	return Number.isFinite(id) ? id : null;
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

function parseLoopId(value: string): number | null {
	const id = Number.parseInt(value, 10);
	if (!Number.isFinite(id)) return null;
	return id;
}

function ensureLoopToolRegistered() {
	if (!piRef || loopCompleteToolRegistered) return;
	loopCompleteToolRegistered = true;

	piRef.registerTool({
		name: "loop_complete",
		label: "Complete Loop",
		description: "Stop the currently running loop when its task is complete.",
		parameters: Type.Object({
			reason: Type.Optional(
				Type.String({ description: "Why the loop is complete" }),
			),
		}),
		async execute(_toolCallId, params, _signal, _onUpdate, _ctx) {
			if (activeLoopToolTargetId === null) {
				return {
					content: [{ type: "text", text: "No active loop to complete." }],
					details: { completed: false },
				};
			}

			const loop = loops.get(activeLoopToolTargetId);
			if (!loop) {
				activeLoopToolTargetId = null;
				return {
					content: [{ type: "text", text: "Loop already stopped." }],
					details: { completed: false },
				};
			}

			clearLoop(loop);
			unregisterLoopToolIfUnused();
			activeLoopRunId = null;
			const reason = params.reason?.trim();
			return {
				content: [
					{
						type: "text",
						text: reason
							? `Completed loop #${loop.id}: ${reason}`
							: `Completed loop #${loop.id}.`,
					},
				],
				details: { loopId: loop.id, completed: true, reason },
			};
		},
	});
}

function setLoopToolActive(enabled: boolean) {
	if (!piRef) return;
	const toolName = "loop_complete";
	const active = piRef.getActiveTools();
	const hasTool = active.includes(toolName);

	if (enabled) {
		ensureLoopToolRegistered();
		const refreshedActive = piRef.getActiveTools();
		if (refreshedActive.includes(toolName)) return;
		activeLoopToolPreviousTools = refreshedActive;
		piRef.setActiveTools([...refreshedActive, toolName]);
		return;
	}

	if (!hasTool) {
		activeLoopToolPreviousTools = null;
		return;
	}

	if (activeLoopToolPreviousTools) {
		piRef.setActiveTools(activeLoopToolPreviousTools);
	} else {
		piRef.setActiveTools(active.filter((name) => name !== toolName));
	}
	activeLoopToolPreviousTools = null;
}

function helpText(): string {
	return [
		"Loop commands:",
		'/loop <duration> [model|thinking] "<prompt>"',
		"/loop <duration> [model|thinking] -- <prompt>",
		"/loop <prompt> every <duration>",
		"/loop every <duration> <prompt>",
		"/loop <prompt> every <duration> using|with <model>",
		"/loop list",
		"/loop now <id>",
		"/loop stop <id>",
		"/loop stop all",
		"",
		"Examples:",
		'/loop 10s "say hi"',
		"/loop 10s off -- say hi",
		"/loop 5m off -- check memory growth and notify using notify cli",
		'/loop 5m gpt-5 off "check CI status"',
		"/loop say hi every 10s",
		"/loop check CI status every 5m with no thinking",
	].join("\n");
}

export default function (pi: ExtensionAPI) {
	piRef = pi;

	pi.on("session_start", async (_event, ctx) => {
		clearAllLoops();
		currentCtx = ctx;
		activeLoopRestore = null;
		activeLoopToolTargetId = null;
		setLoopToolActive(false);
	});

	pi.on("session_shutdown", async () => {
		clearAllLoops();
		currentCtx = null;
		activeLoopRestore = null;
		activeLoopToolTargetId = null;
		setLoopToolActive(false);
	});

	pi.on("before_agent_start", async (event, ctx) => {
		currentCtx = ctx;
		const loopId = parseLoopIdFromPrompt(event.prompt);
		if (loopId === null) return;
		const loop = loops.get(loopId);
		if (!loop) return;
		await applyLoopOverride(loop, ctx);
		return {
			systemPrompt: `${event.systemPrompt}\n\nThis is a recurring loop run for loop #${loop.id}. If the user's task is complete and the loop should stop, call the loop_complete tool instead of continuing the loop.`,
		};
	});

	pi.on("agent_end", async (_event, ctx) => {
		currentCtx = ctx;
		activeLoopRunId = null;
		await restoreAfterLoopRun(ctx);
		activeLoopToolTargetId = null;
		setLoopToolActive(false);
	});

	pi.registerCommand("loop", {
		description:
			"Run periodic prompts inside the current session while Pi stays open",
		handler: async (args, ctx) => {
			currentCtx = ctx;
			const input = args.trim();

			if (!input || input === "help") {
				ctx.ui.notify(helpText(), "info");
				return;
			}

			if (input === "list" || input === "status") {
				showLoopStatus(ctx);
				return;
			}

			if (input === "stop all") {
				const count = loops.size;
				clearAllLoops();
				ctx.ui.notify(`Stopped ${count} loop${count === 1 ? "" : "s"}`, "info");
				return;
			}

			if (input.startsWith("stop ")) {
				const id = parseLoopId(input.slice(5).trim());
				if (id === null) {
					ctx.ui.notify("Usage: /loop stop <id>", "warning");
					return;
				}
				const loop = loops.get(id);
				if (!loop) {
					ctx.ui.notify(`Loop #${id} not found`, "warning");
					return;
				}
				clearLoop(loop);
				unregisterLoopToolIfUnused();
				if (activeLoopRunId === id) activeLoopRunId = null;
				ctx.ui.notify(`Stopped loop #${id}`, "info");
				return;
			}

			if (input.startsWith("now ")) {
				const id = parseLoopId(input.slice(4).trim());
				if (id === null) {
					ctx.ui.notify("Usage: /loop now <id>", "warning");
					return;
				}
				const loop = loops.get(id);
				if (!loop) {
					ctx.ui.notify(`Loop #${id} not found`, "warning");
					return;
				}
				markLoopDue(id);
				ctx.ui.notify(`Triggered loop #${id}`, "info");
				return;
			}

			const spec = parseLoopSpec(input);
			if (!spec) {
				ctx.ui.notify(
					"Usage: /loop <duration> [model|thinking] -- <prompt> (example: /loop 5m off -- check memory growth)",
					"warning",
				);
				return;
			}

			const loop: Loop = {
				id: nextLoopId++,
				prompt: spec.prompt,
				everyMs: spec.ms,
				createdAt: Date.now(),
				lastRunAt: null,
				modelOverride: spec.modelOverride,
				timer: setInterval(() => {
					markLoopDue(loop.id);
				}, spec.ms),
			};

			loops.set(loop.id, loop);
			ensureLoopToolRegistered();
			ctx.ui.notify(
				`Started loop #${loop.id} every ${formatInterval(loop.everyMs)}${formatModelOverride(loop.modelOverride, ctx.model?.id)}: ${loop.prompt}`,
				"info",
			);
		},
	});
}
