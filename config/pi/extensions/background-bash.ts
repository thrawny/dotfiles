import { randomUUID } from "node:crypto";
import { basename } from "node:path";
import {
	createBashToolDefinition,
	SettingsManager,
	truncateTail,
	type BashToolOptions,
	type ExecResult,
	type ExtensionAPI,
} from "@earendil-works/pi-coding-agent";
import { Type } from "@sinclair/typebox";

const COMPLETION_MESSAGE_TYPE = "background-bash-finished";
const TIMEOUT_MESSAGE_TYPE = "background-bash-timeout";
const OUTPUT_MAX_BYTES = 12 * 1024;
const OUTPUT_MAX_LINES = 100;
const SESSION_RETENTION_SECONDS = 12 * 60 * 60;

const bashParameters = Type.Object({
	command: Type.String({ description: "Bash command to execute" }),
	timeout: Type.Optional(
		Type.Number({
			minimum: 1,
			description:
				"Foreground: stop the command after this many seconds. Background: wake the agent after this many seconds if the command is still running, without stopping it.",
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

function staleBackgroundSessions(output: string, nowSeconds: number): string[] {
	const cutoff = nowSeconds - SESSION_RETENTION_SECONDS;
	const stale: string[] = [];

	for (const line of output.split("\n")) {
		const fields = new Map<string, string>();
		for (const field of line.trim().split("\t")) {
			const separator = field.indexOf("=");
			if (separator > 0) {
				fields.set(field.slice(0, separator), field.slice(separator + 1));
			}
		}

		const name = fields.get("name");
		const ended = Number(fields.get("ended"));
		if (
			name?.startsWith("pi-bg-") &&
			fields.get("clients") === "0" &&
			Number.isSafeInteger(ended) &&
			ended <= cutoff
		) {
			stale.push(name);
		}
	}

	return stale;
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
}

type OutputMarkers = { start: string; end: string };

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

function appendOutput(
	lines: string[],
	label: string,
	output: string,
	historyCommand: string,
): void {
	const tail = truncateTail(output, {
		maxBytes: OUTPUT_MAX_BYTES,
		maxLines: OUTPUT_MAX_LINES,
	});
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

function completionContent(
	sessionName: string,
	result: ExecResult,
	durationMs: number,
	output: string,
): string {
	const duration = `${(durationMs / 1000).toFixed(1)}s`;
	const historyCommand = `zmx history ${sessionName} | tail -n 200`;
	const lines = [
		result.code === 0
			? `✓ Background command finished (exit 0, ${duration})`
			: `✗ Background command failed (exit ${result.code}, ${duration})`,
		`Zmx session: ${sessionName}`,
		`Logs: ${historyCommand}`,
	];
	appendOutput(
		lines,
		"Output",
		output || (result.code === 0 ? "" : execFailure(result)),
		historyCommand,
	);
	return lines.join("\n");
}

export default function backgroundBashExtension(pi: ExtensionAPI) {
	const foregroundBash = createBashToolDefinition(process.cwd());
	const waitControllers = new Set<AbortController>();
	let sessionClosed = false;

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

	async function watchCompletion(
		sessionName: string,
		command: string,
		cwd: string,
		startedAt: number,
		controller: AbortController,
		shellPath: string,
		markers: OutputMarkers,
		timeoutSeconds?: number,
	) {
		let settled = false;
		const timeoutHandle =
			timeoutSeconds === undefined
				? undefined
				: setTimeout(() => {
						void (async () => {
							if (settled || sessionClosed || controller.signal.aborted) return;
							const output = await readOutput(sessionName, cwd, markers);
							if (settled || sessionClosed || controller.signal.aborted) return;
							try {
								pi.sendMessage(
									{
										customType: TIMEOUT_MESSAGE_TYPE,
										content: timeoutContent(
											sessionName,
											timeoutSeconds,
											output,
										),
										display: true,
										details: {
											command,
											cwd,
											durationMs: Date.now() - startedAt,
											sessionName,
											stillRunning: true,
											timeoutSeconds,
										},
									},
									{ deliverAs: "steer", triggerTurn: true },
								);
							} catch {
								// The session may have been replaced before the timer fired.
							}
						})();
					}, timeoutSeconds * 1000);
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

			pi.sendMessage(
				{
					customType: COMPLETION_MESSAGE_TYPE,
					content: completionContent(
						sessionName,
						result,
						Date.now() - startedAt,
						output,
					),
					display: true,
					details: {
						command,
						cwd,
						durationMs: Date.now() - startedAt,
						exitCode: result.code,
						sessionName,
					},
				},
				{ deliverAs: "steer", triggerTurn: true },
			);
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
		}
	}

	pi.on("session_start", async () => {
		sessionClosed = false;
	});

	pi.on("session_shutdown", async () => {
		sessionClosed = true;
		for (const controller of waitControllers) controller.abort();
		waitControllers.clear();
	});

	pi.registerTool({
		...foregroundBash,
		description:
			"Execute a Bash command in the current working directory. Foreground commands return bounded output. Background commands run in a detached zmx session and notify on completion; their timeout requests an early wake without stopping the command.",
		promptSnippet:
			"Execute Bash commands, with detached background execution for asynchronous workflows",
		promptGuidelines: [
			"Use foreground Bash by default, including for tests, checks, builds, linting, and formatting.",
			"Use Bash with background=true only for intentionally asynchronous workflows such as PR waiters and Gauntlet reviews; do not use it merely to parallelize validation.",
			"Background Bash already returns immediately and notifies on completion; omit timeout unless an early wake-up is genuinely useful.",
			"Never run zmx wait or zmx tail for a pi-bg-* session created by Bash with background=true; the harness already waits for it. Continue independent work or end the turn instead.",
		],
		parameters: bashParameters,
		async execute(toolCallId, params, signal, onUpdate, ctx) {
			const bash = configuredBash(ctx.cwd);
			if (!params.background) {
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
			const controlCommand = [
				`printf '%s\\n' "$3"`,
				`"$1" -c "$2"`,
				"pi_bg_exit_code=$?",
				`printf '\\n%s:%s\\n' "$4" "$pi_bg_exit_code"`,
				`exit "$pi_bg_exit_code"`,
			].join("\n");
			const launch = await pi.exec(
				"env",
				[
					"QUIET_PROMPT=1",
					"zmx",
					"run",
					sessionName,
					"-d",
					bash.shellPath,
					"-c",
					controlCommand,
					"pi-bg-control",
					bash.shellPath,
					command,
					markers.start,
					markers.end,
				],
				{ cwd: ctx.cwd },
			);
			if (launch.code !== 0) {
				const output = execFailure(launch);
				throw new Error(
					output
						? `Failed to start background command: ${output}`
						: `Failed to start background command (zmx exited ${launch.code})`,
				);
			}

			const controller = new AbortController();
			waitControllers.add(controller);
			void watchCompletion(
				sessionName,
				params.command,
				ctx.cwd,
				startedAt,
				controller,
				bash.shellPath,
				markers,
				params.timeout,
			);

			return {
				content: [
					{
						type: "text",
						text: [
							`Started background command in zmx session ${sessionName}.`,
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
