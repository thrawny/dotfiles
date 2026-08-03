import { mkdtempSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type {
	ExecOptions,
	ExecResult,
	ExtensionAPI,
	ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { beforeEach, describe, expect, it, vi } from "vitest";

// Keep generated control scripts out of the real user cache directory.
process.env.XDG_CACHE_HOME = mkdtempSync(join(tmpdir(), "pi-bg-test-"));
import backgroundBashExtension, {
	backgroundSessionName,
} from "../extensions/background-bash.ts";

type ToolResult = {
	content: Array<{ type: "text"; text: string }>;
};

type RegisteredBashTool = {
	parameters: {
		properties?: Record<string, unknown>;
	};
	promptGuidelines?: string[];
	execute(
		toolCallId: string,
		params: { command: string; timeout?: number; background?: boolean },
		signal: AbortSignal | undefined,
		onUpdate: undefined,
		ctx: ExtensionContext,
	): Promise<ToolResult>;
};

type EventHandler = (
	event: unknown,
	ctx: ExtensionContext,
) => Promise<void> | void;

function execResult(overrides: Partial<ExecResult> = {}): ExecResult {
	return {
		stdout: "",
		stderr: "",
		code: 0,
		killed: false,
		...overrides,
	};
}

function isQuietWait(args: string[]): boolean {
	return args[0] === "-c" && args[1]?.includes("zmx wait") === true;
}

function setupExtension(
	exec: (
		command: string,
		args: string[],
		options?: ExecOptions,
	) => Promise<ExecResult>,
) {
	let tool: RegisteredBashTool | undefined;
	const handlers = new Map<string, EventHandler>();
	const sendMessage = vi.fn();
	const sendUserMessage = vi.fn();
	const appendEntry = vi.fn();
	const pi = {
		exec,
		on(event: string, handler: EventHandler) {
			handlers.set(event, handler);
		},
		registerTool(value: RegisteredBashTool) {
			tool = value;
		},
		appendEntry,
		sendMessage,
		sendUserMessage,
	} as unknown as ExtensionAPI;

	backgroundBashExtension(pi);
	if (!tool) throw new Error("bash tool was not registered");

	return { appendEntry, handlers, sendMessage, sendUserMessage, tool };
}

function assistantStop(
	content: Array<{ type: string; text?: string }>,
	stopReason = "stop",
) {
	return { role: "assistant", stopReason, content };
}

const setStatus = vi.fn();
const ctx = {
	cwd: "/tmp",
	mode: "tui",
	ui: {
		setStatus,
		theme: { fg: (_color: string, text: string) => text },
	},
	sessionManager: { getBranch: () => [] },
} as unknown as ExtensionContext;

describe("background bash", () => {
	beforeEach(() => {
		setStatus.mockClear();
	});

	it("generates a fresh zmx session name even when call IDs repeat", () => {
		const first = backgroundSessionName("call-reused", "just check");
		const second = backgroundSessionName("call-reused", "just check");

		expect(first).not.toBe(second);
		expect(first).toMatch(/^pi-bg-just-call-reused-/);
	});

	it("names a piped shell script after the script instead of the input command", () => {
		const command =
			"cat <<'EOF' | bash /home/user/skills/gauntlet/scripts/gauntlet-review --uncommitted -\nreview brief\nEOF";

		expect(backgroundSessionName("call-review", command)).toMatch(
			/^pi-bg-gauntlet-call-review-/,
		);
	});

	it("returns immediately and wakes the agent with bounded command output", async () => {
		let finishWait: ((result: ExecResult) => void) | undefined;
		let historyOutput = "";
		const waitResult = new Promise<ExecResult>((resolve) => {
			finishWait = resolve;
		});
		const exec = vi.fn(
			async (_command: string, args: string[], _options?: ExecOptions) => {
				if (isQuietWait(args)) return waitResult;
				if (args[0] === "history") return execResult({ stdout: historyOutput });
				return execResult();
			},
		);

		const { appendEntry, sendMessage, sendUserMessage, tool } =
			setupExtension(exec);

		expect(tool.parameters.properties).toHaveProperty("background");
		expect(tool.promptGuidelines?.join("\n")).toContain(
			"Check managed task status with zmx-list",
		);
		expect(tool.promptGuidelines?.join("\n")).toContain(
			"when zero remain, nothing is left to wake the agent",
		);
		const result = await tool.execute(
			"call-abc123",
			{ command: "just check", background: true },
			undefined,
			undefined,
			ctx,
		);

		expect(result.content[0]?.text).toContain("Started background command");
		expect(result.content[0]?.text).toContain(
			"do not run zmx wait or zmx tail",
		);
		expect(exec).toHaveBeenNthCalledWith(1, "zmx", ["list", "--json"], {
			cwd: "/tmp",
		});
		expect(exec).toHaveBeenNthCalledWith(
			2,
			"env",
			[
				"QUIET_PROMPT=1",
				"zmx",
				"run",
				expect.stringMatching(/^pi-bg-/),
				"-d",
				expect.any(String),
				expect.stringMatching(/\/pi-bg-.*\.sh$/),
			],
			{ cwd: "/tmp" },
		);
		expect(exec).toHaveBeenNthCalledWith(
			3,
			expect.any(String),
			[
				"-c",
				'exec zmx wait "$1" >/dev/null',
				"pi-bg-wait",
				expect.stringMatching(/^pi-bg-/),
			],
			expect.objectContaining({ cwd: "/tmp" }),
		);
		expect(sendMessage).not.toHaveBeenCalled();
		expect(appendEntry).toHaveBeenCalledWith(
			"background-bash-task",
			expect.objectContaining({ state: "running", command: "just check" }),
		);
		expect(setStatus).toHaveBeenLastCalledWith("background-bash", " 1");

		const launchArgs = exec.mock.calls[1]?.[1] as string[];
		const script = await readFile(launchArgs.at(-1) ?? "", "utf8");
		expect(script).toContain("pi_bg_exit_code");
		expect(script).toContain("just check");
		const startMarker = script.match(/__PI_BG_OUTPUT_START_\w+__/)?.[0] ?? "";
		const endMarker = script.match(/__PI_BG_OUTPUT_END_\w+__/)?.[0] ?? "";
		historyOutput = [
			"echoed command containing a very long heredoc",
			startMarker,
			"check output",
			`${endMarker}:0`,
		].join("\n");

		finishWait?.(execResult());
		await vi.waitFor(() => expect(sendMessage).toHaveBeenCalledOnce());
		const message = sendMessage.mock.calls[0]?.[0] as {
			content: string;
			details: { remainingTaskCount: number };
		};
		expect(message.content).toContain("exit 0");
		expect(message.content).toContain(
			"No managed background tasks remain; no further completion wake-up is pending.",
		);
		expect(message.details.remainingTaskCount).toBe(0);
		expect(sendMessage.mock.calls[0]?.[1]).toEqual({
			deliverAs: "steer",
			triggerTurn: false,
		});
		expect(sendUserMessage).toHaveBeenCalledOnce();
		expect(sendUserMessage.mock.calls[0]?.[0]).toContain("Keep working");
		expect(sendUserMessage.mock.calls[0]?.[1]).toEqual({ deliverAs: "steer" });
		expect(sendMessage.mock.invocationCallOrder[0]).toBeLessThan(
			sendUserMessage.mock.invocationCallOrder[0] ?? Number.POSITIVE_INFINITY,
		);
		expect(message.content).toContain("Managed task status: zmx-list");
		expect(message.content).toContain("Output:\ncheck output");
		expect(message.content).not.toContain("Command:");
		expect(message.content).not.toContain("echoed command");
		await vi.waitFor(() =>
			expect(setStatus).toHaveBeenLastCalledWith("background-bash", undefined),
		);
		expect(appendEntry).toHaveBeenLastCalledWith(
			"background-bash-task",
			expect.objectContaining({ state: "finished", command: "just check" }),
		);
	});

	it("keeps the command out of the launch line zmx echoes into scrollback", async () => {
		const exec = vi.fn(async (_command: string, args: string[]) => {
			if (isQuietWait(args)) return new Promise<ExecResult>(() => {});
			return execResult();
		});
		const { tool } = setupExtension(exec);
		// Quotes, newlines and $ all survive shell-quoting into the script file.
		const command = "echo 'it'\\''s $HOME'\nprintf 'done\\n'";

		await tool.execute(
			"call-quoting",
			{ command, background: true },
			undefined,
			undefined,
			ctx,
		);

		const launchArgs = exec.mock.calls[1]?.[1] as string[];
		expect(launchArgs.join(" ")).not.toContain("$HOME");
		expect(launchArgs.filter((arg) => arg.includes("\n"))).toEqual([]);

		const script = await readFile(launchArgs.at(-1) ?? "", "utf8");
		expect(script).toContain(command.replaceAll("'", "'\\''"));
		expect(script.trimEnd().endsWith('exit "$pi_bg_exit_code"')).toBe(true);
	});

	it("reports how many managed tasks remain after each completion", async () => {
		const finishWaits: Array<(result: ExecResult) => void> = [];
		const exec = vi.fn(async (_command: string, args: string[]) => {
			if (!isQuietWait(args)) return execResult();
			return new Promise<ExecResult>((resolve) => finishWaits.push(resolve));
		});
		const { sendMessage, sendUserMessage, tool } = setupExtension(exec);

		await tool.execute(
			"call-first",
			{ command: "first-task", background: true },
			undefined,
			undefined,
			ctx,
		);
		await tool.execute(
			"call-second",
			{ command: "second-task", background: true },
			undefined,
			undefined,
			ctx,
		);
		expect(finishWaits).toHaveLength(2);

		finishWaits[0]?.(execResult());
		await vi.waitFor(() => expect(sendMessage).toHaveBeenCalledTimes(1));
		const firstMessage = sendMessage.mock.calls[0]?.[0] as {
			content: string;
			details: { remainingTaskCount: number };
		};
		expect(firstMessage.content).toContain("1 managed background task remains");
		expect(firstMessage.details.remainingTaskCount).toBe(1);
		expect(sendMessage.mock.calls[0]?.[1]).toEqual({
			deliverAs: "steer",
			triggerTurn: true,
		});
		expect(sendUserMessage).not.toHaveBeenCalled();

		finishWaits[1]?.(execResult());
		await vi.waitFor(() => expect(sendMessage).toHaveBeenCalledTimes(2));
		const secondMessage = sendMessage.mock.calls[1]?.[0] as {
			content: string;
			details: { remainingTaskCount: number };
		};
		expect(secondMessage.content).toContain(
			"No managed background tasks remain",
		);
		expect(secondMessage.details.remainingTaskCount).toBe(0);
		expect(sendMessage.mock.calls[1]?.[1]).toEqual({
			deliverAs: "steer",
			triggerTurn: false,
		});
		expect(sendUserMessage).toHaveBeenCalledOnce();
	});

	it("batches completions that finish together into one wake-up", async () => {
		vi.useFakeTimers();
		try {
			const finishWaits: Array<(result: ExecResult) => void> = [];
			const exec = vi.fn(async (_command: string, args: string[]) => {
				if (!isQuietWait(args)) return execResult();
				return new Promise<ExecResult>((resolve) => finishWaits.push(resolve));
			});
			const { sendMessage, sendUserMessage, tool } = setupExtension(exec);

			await tool.execute(
				"call-batch-first",
				{ command: "first-task", background: true },
				undefined,
				undefined,
				ctx,
			);
			await tool.execute(
				"call-batch-second",
				{ command: "second-task", background: true },
				undefined,
				undefined,
				ctx,
			);
			finishWaits[0]?.(execResult());
			finishWaits[1]?.(execResult({ code: 3, stderr: "failed" }));
			await vi.advanceTimersByTimeAsync(0);
			expect(sendMessage).not.toHaveBeenCalled();

			await vi.advanceTimersByTimeAsync(250);
			expect(sendMessage).toHaveBeenCalledOnce();
			const message = sendMessage.mock.calls[0]?.[0] as {
				content: string;
				details: { completions: unknown[]; remainingTaskCount: number };
			};
			expect(message.content).toContain("Background completion 1/2");
			expect(message.content).toContain("Background completion 2/2");
			expect(message.content).toContain("exit 3");
			expect(message.details.completions).toHaveLength(2);
			expect(message.details.remainingTaskCount).toBe(0);
			expect(sendMessage.mock.calls[0]?.[1]).toEqual({
				deliverAs: "steer",
				triggerTurn: false,
			});
			expect(sendUserMessage).toHaveBeenCalledOnce();
		} finally {
			vi.useRealTimers();
		}
	});

	it("retries a failed completion notification at a safe tool boundary", async () => {
		let finishWait: ((result: ExecResult) => void) | undefined;
		const exec = vi.fn(async (_command: string, args: string[]) => {
			if (!isQuietWait(args)) return execResult();
			return new Promise<ExecResult>((resolve) => {
				finishWait = resolve;
			});
		});
		const { appendEntry, handlers, sendMessage, sendUserMessage, tool } =
			setupExtension(exec);
		sendMessage.mockImplementationOnce(() => {
			throw new Error("session temporarily busy");
		});

		await tool.execute(
			"call-notification-retry",
			{ command: "retry-task", background: true },
			undefined,
			undefined,
			ctx,
		);
		finishWait?.(execResult());
		await vi.waitFor(() => expect(sendMessage).toHaveBeenCalledOnce());
		expect(appendEntry).toHaveBeenLastCalledWith(
			"background-bash-task",
			expect.objectContaining({ completionNotification: "pending" }),
		);
		expect(sendUserMessage).not.toHaveBeenCalled();

		await handlers.get("tool_execution_end")?.({}, ctx);
		expect(sendMessage).toHaveBeenCalledTimes(2);
		expect(sendUserMessage).toHaveBeenCalledOnce();
		expect(appendEntry).toHaveBeenCalledWith(
			"background-bash-task",
			expect.objectContaining({ completionNotification: "sent" }),
		);
	});

	it("retries a failed final-wakeup delivery when the agent settles", async () => {
		let finishWait: ((result: ExecResult) => void) | undefined;
		const exec = vi.fn(async (_command: string, args: string[]) => {
			if (!isQuietWait(args)) return execResult();
			return new Promise<ExecResult>((resolve) => {
				finishWait = resolve;
			});
		});
		const { handlers, sendMessage, sendUserMessage, tool } =
			setupExtension(exec);
		sendUserMessage.mockImplementationOnce(() => {
			throw new Error("Agent is already processing.");
		});

		await tool.execute(
			"call-nudge-fail",
			{ command: "flaky-nudge-task", background: true },
			undefined,
			undefined,
			ctx,
		);
		finishWait?.(execResult());
		await vi.waitFor(() => expect(sendMessage).toHaveBeenCalledOnce());
		const message = sendMessage.mock.calls[0]?.[0] as { content: string };
		expect(message.content).toContain("exit 0");

		await handlers.get("agent_end")?.(
			{ messages: [assistantStop([{ type: "text", text: "" }])] },
			ctx,
		);
		await handlers.get("agent_settled")?.({}, ctx);
		expect(sendUserMessage).toHaveBeenCalledTimes(2);
		expect(sendUserMessage.mock.calls[1]?.[0]).toContain(
			"Extension-generated wake-up",
		);
		expect(sendUserMessage.mock.calls[1]?.[1]).toEqual({
			deliverAs: "steer",
		});
	});

	it("does not retry a failed final wake when the completion was acted on", async () => {
		let finishWait: ((result: ExecResult) => void) | undefined;
		const exec = vi.fn(async (_command: string, args: string[]) => {
			if (!isQuietWait(args)) return execResult();
			return new Promise<ExecResult>((resolve) => {
				finishWait = resolve;
			});
		});
		const { appendEntry, handlers, sendMessage, sendUserMessage, tool } =
			setupExtension(exec);
		sendUserMessage.mockImplementationOnce(() => {
			throw new Error("Agent is already processing.");
		});

		await tool.execute(
			"call-nudge-observed",
			{ command: "quick-task", background: true },
			undefined,
			undefined,
			ctx,
		);
		finishWait?.(execResult());
		await vi.waitFor(() => expect(sendMessage).toHaveBeenCalledOnce());

		await handlers.get("agent_end")?.(
			{
				messages: [
					assistantStop([{ type: "text", text: "Completion handled." }]),
				],
			},
			ctx,
		);
		await handlers.get("agent_settled")?.({}, ctx);

		expect(sendUserMessage).toHaveBeenCalledOnce();
		expect(appendEntry).toHaveBeenCalledWith(
			"background-bash-task",
			expect.objectContaining({ completionWake: "sent" }),
		);
	});

	describe("final wakeup empty-turn watchdog", () => {
		async function armWatch() {
			let finishWait: ((result: ExecResult) => void) | undefined;
			const exec = vi.fn(async (_command: string, args: string[]) => {
				if (!isQuietWait(args)) return execResult();
				return new Promise<ExecResult>((resolve) => {
					finishWait = resolve;
				});
			});
			const setup = setupExtension(exec);
			await setup.tool.execute(
				"call-watch",
				{ command: "prctl wait 1027", background: true },
				undefined,
				undefined,
				ctx,
			);
			finishWait?.(execResult());
			await vi.waitFor(() => expect(setup.sendMessage).toHaveBeenCalledOnce());
			// The final completion always sends a keep-working user nudge; drop it
			// so these tests assert only the watchdog's own sends.
			setup.sendUserMessage.mockClear();
			return setup;
		}

		it("nudges once when the run after the final completion ends silently", async () => {
			const { appendEntry, handlers, sendUserMessage } = await armWatch();

			await handlers.get("agent_end")?.(
				{
					messages: [
						assistantStop([
							{ type: "thinking", text: "" },
							{ type: "text", text: "" },
						]),
					],
				},
				ctx,
			);
			await handlers.get("agent_settled")?.({}, ctx);

			expect(sendUserMessage).toHaveBeenCalledOnce();
			expect(sendUserMessage.mock.calls[0]?.[0]).toContain("empty response");
			expect(sendUserMessage.mock.calls[0]?.[1]).toEqual({
				deliverAs: "followUp",
			});
			expect(appendEntry).toHaveBeenCalledWith("background-bash-empty-turn", {
				action: "nudged",
			});
		});

		it("stays armed and retries when the nudge cannot be delivered", async () => {
			const { appendEntry, handlers, sendUserMessage } = await armWatch();
			sendUserMessage.mockImplementationOnce(() => {
				throw new Error("Agent is already processing.");
			});
			const agentEnd = handlers.get("agent_end");
			const silentRun = {
				messages: [assistantStop([{ type: "text", text: "" }])],
			};

			await agentEnd?.(silentRun, ctx);
			await handlers.get("agent_settled")?.({}, ctx);
			expect(appendEntry).toHaveBeenCalledWith("background-bash-empty-turn", {
				action: "nudge-failed",
				error: "Agent is already processing.",
			});

			await handlers.get("agent_settled")?.({}, ctx);
			expect(sendUserMessage).toHaveBeenCalledTimes(2);
			expect(appendEntry).toHaveBeenCalledWith("background-bash-empty-turn", {
				action: "nudged",
			});
		});

		it("gives up after one nudge instead of looping", async () => {
			const { appendEntry, handlers, sendUserMessage } = await armWatch();
			const agentEnd = handlers.get("agent_end");
			const silentRun = {
				messages: [assistantStop([{ type: "text", text: "" }])],
			};

			await agentEnd?.(silentRun, ctx);
			await handlers.get("agent_settled")?.({}, ctx);
			await agentEnd?.(silentRun, ctx);
			await handlers.get("agent_settled")?.({}, ctx);
			await handlers.get("agent_settled")?.({}, ctx);

			expect(sendUserMessage).toHaveBeenCalledOnce();
			expect(appendEntry).toHaveBeenCalledWith("background-bash-empty-turn", {
				action: "gave-up",
			});
		});

		it("disarms when the run responds with text or tool calls", async () => {
			const textRun = await armWatch();
			const textAgentEnd = textRun.handlers.get("agent_end");
			await textAgentEnd?.(
				{
					messages: [
						assistantStop([{ type: "text", text: "CI is green; continuing." }]),
					],
				},
				ctx,
			);
			await textAgentEnd?.(
				{ messages: [assistantStop([{ type: "text", text: "" }])] },
				ctx,
			);
			expect(textRun.sendUserMessage).not.toHaveBeenCalled();

			const toolRun = await armWatch();
			await toolRun.handlers.get("agent_end")?.(
				{ messages: [assistantStop([{ type: "toolCall" }])] },
				ctx,
			);
			expect(toolRun.sendUserMessage).not.toHaveBeenCalled();
		});

		it("does not nudge aborted runs", async () => {
			const { handlers, sendUserMessage } = await armWatch();

			await handlers.get("agent_end")?.(
				{ messages: [assistantStop([{ type: "text", text: "" }], "aborted")] },
				ctx,
			);
			await handlers.get("agent_settled")?.({}, ctx);
			await handlers.get("agent_end")?.(
				{ messages: [assistantStop([{ type: "text", text: "" }])] },
				ctx,
			);
			await handlers.get("agent_settled")?.({}, ctx);

			expect(sendUserMessage).not.toHaveBeenCalled();
		});

		it("does not arm while other managed tasks remain", async () => {
			const finishWaits: Array<(result: ExecResult) => void> = [];
			const exec = vi.fn(async (_command: string, args: string[]) => {
				if (!isQuietWait(args)) return execResult();
				return new Promise<ExecResult>((resolve) => finishWaits.push(resolve));
			});
			const { handlers, sendMessage, sendUserMessage, tool } =
				setupExtension(exec);

			await tool.execute(
				"call-first",
				{ command: "first-task", background: true },
				undefined,
				undefined,
				ctx,
			);
			await tool.execute(
				"call-second",
				{ command: "second-task", background: true },
				undefined,
				undefined,
				ctx,
			);

			finishWaits[0]?.(execResult());
			await vi.waitFor(() => expect(sendMessage).toHaveBeenCalledTimes(1));
			const silentRun = {
				messages: [assistantStop([{ type: "text", text: "" }])],
			};
			await handlers.get("agent_end")?.(silentRun, ctx);
			await handlers.get("agent_settled")?.({}, ctx);
			expect(sendUserMessage).not.toHaveBeenCalled();

			finishWaits[1]?.(execResult());
			await vi.waitFor(() => expect(sendMessage).toHaveBeenCalledTimes(2));
			expect(sendUserMessage).toHaveBeenCalledOnce();
			await handlers.get("agent_end")?.(silentRun, ctx);
			await handlers.get("agent_settled")?.({}, ctx);
			expect(sendUserMessage).toHaveBeenCalledTimes(2);
			expect(sendUserMessage.mock.calls[1]?.[1]).toEqual({
				deliverAs: "followUp",
			});
		});
	});

	it("wakes on a background timeout without stopping the command", async () => {
		vi.useFakeTimers();
		try {
			let finishWait: ((result: ExecResult) => void) | undefined;
			const waitResult = new Promise<ExecResult>((resolve) => {
				finishWait = resolve;
			});
			const exec = vi.fn(async (_command: string, args: string[]) =>
				isQuietWait(args) ? waitResult : execResult(),
			);
			const { appendEntry, sendMessage, tool } = setupExtension(exec);

			const result = await tool.execute(
				"call-timeout",
				{ command: "slow-check", background: true, timeout: 5 },
				undefined,
				undefined,
				ctx,
			);
			expect(result.content[0]?.text).toContain(
				"woken without stopping the command",
			);

			await vi.advanceTimersByTimeAsync(5_000);
			expect(sendMessage).toHaveBeenCalledOnce();
			expect(sendMessage).toHaveBeenLastCalledWith(
				expect.objectContaining({
					customType: "background-bash-timeout",
					content: expect.stringContaining("was not stopped"),
					details: expect.objectContaining({ stillRunning: true }),
				}),
				{ deliverAs: "steer", triggerTurn: true },
			);
			expect(appendEntry).toHaveBeenLastCalledWith(
				"background-bash-task",
				expect.objectContaining({
					state: "running",
					timeoutNotification: "sent",
				}),
			);

			finishWait?.(execResult());
			await vi.advanceTimersByTimeAsync(250);
			expect(sendMessage).toHaveBeenCalledTimes(2);
			expect(sendMessage).toHaveBeenLastCalledWith(
				expect.objectContaining({
					customType: "background-bash-finished",
					content: expect.stringContaining("exit 0"),
				}),
				{ deliverAs: "steer", triggerTurn: false },
			);
		} finally {
			vi.useRealTimers();
		}
	});

	it("retries a failed timeout notification at a safe tool boundary", async () => {
		vi.useFakeTimers();
		try {
			const waitResult = new Promise<ExecResult>(() => {});
			const exec = vi.fn(async (_command: string, args: string[]) =>
				isQuietWait(args) ? waitResult : execResult(),
			);
			const { appendEntry, handlers, sendMessage, tool } = setupExtension(exec);
			sendMessage.mockImplementationOnce(() => {
				throw new Error("session temporarily busy");
			});

			await tool.execute(
				"call-timeout-retry",
				{ command: "slow-check", background: true, timeout: 5 },
				undefined,
				undefined,
				ctx,
			);
			await vi.advanceTimersByTimeAsync(5_000);
			expect(sendMessage).toHaveBeenCalledOnce();
			expect(appendEntry).toHaveBeenLastCalledWith(
				"background-bash-task",
				expect.objectContaining({ timeoutNotification: "pending" }),
			);

			await handlers.get("tool_execution_end")?.({}, ctx);
			expect(sendMessage).toHaveBeenCalledTimes(2);
			expect(appendEntry).toHaveBeenLastCalledWith(
				"background-bash-task",
				expect.objectContaining({ timeoutNotification: "sent" }),
			);
		} finally {
			vi.useRealTimers();
		}
	});

	it("does not send a timeout wake-up after early completion", async () => {
		vi.useFakeTimers();
		try {
			const exec = vi.fn(async () => execResult());
			const { sendMessage, tool } = setupExtension(exec);

			await tool.execute(
				"call-early",
				{ command: "quick-check", background: true, timeout: 5 },
				undefined,
				undefined,
				ctx,
			);
			await vi.advanceTimersByTimeAsync(250);
			expect(sendMessage).toHaveBeenCalledOnce();
			expect(sendMessage).toHaveBeenLastCalledWith(
				expect.objectContaining({
					customType: "background-bash-finished",
				}),
				{ deliverAs: "steer", triggerTurn: false },
			);

			await vi.advanceTimersByTimeAsync(5_000);
			expect(sendMessage).toHaveBeenCalledOnce();
		} finally {
			vi.useRealTimers();
		}
	});

	it("prunes completed, unattached background sessions older than 12 hours", async () => {
		const nowSeconds = Math.floor(Date.now() / 1000);
		const old = nowSeconds - 13 * 60 * 60;
		const recent = nowSeconds - 11 * 60 * 60;
		const listOutput = JSON.stringify([
			{
				name: "pi-bg-old",
				pid: 1,
				clients: 0,
				created: 1,
				ended: old,
				exit_code: 0,
			},
			{
				name: "pi-bg-recent",
				pid: 2,
				clients: 0,
				created: 1,
				ended: recent,
				exit_code: 0,
			},
			// Still running: zmx omits `ended` entirely rather than sending 0.
			{ name: "pi-bg-running", pid: 3, clients: 0, created: 1 },
			{
				name: "pi-bg-attached",
				pid: 4,
				clients: 1,
				created: 1,
				ended: old,
				exit_code: 0,
			},
			{
				name: "unrelated",
				pid: 5,
				clients: 0,
				created: 1,
				ended: old,
				exit_code: 0,
			},
			// Unreachable sessions carry `err` in place of the runtime fields.
			{ name: "pi-bg-dead", current: false, err: "ConnectionRefused" },
		]);
		const exec = vi.fn(async (_command: string, args: string[]) =>
			args[0] === "list" ? execResult({ stdout: listOutput }) : execResult(),
		);
		const { tool } = setupExtension(exec);

		await tool.execute(
			"call-prune",
			{ command: "just check", background: true },
			undefined,
			undefined,
			ctx,
		);

		expect(exec).toHaveBeenNthCalledWith(2, "zmx", ["kill", "pi-bg-old"], {
			cwd: "/tmp",
		});
		expect(exec).not.toHaveBeenCalledWith(
			"zmx",
			expect.arrayContaining([
				"pi-bg-recent",
				"pi-bg-running",
				"pi-bg-attached",
				"pi-bg-dead",
				"unrelated",
			]),
			expect.anything(),
		);
	});

	it("preserves foreground bash behavior through the timeout boundary", async () => {
		const exec = vi.fn(async () => execResult());
		const { tool } = setupExtension(exec);

		const result = await tool.execute(
			"call-foreground",
			{ command: "pwd", timeout: 600 },
			undefined,
			undefined,
			ctx,
		);

		expect(result.content[0]?.text.trim()).toBe("/tmp");
		expect(exec).not.toHaveBeenCalled();
	});

	it("automatically backgrounds foreground timeouts longer than ten minutes", async () => {
		const waitResult = new Promise<ExecResult>(() => {});
		const exec = vi.fn(async (_command: string, args: string[]) =>
			isQuietWait(args) ? waitResult : execResult(),
		);
		const { appendEntry, handlers, tool } = setupExtension(exec);

		const result = await tool.execute(
			"call-auto-background",
			{ command: "gauntlet-review", timeout: 601 },
			undefined,
			undefined,
			ctx,
		);

		expect(result.content[0]?.text).toContain(
			"Automatically sent to the background",
		);
		expect(exec).toHaveBeenCalledWith(
			"env",
			expect.arrayContaining([
				"zmx",
				"run",
				"-d",
				expect.stringMatching(/\/pi-bg-gauntlet-review-.*\.sh$/),
			]),
			{ cwd: "/tmp" },
		);
		expect(appendEntry).toHaveBeenCalledWith(
			"background-bash-task",
			expect.objectContaining({
				command: "gauntlet-review",
				timeoutSeconds: 601,
			}),
		);

		await handlers.get("session_shutdown")?.({}, ctx);
	});

	it("delivers a persisted pending completion after session restore", async () => {
		const exec = vi.fn(async () => execResult());
		const { appendEntry, handlers, sendMessage, sendUserMessage } =
			setupExtension(exec);
		const restoredCtx = {
			...ctx,
			sessionManager: {
				getBranch: () => [
					{
						type: "custom",
						customType: "background-bash-task",
						data: {
							version: 2,
							state: "finished",
							sessionName: "pi-bg-restored-finished",
							command: "just check",
							cwd: "/tmp",
							startedAt: Date.now() - 1_000,
							shellPath: "bash",
							markers: { start: "start", end: "end" },
							timeoutNotification: "none",
							completion: {
								exitCode: 0,
								durationMs: 1_000,
								output: "restored output",
							},
							completionNotification: "pending",
							completionWake: "none",
						},
					},
				],
			},
		} as unknown as ExtensionContext;

		await handlers.get("session_start")?.({}, restoredCtx);

		expect(sendMessage).toHaveBeenCalledOnce();
		expect(sendMessage.mock.calls[0]?.[0]).toEqual(
			expect.objectContaining({
				customType: "background-bash-finished",
				content: expect.stringContaining("restored output"),
			}),
		);
		expect(sendUserMessage).toHaveBeenCalledOnce();
		expect(appendEntry).toHaveBeenCalledWith(
			"background-bash-task",
			expect.objectContaining({ completionNotification: "sent" }),
		);
	});

	it("restores running task watchers from session state", async () => {
		const sessionName = "pi-bg-restored-call-123";
		const waitResult = new Promise<ExecResult>(() => {});
		const exec = vi.fn(async (_command: string, args: string[]) => {
			if (args[0] === "list") {
				return execResult({
					stdout: JSON.stringify([
						{ name: sessionName, pid: 1, clients: 0, created: 1 },
					]),
				});
			}
			return isQuietWait(args) ? waitResult : execResult();
		});
		const { appendEntry, handlers } = setupExtension(exec);
		const restoredCtx = {
			...ctx,
			sessionManager: {
				getBranch: () => [
					{
						type: "custom",
						customType: "background-bash-task",
						data: {
							version: 1,
							state: "running",
							sessionName,
							command: "prctl wait",
							cwd: "/tmp",
							startedAt: Date.now(),
							shellPath: "bash",
							markers: { start: "start", end: "end" },
							timeoutNotified: false,
						},
					},
				],
			},
		} as unknown as ExtensionContext;

		await handlers.get("session_start")?.({}, restoredCtx);

		expect(exec).toHaveBeenCalledWith("zmx", ["list", "--json"], {
			cwd: "/tmp",
		});
		expect(exec).toHaveBeenCalledWith(
			"bash",
			["-c", 'exec zmx wait "$1" >/dev/null', "pi-bg-wait", sessionName],
			expect.objectContaining({ cwd: "/tmp" }),
		);
		expect(setStatus).toHaveBeenLastCalledWith("background-bash", " 1");
		expect(appendEntry).not.toHaveBeenCalled();

		await handlers.get("session_shutdown")?.({}, restoredCtx);
	});

	it("stops watching without killing zmx work when the Pi session closes", async () => {
		let finishWait: ((result: ExecResult) => void) | undefined;
		const waitResult = new Promise<ExecResult>((resolve) => {
			finishWait = resolve;
		});
		const exec = vi.fn(
			async (_command: string, args: string[], _options?: ExecOptions) =>
				isQuietWait(args) ? waitResult : execResult(),
		);
		const { handlers, sendMessage, tool } = setupExtension(exec);

		await tool.execute(
			"call-shutdown",
			{ command: "long-task", background: true },
			undefined,
			undefined,
			ctx,
		);
		await handlers.get("session_shutdown")?.({}, ctx);

		const waitOptions = exec.mock.calls[2]?.[2] as ExecOptions;
		expect(waitOptions.signal?.aborted).toBe(true);
		finishWait?.(execResult());
		await new Promise((resolve) => setTimeout(resolve, 0));
		expect(sendMessage).not.toHaveBeenCalled();
		expect(exec).not.toHaveBeenCalledWith(
			"zmx",
			expect.arrayContaining(["kill"]),
			expect.anything(),
		);
	});

	it("reports a failed background command with its recent output", async () => {
		const exec = vi.fn(async (_command: string, args: string[]) =>
			isQuietWait(args)
				? execResult({ code: 7, stderr: "tests failed" })
				: execResult(),
		);
		const { sendMessage, tool } = setupExtension(exec);

		await tool.execute(
			"call-failed",
			{ command: "just test", background: true },
			undefined,
			undefined,
			ctx,
		);

		await vi.waitFor(() => expect(sendMessage).toHaveBeenCalledOnce());
		const message = sendMessage.mock.calls[0]?.[0] as { content: string };
		expect(message.content).toContain("exit 7");
		expect(message.content).toContain("tests failed");
		expect(message.content).toContain("zmx history");
	});
});
