import type {
	ExtensionAPI,
	ExtensionContext,
} from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";

type ThinkingLevel = "off" | "minimal" | "low" | "medium" | "high" | "xhigh";
type IntervalUnit = "seconds" | "minutes" | "hours" | "days";
type ScheduleType = "once" | "interval";

type ModelOverride = {
	query: string;
	thinkingLevel?: ThinkingLevel;
};

type Schedule = {
	id: number;
	type: ScheduleType;
	prompt: string;
	everyMs: number;
	createdAt: number;
	lastRunAt: number | null;
	timer: NodeJS.Timeout;
	modelOverride?: ModelOverride;
};

const SCHEDULE_TOOL = "schedule";

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

const schedules = new Map<number, Schedule>();

let nextScheduleId = 1;
let currentCtx: ExtensionContext | null = null;
let activeScheduleRunId: number | null = null;
let activeScheduleToolTargetId: number | null = null;
let activeScheduleRestore: {
	modelId?: string;
	provider?: string;
	thinkingLevel: ThinkingLevel;
} | null = null;
let restoringAfterScheduleRun = false;
let scheduleEnabled = false;
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

function syncScheduleToolActivation() {
	if (!piRef) return;
	const active = piRef.getActiveTools().filter((name) => name !== SCHEDULE_TOOL);
	if (!scheduleEnabled) {
		piRef.setActiveTools(active);
		return;
	}
	piRef.setActiveTools([...active, SCHEDULE_TOOL]);
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

function intervalToMs(value: number, unit: IntervalUnit): number {
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

function scheduleMessage(schedule: Schedule): string {
	const kind = schedule.type === "once" ? "one-shot schedule" : "automatic loop";
	const timing = schedule.type === "once" ? "once" : `every ${formatInterval(schedule.everyMs)}`;
	return [`[${kind} #${schedule.id}; ${timing}]`, schedule.prompt].join("\n\n");
}

function sortedSchedules(): Schedule[] {
	return [...schedules.values()].sort((a, b) => a.id - b.id);
}

function scheduleToDetails(schedule: Schedule) {
	return {
		id: schedule.id,
		type: schedule.type,
		prompt: schedule.prompt,
		everyMs: schedule.everyMs,
		createdAt: schedule.createdAt,
		lastRunAt: schedule.lastRunAt,
		modelOverride: schedule.modelOverride,
	};
}

function scheduleSummary(schedule: Schedule): string {
	const basis = schedule.lastRunAt ?? schedule.createdAt;
	const dueIn = formatRelative(Math.max(0, basis + schedule.everyMs - Date.now()));
	const lastRun = schedule.lastRunAt
		? `${formatRelative(Date.now() - schedule.lastRunAt)} ago`
		: "never";
	const timing = schedule.type === "once" ? `once · due ${dueIn}` : `every ${formatInterval(schedule.everyMs)} · next ${dueIn}`;
	return `#${schedule.id} ${timing} · last ${lastRun}${formatModelOverride(schedule.modelOverride, currentCtx?.model?.id)} · ${schedule.prompt}`;
}

function formatScheduleStatus(): string {
	const allSchedules = sortedSchedules();
	if (allSchedules.length === 0) return "No active schedules in this session.";
	return [
		`Active schedules (${allSchedules.length})`,
		...allSchedules.map(scheduleSummary),
	].join("\n");
}

function clearSchedule(schedule: Schedule) {
	if (schedule.type === "once") clearTimeout(schedule.timer);
	else clearInterval(schedule.timer);
	schedules.delete(schedule.id);
	if (activeScheduleRunId === schedule.id) activeScheduleRunId = null;
	if (activeScheduleToolTargetId === schedule.id) activeScheduleToolTargetId = null;
}

function clearAllSchedules() {
	for (const schedule of schedules.values()) {
		if (schedule.type === "once") clearTimeout(schedule.timer);
		else clearInterval(schedule.timer);
	}
	schedules.clear();
	activeScheduleRunId = null;
	activeScheduleToolTargetId = null;
}

function parseScheduleIdFromPrompt(prompt: string): number | null {
	const match = prompt.match(/^\[(?:automatic loop|one-shot schedule) #(\d+); [^\]]+\]/);
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

async function applyScheduleOverride(schedule: Schedule, ctx: ExtensionContext) {
	if (!schedule.modelOverride || !piRef) return;

	activeScheduleRestore = {
		modelId: ctx.model?.id,
		provider: ctx.model?.provider,
		thinkingLevel: piRef.getThinkingLevel() as ThinkingLevel,
	};

	if (schedule.modelOverride.query !== "current") {
		const model = await findModel(ctx, schedule.modelOverride.query);
		if (!model) {
			ctx.ui.notify(
				`Schedule #${schedule.id}: model not found: ${schedule.modelOverride.query}`,
				"warning",
			);
			activeScheduleRestore = null;
			return;
		}

		const success = await piRef.setModel(model);
		if (!success) {
			ctx.ui.notify(
				`Schedule #${schedule.id}: no API key for ${model.provider}/${model.id}`,
				"warning",
			);
			activeScheduleRestore = null;
			return;
		}
	}

	if (schedule.modelOverride.thinkingLevel) {
		piRef.setThinkingLevel(schedule.modelOverride.thinkingLevel);
	}
}

async function restoreAfterScheduleRun(ctx: ExtensionContext) {
	if (!piRef || !activeScheduleRestore || restoringAfterScheduleRun) return;
	const restore = activeScheduleRestore;
	activeScheduleRestore = null;
	restoringAfterScheduleRun = true;
	try {
		if (restore.provider && restore.modelId) {
			const model = ctx.modelRegistry.find(restore.provider, restore.modelId);
			if (model) {
				await piRef.setModel(model);
			}
		}
		piRef.setThinkingLevel(restore.thinkingLevel);
	} finally {
		restoringAfterScheduleRun = false;
	}
}

function triggerSchedule(scheduleId: number): "started" | "busy" | "missing" {
	const schedule = schedules.get(scheduleId);
	const ctx = currentCtx;
	if (!schedule || !ctx) return "missing";
	if (activeScheduleRunId !== null || !ctx.isIdle()) return "busy";

	schedule.lastRunAt = Date.now();
	activeScheduleRunId = schedule.id;
	activeScheduleToolTargetId = schedule.id;
	ctx.ui.notify(
		`Running schedule #${schedule.id}: ${schedule.prompt}${formatModelOverride(schedule.modelOverride, ctx.model?.id)}`,
		"info",
	);
	if (schedule.type === "once") activeScheduleToolTargetId = null;
	piRef?.sendUserMessage(scheduleMessage(schedule));
	return "started";
}

function createTimer(schedule: Schedule): NodeJS.Timeout {
	if (schedule.type === "interval") {
		return setInterval(() => {
			triggerSchedule(schedule.id);
		}, schedule.everyMs);
	}

	return setTimeout(() => {
		const result = triggerSchedule(schedule.id);
		if (result === "busy") {
			const retry = schedules.get(schedule.id);
			if (retry) retry.timer = createTimer({ ...retry, everyMs: 30_000 });
		}
	}, schedule.everyMs);
}

export default function (pi: ExtensionAPI) {
	piRef = pi;

	pi.on("session_start", async (_event, ctx) => {
		currentCtx = ctx;
		activeScheduleRestore = null;
		scheduleEnabled = false;
		clearAllSchedules();
		syncScheduleToolActivation();
	});

	pi.on("session_shutdown", async () => {
		clearAllSchedules();
		currentCtx = null;
		activeScheduleRestore = null;
		scheduleEnabled = false;
		syncScheduleToolActivation();
	});

	pi.on("before_agent_start", async (event, ctx) => {
		currentCtx = ctx;
		const scheduleId = parseScheduleIdFromPrompt(event.prompt);
		if (scheduleId === null) return;
		const schedule = schedules.get(scheduleId);
		if (schedule) await applyScheduleOverride(schedule, ctx);
		return {
			systemPrompt: `${event.systemPrompt}\n\nThis is a scheduled run for schedule #${scheduleId}. If this is a recurring loop and the recurring task has finished, call the schedule tool with { action: "complete" } instead of continuing the loop.`,
		};
	});

	pi.on("agent_end", async (_event, ctx) => {
		currentCtx = ctx;
		const finishedSchedule =
			activeScheduleRunId === null ? null : schedules.get(activeScheduleRunId);
		activeScheduleRunId = null;
		activeScheduleToolTargetId = null;
		if (finishedSchedule?.type === "once") clearSchedule(finishedSchedule);
		await restoreAfterScheduleRun(ctx);
	});

	function forwardScheduleRequest(input: string, ctx: ExtensionContext, prefix: string) {
		scheduleEnabled = true;
		syncScheduleToolActivation();
		ctx.ui.notify("Schedule tool enabled for this session", "info");
		const message = `${prefix}: ${input}`;
		if (ctx.isIdle()) pi.sendUserMessage(message);
		else pi.sendUserMessage(message, { deliverAs: "followUp" });
	}

	pi.registerCommand("schedule", {
		description: "Enable the schedule tool and forward a scheduling request",
		handler: async (args, ctx) => {
			currentCtx = ctx;
			const input = args.trim();
			if (!input) {
				ctx.ui.notify(
					"Usage: /schedule <natural language> (examples: /schedule check this in 30m, /schedule check CI every 5m)",
					"info",
				);
				return;
			}
			forwardScheduleRequest(input, ctx, "Use the schedule tool for this request");
		},
	});

	pi.registerCommand("loop", {
		description: "Alias for /schedule for recurring loop requests",
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
			forwardScheduleRequest(input, ctx, "Use the schedule tool to create a recurring loop for this request");
		},
	});

	pi.registerTool({
		name: SCHEDULE_TOOL,
		label: "Schedule",
		description: `Create or manage scheduled prompts in the current session.

	CREATE (omit action):
	• { type: "once", prompt, delay: { value, unit } } - run once later
	• { type: "interval", prompt, interval: { value, unit } } - recurring loop
	• Optional overrides: { model, thinkingLevel }

	MANAGEMENT (set action):
	• { action: "list" } - list active schedules
	• { action: "stop", scheduleId } - stop one schedule
	• { action: "run_now", scheduleId } - trigger one schedule immediately
	• { action: "stop_all" } - stop all schedules
	• { action: "complete", reason? } - stop the currently running recurring loop because the task is finished`,
		parameters: Type.Object({
			action: Type.Optional(
				Type.String({
					description:
						"Schedule action: omit to create, or set to 'list', 'stop', 'run_now', 'stop_all', or 'complete'.",
				}),
			),
			type: Type.Optional(
				Type.Union([Type.Literal("once"), Type.Literal("interval")]),
			),
			prompt: Type.Optional(
				Type.String({
					description:
						"For create: the prompt to send, without the scheduling phrase.",
				}),
			),
			delay: Type.Optional(
				Type.Object({
					value: Type.Number({ exclusiveMinimum: 0 }),
					unit: intervalUnitSchema,
				}),
			),
			interval: Type.Optional(
				Type.Object({
					value: Type.Number({ exclusiveMinimum: 0 }),
					unit: intervalUnitSchema,
				}),
			),
			scheduleId: Type.Optional(
				Type.Number({
					description:
						"For stop or run_now: the schedule ID returned by list or create.",
				}),
			),
			loopId: Type.Optional(
				Type.Number({
					description: "Backward-compatible alias for scheduleId.",
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
			const scheduleId = params.scheduleId ?? params.loopId;

			if (!action) {
				const prompt = params.prompt?.trim() ?? "";
				if (!prompt) return textResult("Schedule prompt must not be empty.", {}, true);

				const type = params.type ?? (params.delay ? "once" : "interval");
				const timing = type === "once" ? params.delay : params.interval;
				if (!timing) {
					return textResult(
						type === "once"
							? "Schedule delay is required for one-shot schedules."
							: "Schedule interval is required for recurring loops.",
						{},
						true,
					);
				}

				const everyMs = intervalToMs(timing.value, timing.unit);
				if (!Number.isFinite(everyMs) || everyMs <= 0) {
					return textResult("Schedule duration must be positive.", {}, true);
				}

				const modelOverride = toModelOverride(params.model, params.thinkingLevel);
				const schedule: Schedule = {
					id: nextScheduleId++,
					type,
					prompt,
					everyMs,
					createdAt: Date.now(),
					lastRunAt: null,
					modelOverride,
					timer: undefined as unknown as NodeJS.Timeout,
				};
				schedule.timer = createTimer(schedule);

				schedules.set(schedule.id, schedule);
				const started = type === "once" ? "Scheduled" : "Started loop";
				const timingText = type === "once" ? `in ${formatInterval(everyMs)}` : `every ${formatInterval(everyMs)}`;
				return textResult(
					`${started} #${schedule.id} ${timingText}${formatModelOverride(schedule.modelOverride, ctx.model?.id)}: ${schedule.prompt}`,
					{
						action: "create",
						scheduleId: schedule.id,
						loopId: schedule.type === "interval" ? schedule.id : undefined,
						schedule: scheduleToDetails(schedule),
					},
				);
			}

			if (action === "list") {
				return textResult(formatScheduleStatus(), {
					action,
					schedules: sortedSchedules().map(scheduleToDetails),
				});
			}

			if (action === "stop") {
				if (scheduleId === undefined) {
					return textResult("scheduleId is required for action 'stop'.", { action }, true);
				}
				const schedule = schedules.get(scheduleId);
				if (!schedule) {
					return textResult(`Schedule #${scheduleId} not found.`, { action, scheduleId }, true);
				}

				clearSchedule(schedule);
				return textResult(`Stopped schedule #${schedule.id}.`, { action, scheduleId: schedule.id });
			}

			if (action === "run_now") {
				if (scheduleId === undefined) {
					return textResult("scheduleId is required for action 'run_now'.", { action }, true);
				}
				const schedule = schedules.get(scheduleId);
				if (!schedule) {
					return textResult(`Schedule #${scheduleId} not found.`, { action, scheduleId }, true);
				}

				const result = triggerSchedule(schedule.id);
				if (result === "busy") {
					return textResult(
						`Schedule #${schedule.id} was not triggered because Pi is busy right now.`,
						{ action, scheduleId: schedule.id, started: false },
						true,
					);
				}

				if (result === "missing") {
					return textResult(`Schedule #${scheduleId} not found.`, { action, scheduleId }, true);
				}

				return textResult(`Triggered schedule #${schedule.id}.`, {
					action,
					scheduleId: schedule.id,
					started: true,
				});
			}

			if (action === "stop_all") {
				const count = schedules.size;
				clearAllSchedules();
				return textResult(`Stopped ${count} schedule${count === 1 ? "" : "s"}.`, {
					action,
					count,
				});
			}

			if (action === "complete") {
				if (activeScheduleToolTargetId === null) {
					return textResult("No active recurring loop run to complete.", { action, completed: false }, true);
				}

				const schedule = schedules.get(activeScheduleToolTargetId);
				if (!schedule) {
					activeScheduleToolTargetId = null;
					return textResult("Schedule already stopped.", { action, completed: false }, true);
				}

				const reason = params.reason?.trim();
				clearSchedule(schedule);
				return textResult(
					reason
						? `Completed loop #${schedule.id}: ${reason}`
						: `Completed loop #${schedule.id}.`,
					{ action, scheduleId: schedule.id, completed: true, reason },
				);
			}

			const validActions = ["list", "stop", "run_now", "stop_all", "complete"];
			return textResult(
				`Unknown action: ${action}. Valid: ${validActions.join(", ")}. Omit action to create a schedule.`,
				{ action },
				true,
			);
		},
	});
}
