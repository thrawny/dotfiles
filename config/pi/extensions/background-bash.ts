import { randomUUID } from "node:crypto";
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
const FAILURE_OUTPUT_MAX_BYTES = 12 * 1024;
const FAILURE_OUTPUT_MAX_LINES = 100;

const bashParameters = Type.Object({
	command: Type.String({ description: "Bash command to execute" }),
	timeout: Type.Optional(
		Type.Number({
			description:
				"Timeout in seconds for foreground commands (optional, no default timeout)",
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

export function backgroundSessionName(
	toolCallId: string,
	command: string,
): string {
	const commandName = slug(command.split(/\s+/, 1)[0] ?? "", "task", 20);
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

function completionContent(
	sessionName: string,
	command: string,
	result: ExecResult,
	durationMs: number,
): string {
	const duration = `${(durationMs / 1000).toFixed(1)}s`;
	const historyCommand = `zmx history ${sessionName} | tail -n 200`;
	const lines = [
		result.code === 0
			? `✓ Background command finished (exit 0, ${duration})`
			: `✗ Background command failed (exit ${result.code}, ${duration})`,
		`Command: ${command}`,
		`Zmx session: ${sessionName}`,
		`Logs: ${historyCommand}`,
	];

	if (result.code !== 0) {
		const output = execFailure(result);
		if (output) {
			const tail = truncateTail(output, {
				maxBytes: FAILURE_OUTPUT_MAX_BYTES,
				maxLines: FAILURE_OUTPUT_MAX_LINES,
			});
			lines.push("", "Last output:", tail.content);
			if (tail.truncated) {
				lines.push(
					`[Output truncated; use ${historyCommand} for full history.]`,
				);
			}
		}
	}

	return lines.join("\n");
}

export default function backgroundBashExtension(pi: ExtensionAPI) {
	const foregroundBash = createBashToolDefinition(process.cwd());
	const waitControllers = new Set<AbortController>();
	let sessionClosed = false;

	async function watchCompletion(
		sessionName: string,
		command: string,
		cwd: string,
		startedAt: number,
		controller: AbortController,
	) {
		try {
			const result = await pi.exec("zmx", ["wait", sessionName], {
				cwd,
				signal: controller.signal,
			});
			if (sessionClosed || controller.signal.aborted) return;

			pi.sendMessage(
				{
					customType: COMPLETION_MESSAGE_TYPE,
					content: completionContent(
						sessionName,
						command,
						result,
						Date.now() - startedAt,
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
			"Execute a bash command in the current working directory. Set background=true for long-running commands that can run concurrently with other work; background commands run in a detached zmx session and notify the agent on completion. Foreground output is truncated to the built-in limits. timeout is supported only for foreground commands.",
		promptSnippet:
			"Execute bash commands; set background=true for detached zmx execution with completion notification",
		promptGuidelines: [
			"Use bash with background=true for long-running finite commands when useful work can continue while they run; completion wakes the agent automatically, so do not poll or sleep waiting for them.",
			"Use foreground bash when its output is needed before continuing.",
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

			if (params.timeout !== undefined) {
				throw new Error(
					"timeout is not supported with background=true; enforce the deadline in the command itself",
				);
			}

			const sessionName = backgroundSessionName(toolCallId, params.command);
			const startedAt = Date.now();
			const command = bash.commandPrefix
				? `${bash.commandPrefix}\n${params.command}`
				: params.command;
			const launch = await pi.exec(
				"zmx",
				["run", sessionName, "-d", bash.shellPath, "-c", command],
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
			);

			return {
				content: [
					{
						type: "text",
						text: [
							`Started background command in zmx session ${sessionName}.`,
							"Completion will notify the agent automatically.",
							`Logs: zmx history ${sessionName} | tail -n 200`,
						].join("\n"),
					},
				],
				details: undefined,
			};
		},
	});
}
