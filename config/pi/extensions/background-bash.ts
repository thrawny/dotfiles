import { randomUUID } from "node:crypto";
import { mkdir, readdir, rm, stat, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, join } from "node:path";
import {
	createBashToolDefinition,
	SettingsManager,
	truncateTail,
	type BashToolOptions,
	type ExecResult,
	type ExtensionAPI,
	type ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { Type } from "@sinclair/typebox";

const COMPLETION_MESSAGE_TYPE = "background-bash-finished";
const TIMEOUT_MESSAGE_TYPE = "background-bash-timeout";
const STATUS_ID = "background-bash";
const TASK_ENTRY_TYPE = "background-bash-task";
const EMPTY_TURN_ENTRY_TYPE = "background-bash-empty-turn";
const EMPTY_TURN_NUDGE =
	"The final background task completion above received an empty response. React to it now: continue the work it unblocks, or state the outcome and current status.";
const FINAL_WAKEUP_NUDGE =
	"Extension-generated wake-up, not a new user instruction: react to the background completion notification above. Keep working; if everything is already done, state the final status.";
const OUTPUT_MAX_BYTES = 12 * 1024;
const OUTPUT_MAX_LINES = 100;
const COMPLETION_BATCH_DELAY_MS = 250;
const COMPLETION_BATCH_MAX_TASKS = 16;
const MAX_FOREGROUND_TIMEOUT_SECONDS = 10 * 60;
const SESSION_RETENTION_SECONDS = 12 * 60 * 60;

const bashParameters = Type.Object({
	command: Type.String({ description: "Bash command to execute" }),
	timeout: Type.Optional(
		Type.Number({
			minimum: 1,
			description:
				"Foreground: stop the command after this many seconds; requests above 600 seconds automatically run in the background. Background: wake the agent after this many seconds if the command is still running, without stopping it.",
		}),
	),
	background: Type.Optional(
		Type.Boolean({
			description:
				"Run via a detached zmx session and return immediately. The agent is notified when the command finishes.",
		}),
	),
});

function slug(value: string, fallback: string, maxLength: number): string {
	const normalized = value
		.toLowerCase()
		.replace(/[^a-z0-9]+/g, "-")
		.replace(/^-+|-+$/g, "")
		.slice(0, maxLength)
		.replace(/-+$/g, "");
	return normalized || fallback;
}

function unquoteShellWord(word: string): string {
	if (
		word.length >= 2 &&
		((word.startsWith("'") && word.endsWith("'")) ||
			(word.startsWith('"') && word.endsWith('"')))
	) {
		return word.slice(1, -1);
	}
	return word;
}

function backgroundCommandName(command: string): string {
	const launchLine = command.trimStart().split("\n", 1)[0] ?? "";
	const segments = launchLine.split(/\s*(?:\|\||&&|[|;])\s*/);

	for (const segment of segments) {
		const words = segment.match(/'[^']*'|"[^"]*"|\S+/g)?.map(unquoteShellWord);
		if (!words || words.length < 2) continue;

		const executable = basename(words[0] ?? "");
		if (!["bash", "dash", "sh", "zsh"].includes(executable)) continue;

		const args = words.slice(1);
		if (args.includes("-c")) continue;
		const script = args.find((argument) => !argument.startsWith("-"));
		if (!script) continue;

		const pathParts = script.split("/");
		const skillsIndex = pathParts.lastIndexOf("skills");
		const skillName = pathParts[skillsIndex + 1];
		if (
			skillsIndex >= 0 &&
			skillName &&
			pathParts[skillsIndex + 2] === "scripts"
		) {
			return slug(skillName, "task", 20);
		}

		const scriptName = basename(script).replace(/\.(?:ba|da|z)?sh$/i, "");
		return slug(scriptName, "task", 20);
	}

	return slug(launchLine.split(/\s+/, 1)[0] ?? "", "task", 20);
}

export function backgroundSessionName(
	toolCallId: string,
	command: string,
): string {
	const commandName = backgroundCommandName(command);
	const normalizedCallId = toolCallId
		.toLowerCase()
		.replace(/[^a-z0-9]+/g, "-")
		.replace(/^-+|-+$/g, "");
	const callId = normalizedCallId.slice(-20) || "call";
	const entropy = randomUUID().replaceAll("-", "").slice(0, 12);
	return `pi-bg-${commandName}-${callId}-${entropy}`;
}

function configuredBash(cwd: string) {
	const settings = SettingsManager.create(cwd);
	const options: BashToolOptions = {
		commandPrefix: settings.getShellCommandPrefix(),
		shellPath: settings.getShellPath(),
	};
	return {
		commandPrefix: options.commandPrefix,
		shellPath: options.shellPath ?? "bash",
		tool: createBashToolDefinition(cwd, options),
	};
}

function execFailure(result: ExecResult): string {
	return [result.stderr.trim(), result.stdout.trim()]
		.filter(Boolean)
		.join("\n")
		.trim();
}

type ZmxSession = {
	name: string;
	clients?: number;
	ended?: number;
	err?: string;
};

// zmx documents the default list output as stable tab-separated key=value
// fields. We only consume task lifecycle fields and ignore cwd/cmd/labels.
function parseZmxSessions(output: string): ZmxSession[] {
	const sessions: ZmxSession[] = [];
	for (const line of output.split("\n")) {
		const fields = new Map<string, string>();
		for (const item of line.split("\t")) {
			const separator = item.indexOf("=");
			if (separator < 0) continue;
			const key = item
				.slice(0, separator)
				.trim()
				.replace(/^→\s*/, "");
			fields.set(key, item.slice(separator + 1));
		}

		const name = fields.get("name");
		if (!name) continue;
		const clients = Number(fields.get("clients"));
		const ended = Number(fields.get("ended"));
		sessions.push({
			name,
			clients: Number.isSafeInteger(clients) ? clients : undefined,
			ended: Number.isSafeInteger(ended) ? ended : undefined,
			err: fields.get("err"),
		});
	}
	return sessions;
}

function staleBackgroundSessions(output: string, nowSeconds: number): string[] {
	const cutoff = nowSeconds - SESSION_RETENTION_SECONDS;

	return parseZmxSessions(output)
		.filter(
			(session) =>
				session.name.startsWith("pi-bg-") &&
				session.clients === 0 &&
				// `ended` is absent while a task is still running.
				session.ended !== undefined &&
				session.ended <= cutoff,
		)
		.map((session) => session.name);
}

async function pruneOldBackgroundSessions(
	pi: ExtensionAPI,
	cwd: string,
): Promise<void> {
	try {
		const list = await pi.exec("zmx", ["list"], { cwd });
		if (list.code !== 0) return;

		const stale = staleBackgroundSessions(
			list.stdout,
			Math.floor(Date.now() / 1000),
		);
		if (stale.length > 0) {
			await pi.exec("zmx", ["kill", ...stale], { cwd });
		}
	} catch {
		// Cleanup is opportunistic and must not prevent a new command from starting.
	}

	await pruneOldControlScripts();
}

// Resolved per call so tests can redirect writes with XDG_CACHE_HOME.
function controlScriptDir(): string {
	const cacheHome = process.env.XDG_CACHE_HOME || join(homedir(), ".cache");
	return join(cacheHome, "pi", "background-bash");
}

async function pruneOldControlScripts(): Promise<void> {
	const dir = controlScriptDir();
	let entries: string[];
	try {
		entries = await readdir(dir);
	} catch {
		// The directory only exists once a background command has run.
		return;
	}

	const cutoff = Date.now() - SESSION_RETENTION_SECONDS * 1000;
	await Promise.all(
		entries.map(async (entry) => {
			const path = join(dir, entry);
			try {
				const info = await stat(path);
				if (info.mtimeMs <= cutoff) await rm(path, { force: true });
			} catch {
				// A concurrent launch may have pruned the same file already.
			}
		}),
	);
}

type OutputMarkers = { start: string; end: string };

type AssistantRunMessage = {
	role: "assistant";
	stopReason: string;
	content: Array<{ type: string; text?: string }>;
};

function lastAssistantMessage(
	messages: unknown[],
): AssistantRunMessage | undefined {
	for (let index = messages.length - 1; index >= 0; index--) {
		const message = messages[index] as Partial<AssistantRunMessage> | null;
		if (
			typeof message === "object" &&
			message !== null &&
			message.role === "assistant" &&
			Array.isArray(message.content)
		) {
			return message as AssistantRunMessage;
		}
	}
	return undefined;
}

function isSilentStop(message: AssistantRunMessage): boolean {
	if (message.stopReason !== "stop") return false;
	return !message.content.some(
		(block) =>
			block.type === "toolCall" ||
			(block.type === "text" && (block.text ?? "").trim() !== ""),
	);
}

type NotificationState = "none" | "pending" | "sent";

type CompletionSnapshot = {
	exitCode: number;
	durationMs: number;
	output: string;
};

type TimeoutSnapshot = {
	durationMs: number;
	output: string;
};

type BackgroundTask = {
	version: 2;
	state: "running" | "finished";
	sessionName: string;
	command: string;
	cwd: string;
	startedAt: number;
	shellPath: string;
	markers: OutputMarkers;
	timeoutSeconds?: number;
	timeout?: TimeoutSnapshot;
	timeoutNotification: NotificationState;
	completion?: CompletionSnapshot;
	completionNotification: NotificationState;
	completionWake: NotificationState;
};

function notificationState(value: unknown): value is NotificationState {
	return value === "none" || value === "pending" || value === "sent";
}

function backgroundTask(value: unknown): BackgroundTask | undefined {
	if (typeof value !== "object" || value === null) return undefined;
	const data = value as Record<string, unknown>;
	const markers = data.markers;
	if (
		(data.version !== 1 && data.version !== 2) ||
		(data.state !== "running" && data.state !== "finished") ||
		typeof data.sessionName !== "string" ||
		typeof data.command !== "string" ||
		typeof data.cwd !== "string" ||
		typeof data.startedAt !== "number" ||
		!Number.isFinite(data.startedAt) ||
		typeof data.shellPath !== "string" ||
		typeof markers !== "object" ||
		markers === null ||
		typeof (markers as Record<string, unknown>).start !== "string" ||
		typeof (markers as Record<string, unknown>).end !== "string" ||
		(data.timeoutSeconds !== undefined &&
			(typeof data.timeoutSeconds !== "number" ||
				!Number.isFinite(data.timeoutSeconds)))
	) {
		return undefined;
	}

	if (data.version === 1) {
		return {
			version: 2,
			state: data.state,
			sessionName: data.sessionName,
			command: data.command,
			cwd: data.cwd,
			startedAt: data.startedAt,
			shellPath: data.shellPath,
			markers: markers as OutputMarkers,
			timeoutSeconds: data.timeoutSeconds as number | undefined,
			timeoutNotification: data.timeoutNotified === true ? "sent" : "none",
			completionNotification: data.state === "finished" ? "sent" : "none",
			completionWake: "none",
		};
	}

	const timeout = data.timeout as Record<string, unknown> | null | undefined;
	const completion = data.completion as
		| Record<string, unknown>
		| null
		| undefined;
	if (
		!notificationState(data.timeoutNotification) ||
		(timeout !== undefined &&
			(timeout === null ||
				typeof timeout.durationMs !== "number" ||
				!Number.isFinite(timeout.durationMs) ||
				typeof timeout.output !== "string")) ||
		!notificationState(data.completionNotification) ||
		!notificationState(data.completionWake) ||
		(completion !== undefined &&
			(completion === null ||
				typeof completion.exitCode !== "number" ||
				!Number.isFinite(completion.exitCode) ||
				typeof completion.durationMs !== "number" ||
				!Number.isFinite(completion.durationMs) ||
				typeof completion.output !== "string"))
	) {
		return undefined;
	}

	return {
		version: 2,
		state: data.state,
		sessionName: data.sessionName,
		command: data.command,
		cwd: data.cwd,
		startedAt: data.startedAt,
		shellPath: data.shellPath,
		markers: markers as OutputMarkers,
		timeoutSeconds: data.timeoutSeconds as number | undefined,
		timeout: timeout as TimeoutSnapshot | undefined,
		timeoutNotification: data.timeoutNotification,
		completion: completion as CompletionSnapshot | undefined,
		completionNotification: data.completionNotification,
		completionWake: data.completionWake,
	};
}

function persistedTasks(ctx: ExtensionContext): BackgroundTask[] {
	const latest = new Map<string, BackgroundTask>();
	for (const entry of ctx.sessionManager.getBranch()) {
		if (entry.type !== "custom" || entry.customType !== TASK_ENTRY_TYPE)
			continue;
		const task = backgroundTask(entry.data);
		if (task) latest.set(task.sessionName, task);
	}
	return [...latest.values()];
}

function listedBackgroundSessions(output: string): Set<string> {
	return new Set(
		parseZmxSessions(output)
			.map((session) => session.name)
			.filter((name) => name.startsWith("pi-bg-")),
	);
}

function outputMarkers(): OutputMarkers {
	const id = randomUUID().replaceAll("-", "");
	return {
		start: `__PI_BG_OUTPUT_START_${id}__`,
		end: `__PI_BG_OUTPUT_END_${id}__`,
	};
}

function extractBackgroundOutput(
	history: string,
	markers: OutputMarkers,
): string {
	const lines = history.replaceAll("\r", "").split("\n");
	const startIndex = lines.lastIndexOf(markers.start);
	if (startIndex < 0) return "";
	const endIndex = lines.findIndex(
		(line, index) => index > startIndex && line.startsWith(`${markers.end}:`),
	);
	return lines
		.slice(startIndex + 1, endIndex < 0 ? undefined : endIndex)
		.join("\n")
		.trimEnd();
}

function shellQuote(value: string): string {
	return `'${value.replaceAll("'", "'\\''")}'`;
}

// zmx has no exec channel for `run`: it spawns a login bash and types the
// launch line into the PTY, where the tty echoes it and readline renders it
// again. Every argument therefore lands in `zmx history` twice. Keeping the
// command in a script file holds the echoed line to `<shell> <script>`.
function controlScript(
	shellPath: string,
	command: string,
	markers: OutputMarkers,
): string {
	return `${[
		`printf '%s\\n' ${shellQuote(markers.start)}`,
		`${shellQuote(shellPath)} -c ${shellQuote(command)}`,
		"pi_bg_exit_code=$?",
		`printf '\\n%s:%s\\n' ${shellQuote(markers.end)} "$pi_bg_exit_code"`,
		'exit "$pi_bg_exit_code"',
	].join("\n")}\n`;
}

async function writeControlScript(
	sessionName: string,
	script: string,
): Promise<string> {
	const dir = controlScriptDir();
	await mkdir(dir, { recursive: true });
	const path = join(dir, `${sessionName}.sh`);
	await writeFile(path, script, { mode: 0o700 });
	return path;
}

function appendOutput(
	lines: string[],
	label: string,
	output: string,
	historyCommand: string,
	limits: { maxBytes: number; maxLines: number } = {
		maxBytes: OUTPUT_MAX_BYTES,
		maxLines: OUTPUT_MAX_LINES,
	},
): void {
	const tail = truncateTail(output, limits);
	lines.push("", `${label}:`, tail.content || "(no output)");
	if (tail.truncated) {
		lines.push(`[Output truncated; use ${historyCommand} for full history.]`);
	}
}

function timeoutContent(
	sessionName: string,
	timeoutSeconds: number,
	output: string,
): string {
	const historyCommand = `zmx history ${sessionName} | tail -n 200`;
	const lines = [
		`⏳ Background command is still running after ${timeoutSeconds}s.`,
		`Zmx session: ${sessionName}`,
		"The command was not stopped; completion will still notify the agent.",
		`Logs: ${historyCommand}`,
	];
	appendOutput(lines, "Output so far", output, historyCommand);
	return lines.join("\n");
}

function remainingTaskStatus(
	remainingTaskCount: number,
	deferredCompletionCount = 0,
): string {
	if (remainingTaskCount === 0 && deferredCompletionCount === 0) {
		return "No managed background tasks remain; no further completion wake-up is pending.";
	}
	const running =
		remainingTaskCount === 0
			? undefined
			: remainingTaskCount === 1
				? "1 managed background task remains and will notify the agent when it finishes."
				: `${remainingTaskCount} managed background tasks remain and will notify the agent when they finish.`;
	const deferred =
		deferredCompletionCount === 0
			? undefined
			: `${deferredCompletionCount} additional completion notification${deferredCompletionCount === 1 ? " is" : "s are"} queued.`;
	return [running, deferred].filter(Boolean).join(" ");
}

function completionTaskContent(
	sessionName: string,
	completion: CompletionSnapshot,
	outputLimits: { maxBytes: number; maxLines: number },
): string {
	const duration = `${(completion.durationMs / 1000).toFixed(1)}s`;
	const historyCommand = `zmx history ${sessionName} | tail -n 200`;
	const lines = [
		completion.exitCode === 0
			? `✓ Background command finished (exit 0, ${duration})`
			: `✗ Background command failed (exit ${completion.exitCode}, ${duration})`,
		`Zmx session retained for logs: ${sessionName}`,
		`Logs: ${historyCommand}`,
	];
	appendOutput(
		lines,
		"Output",
		completion.output,
		historyCommand,
		outputLimits,
	);
	return lines.join("\n");
}

function completionContent(
	tasks: BackgroundTask[],
	remainingTaskCount: number,
	deferredCompletionCount: number,
): string {
	const outputLimits = {
		maxBytes: Math.max(512, Math.floor(OUTPUT_MAX_BYTES / tasks.length)),
		maxLines: Math.max(5, Math.floor(OUTPUT_MAX_LINES / tasks.length)),
	};
	const blocks = tasks.flatMap((task, index) => {
		if (!task.completion) return [];
		const heading =
			tasks.length === 1
				? undefined
				: `Background completion ${index + 1}/${tasks.length}`;
		return [
			[
				heading,
				completionTaskContent(task.sessionName, task.completion, outputLimits),
			]
				.filter(Boolean)
				.join("\n"),
		];
	});
	return [
		remainingTaskStatus(remainingTaskCount, deferredCompletionCount),
		"Managed task status: zmx-list",
		...blocks,
	].join("\n\n");
}

export default function backgroundBashExtension(pi: ExtensionAPI) {
	const foregroundBash = createBashToolDefinition(process.cwd());
	const waitControllers = new Set<AbortController>();
	const tasksBySession = new Map<string, BackgroundTask>();
	let sessionClosed = false;
	let completionFlushTimer: ReturnType<typeof setTimeout> | undefined;
	let completionFlushReady = false;
	// After the final completion notification (zero tasks remain), nothing else
	// will ever wake the agent, so a silent settled run there loses the result.
	let finalWakeupWatch: "off" | "armed" | "nudged" = "off";
	let finalWakeupRun: "pending" | "silent" | "engaged" = "pending";

	function updateStatus(ctx: ExtensionContext): void {
		const count = waitControllers.size;
		const status =
			count === 0
				? undefined
				: ctx.ui.theme.fg("accent", "") + ctx.ui.theme.fg("dim", ` ${count}`);
		ctx.ui.setStatus(STATUS_ID, status);
	}

	async function readOutput(
		sessionName: string,
		cwd: string,
		markers: OutputMarkers,
	): Promise<string> {
		try {
			const history = await pi.exec("zmx", ["history", sessionName], { cwd });
			return history.code === 0
				? extractBackgroundOutput(history.stdout, markers)
				: "";
		} catch {
			return "";
		}
	}

	function persistTask(task: BackgroundTask): void {
		tasksBySession.set(task.sessionName, task);
		try {
			pi.appendEntry(TASK_ENTRY_TYPE, task);
		} catch {
			// Session replacement can invalidate the old extension between checks.
		}
	}

	function updateTask(
		sessionName: string,
		update: (task: BackgroundTask) => BackgroundTask,
	): BackgroundTask | undefined {
		const current = tasksBySession.get(sessionName);
		if (!current) return undefined;
		const next = update(current);
		persistTask(next);
		return next;
	}

	function deliverTimeoutNotification(task: BackgroundTask): boolean {
		if (
			task.timeoutNotification !== "pending" ||
			task.timeoutSeconds === undefined ||
			!task.timeout
		) {
			return false;
		}
		try {
			pi.sendMessage(
				{
					customType: TIMEOUT_MESSAGE_TYPE,
					content: timeoutContent(
						task.sessionName,
						task.timeoutSeconds,
						task.timeout.output,
					),
					display: true,
					details: {
						command: task.command,
						cwd: task.cwd,
						durationMs: task.timeout.durationMs,
						sessionName: task.sessionName,
						stillRunning: task.state === "running",
						timeoutSeconds: task.timeoutSeconds,
					},
				},
				{ deliverAs: "steer", triggerTurn: true },
			);
		} catch {
			return false;
		}
		updateTask(task.sessionName, (current) => ({
			...current,
			timeoutNotification: "sent",
		}));
		return true;
	}

	function markPendingCompletionWakesSent(): void {
		for (const task of tasksBySession.values()) {
			if (task.completionWake !== "pending") continue;
			updateTask(task.sessionName, (current) => ({
				...current,
				completionWake: "sent",
			}));
		}
	}

	function sendFinalWake(task: BackgroundTask): boolean {
		if (
			task.completionNotification !== "sent" ||
			task.completionWake !== "pending"
		) {
			return false;
		}
		finalWakeupWatch = "armed";
		finalWakeupRun = "pending";
		try {
			pi.sendUserMessage(FINAL_WAKEUP_NUDGE, { deliverAs: "steer" });
		} catch {
			return false;
		}
		updateTask(task.sessionName, (current) => ({
			...current,
			completionWake: "sent",
		}));
		return true;
	}

	function flushCompletionBatch(): boolean {
		if (!completionFlushReady || sessionClosed) return false;
		const pending = [...tasksBySession.values()].filter(
			(task) =>
				task.state === "finished" &&
				task.completion !== undefined &&
				task.completionNotification === "pending",
		);
		if (pending.length === 0) {
			completionFlushReady = false;
			return false;
		}

		const batch = pending.slice(0, COMPLETION_BATCH_MAX_TASKS);
		const deferredCompletionCount = pending.length - batch.length;
		const remainingTaskCount = waitControllers.size;
		const isFinalCompletion =
			remainingTaskCount === 0 && deferredCompletionCount === 0;
		const anchor = batch.at(-1);
		if (isFinalCompletion && anchor) {
			updateTask(anchor.sessionName, (current) => ({
				...current,
				completionWake: "pending",
			}));
		}

		try {
			pi.sendMessage(
				{
					customType: COMPLETION_MESSAGE_TYPE,
					content: completionContent(
						batch,
						remainingTaskCount,
						deferredCompletionCount,
					),
					display: true,
					details: {
						remainingTaskCount,
						deferredCompletionCount,
						completions: batch.map((task) => ({
							command: task.command,
							cwd: task.cwd,
							durationMs: task.completion?.durationMs,
							exitCode: task.completion?.exitCode,
							sessionName: task.sessionName,
						})),
						...(batch.length === 1
							? {
									command: batch[0]?.command,
									cwd: batch[0]?.cwd,
									durationMs: batch[0]?.completion?.durationMs,
									exitCode: batch[0]?.completion?.exitCode,
									sessionName: batch[0]?.sessionName,
								}
							: {}),
					},
				},
				{ deliverAs: "steer", triggerTurn: !isFinalCompletion },
			);
		} catch {
			// Keep the durable pending state for the next safe retry point.
			return false;
		}

		for (const task of batch) {
			updateTask(task.sessionName, (current) => ({
				...current,
				completionNotification: "sent",
			}));
		}
		completionFlushReady = false;
		if (deferredCompletionCount > 0) scheduleCompletionFlush();

		if (!isFinalCompletion || !anchor) return !isFinalCompletion;
		const currentAnchor = tasksBySession.get(anchor.sessionName);
		return currentAnchor ? sendFinalWake(currentAnchor) : false;
	}

	function flushPendingNotifications(): boolean {
		let triggeredTurn = false;
		// Snapshot pre-existing wake retries so a failed first send from the batch
		// below is retried only at the next safe event, not immediately in a loop.
		const pendingWakeSessionNames = [...tasksBySession.values()]
			.filter(
				(task) =>
					task.completionNotification === "sent" &&
					task.completionWake === "pending",
			)
			.map((task) => task.sessionName);
		for (const task of tasksBySession.values()) {
			if (deliverTimeoutNotification(task)) triggeredTurn = true;
		}
		if (flushCompletionBatch()) triggeredTurn = true;
		for (const sessionName of pendingWakeSessionNames) {
			const task = tasksBySession.get(sessionName);
			if (task && sendFinalWake(task)) triggeredTurn = true;
		}
		return triggeredTurn;
	}

	function scheduleCompletionFlush(): void {
		if (completionFlushTimer !== undefined || completionFlushReady) return;
		completionFlushTimer = setTimeout(() => {
			completionFlushTimer = undefined;
			completionFlushReady = true;
			flushPendingNotifications();
		}, COMPLETION_BATCH_DELAY_MS);
	}

	async function watchCompletion(
		task: BackgroundTask,
		controller: AbortController,
		ctx: ExtensionContext,
	) {
		const {
			sessionName,
			command,
			cwd,
			startedAt,
			shellPath,
			markers,
			timeoutSeconds,
		} = task;
		let settled = false;
		const timeoutDelay =
			timeoutSeconds === undefined || task.timeoutNotification !== "none"
				? undefined
				: Math.max(0, startedAt + timeoutSeconds * 1000 - Date.now());
		const timeoutHandle =
			timeoutDelay === undefined || timeoutSeconds === undefined
				? undefined
				: setTimeout(() => {
						void (async () => {
							if (settled || sessionClosed || controller.signal.aborted) return;
							const output = await readOutput(sessionName, cwd, markers);
							if (settled || sessionClosed || controller.signal.aborted) return;
							const pending = updateTask(sessionName, (current) => ({
								...current,
								timeout: {
									durationMs: Date.now() - startedAt,
									output,
								},
								timeoutNotification: "pending",
							}));
							if (pending) deliverTimeoutNotification(pending);
						})();
					}, timeoutDelay);
		const clearWakeTimer = () => {
			if (timeoutHandle !== undefined) clearTimeout(timeoutHandle);
		};
		controller.signal.addEventListener("abort", clearWakeTimer, { once: true });

		try {
			const result = await pi.exec(
				shellPath,
				["-c", 'exec zmx wait "$1" >/dev/null', "pi-bg-wait", sessionName],
				{
					cwd,
					signal: controller.signal,
				},
			);
			if (sessionClosed || controller.signal.aborted) return;
			settled = true;
			const output = await readOutput(sessionName, cwd, markers);
			if (sessionClosed || controller.signal.aborted) return;

			const current = tasksBySession.get(sessionName) ?? task;
			persistTask({
				...current,
				state: "finished",
				completion: {
					exitCode: result.code,
					durationMs: Date.now() - startedAt,
					output: output || (result.code === 0 ? "" : execFailure(result)),
				},
				completionNotification: "pending",
			});
			waitControllers.delete(controller);
			updateStatus(ctx);
			scheduleCompletionFlush();
		} catch (error) {
			if (sessionClosed || controller.signal.aborted) return;
			const message = error instanceof Error ? error.message : String(error);
			try {
				pi.sendMessage(
					{
						customType: COMPLETION_MESSAGE_TYPE,
						content: [
							`Background command watcher failed for zmx session ${sessionName}.`,
							`Command: ${command}`,
							`Error: ${message}`,
							`Inspect: zmx history ${sessionName} | tail -n 200`,
						].join("\n"),
						display: true,
						details: { command, cwd, error: message, sessionName },
					},
					{ deliverAs: "steer", triggerTurn: true },
				);
			} catch {
				// The session may have been replaced between the active check and send.
			}
		} finally {
			settled = true;
			clearWakeTimer();
			controller.signal.removeEventListener("abort", clearWakeTimer);
			waitControllers.delete(controller);
			if (!sessionClosed) updateStatus(ctx);
		}
	}

	async function restoreBackgroundTasks(ctx: ExtensionContext): Promise<void> {
		tasksBySession.clear();
		for (const task of persistedTasks(ctx))
			tasksBySession.set(task.sessionName, task);
		const runningTasks = [...tasksBySession.values()].filter(
			(task) => task.state === "running",
		);
		if (runningTasks.length > 0) {
			const result = await pi.exec("zmx", ["list"], { cwd: ctx.cwd });
			if (result.code !== 0) {
				throw new Error(`Could not list zmx sessions: ${execFailure(result)}`);
			}
			const listed = listedBackgroundSessions(result.stdout);
			if (sessionClosed) return;

			for (const task of runningTasks) {
				if (!listed.has(task.sessionName)) {
					persistTask({ ...task, state: "finished" });
					continue;
				}
				const controller = new AbortController();
				waitControllers.add(controller);
				void watchCompletion(task, controller, ctx);
			}
		}
		updateStatus(ctx);
		if (
			[...tasksBySession.values()].some(
				(task) => task.completionNotification === "pending",
			)
		) {
			completionFlushReady = true;
		}
		flushPendingNotifications();
	}

	pi.on("session_start", async (_event, ctx) => {
		sessionClosed = false;
		finalWakeupWatch = "off";
		finalWakeupRun = "pending";
		await restoreBackgroundTasks(ctx);
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		sessionClosed = true;
		finalWakeupWatch = "off";
		if (completionFlushTimer !== undefined) clearTimeout(completionFlushTimer);
		completionFlushTimer = undefined;
		completionFlushReady = false;
		for (const controller of waitControllers) controller.abort();
		waitControllers.clear();
		updateStatus(ctx);
	});

	pi.on("tool_execution_end", async (_event, ctx) => {
		if (!sessionClosed) flushPendingNotifications();
		updateStatus(ctx);
	});

	pi.on("agent_end", async (event) => {
		if (sessionClosed || finalWakeupWatch === "off") return;
		const last = lastAssistantMessage(event.messages);
		if (
			last &&
			(last.stopReason === "aborted" ||
				last.content.some(
					(block) =>
						block.type === "toolCall" ||
						(block.type === "text" && (block.text ?? "").trim() !== ""),
				))
		) {
			finalWakeupRun = "engaged";
			finalWakeupWatch = "off";
			markPendingCompletionWakesSent();
			return;
		}
		finalWakeupRun = last && isSilentStop(last) ? "silent" : "pending";
	});

	pi.on("agent_settled", async (_event, _ctx) => {
		if (sessionClosed) return;
		if (flushPendingNotifications()) return;
		if (finalWakeupWatch === "off" || finalWakeupRun === "engaged") return;
		if (finalWakeupWatch === "nudged") {
			finalWakeupWatch = "off";
			pi.appendEntry(EMPTY_TURN_ENTRY_TYPE, { action: "gave-up" });
			return;
		}
		finalWakeupWatch = "nudged";
		finalWakeupRun = "pending";
		try {
			pi.sendUserMessage(EMPTY_TURN_NUDGE, { deliverAs: "followUp" });
			markPendingCompletionWakesSent();
			pi.appendEntry(EMPTY_TURN_ENTRY_TYPE, { action: "nudged" });
		} catch (error) {
			finalWakeupWatch = "armed";
			pi.appendEntry(EMPTY_TURN_ENTRY_TYPE, {
				action: "nudge-failed",
				error: error instanceof Error ? error.message : String(error),
			});
		}
	});

	pi.registerTool({
		...foregroundBash,
		description:
			"Execute a Bash command in the current working directory. Foreground commands return bounded output. Background commands run in a detached zmx session and notify on completion; their timeout requests an early wake without stopping the command.",
		promptSnippet:
			"Execute Bash commands, with detached background execution for asynchronous workflows",
		promptGuidelines: [
			"Use foreground Bash by default, including for tests, checks, builds, linting, and formatting.",
			"Keep the main agent thread responsive: run intentionally asynchronous work such as PR waiters and Gauntlet reviews with background=true; do not use it merely to parallelize validation.",
			"Background Bash already returns immediately and notifies on completion; omit timeout unless an early wake-up is genuinely useful.",
			"Never run zmx wait or zmx tail for a pi-bg-* session created by Bash with background=true; the harness already waits for it. Continue independent work or end the turn instead.",
			"A background-bash-finished message states the authoritative remaining managed-task count; when zero remain, nothing is left to wake the agent — do not assume monitoring continues. Check managed task status with zmx-list (zmx-list --all includes completed exit status).",
		],
		parameters: bashParameters,
		async execute(toolCallId, params, signal, onUpdate, ctx) {
			const bash = configuredBash(ctx.cwd);
			const automaticallyBackgrounded =
				params.background !== true &&
				params.timeout !== undefined &&
				params.timeout > MAX_FOREGROUND_TIMEOUT_SECONDS;
			if (!params.background && !automaticallyBackgrounded) {
				return bash.tool.execute(
					toolCallId,
					{ command: params.command, timeout: params.timeout },
					signal,
					onUpdate,
					ctx,
				);
			}

			await pruneOldBackgroundSessions(pi, ctx.cwd);

			const sessionName = backgroundSessionName(toolCallId, params.command);
			const startedAt = Date.now();
			const command = bash.commandPrefix
				? `${bash.commandPrefix}\n${params.command}`
				: params.command;
			const markers = outputMarkers();
			const scriptPath = await writeControlScript(
				sessionName,
				controlScript(bash.shellPath, command, markers),
			);
			// QUIET_PROMPT is redundant where bash.nix also suppresses the prompt
			// for any ZMX_SESSION, but it keeps this working on hosts that do not
			// use these dotfiles. zmx forks the daemon from this client, so the
			// variable only lands if the session is created here — which it is,
			// because every launch generates a fresh session name.
			const launch = await pi.exec(
				"env",
				[
					"QUIET_PROMPT=1",
					"zmx",
					"run",
					sessionName,
					"-d",
					bash.shellPath,
					scriptPath,
				],
				{ cwd: ctx.cwd },
			);
			if (launch.code !== 0) {
				await rm(scriptPath, { force: true }).catch(() => {});
				const output = execFailure(launch);
				throw new Error(
					output
						? `Failed to start background command: ${output}`
						: `Failed to start background command (zmx exited ${launch.code})`,
				);
			}

			const task: BackgroundTask = {
				version: 2,
				state: "running",
				sessionName,
				command: params.command,
				cwd: ctx.cwd,
				startedAt,
				shellPath: bash.shellPath,
				markers,
				timeoutSeconds: params.timeout,
				timeoutNotification: "none",
				completionNotification: "none",
				completionWake: "none",
			};
			persistTask(task);
			finalWakeupWatch = "off";
			finalWakeupRun = "pending";
			const controller = new AbortController();
			waitControllers.add(controller);
			updateStatus(ctx);
			void watchCompletion(task, controller, ctx);

			return {
				content: [
					{
						type: "text",
						text: [
							`Started background command in zmx session ${sessionName}.`,
							automaticallyBackgrounded
								? `Automatically sent to the background because the requested ${params.timeout}s timeout exceeds the ${MAX_FOREGROUND_TIMEOUT_SECONDS}s foreground limit.`
								: undefined,
							"Completion will notify the agent automatically; do not run zmx wait or zmx tail for this session.",
							params.timeout === undefined
								? undefined
								: `If still running after ${params.timeout}s, the agent will be woken without stopping the command.`,
							`Logs: zmx history ${sessionName} | tail -n 200`,
						]
							.filter(Boolean)
							.join("\n"),
					},
				],
				details: undefined,
			};
		},
	});
}
