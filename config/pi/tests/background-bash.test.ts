import type {
	ExecOptions,
	ExecResult,
	ExtensionAPI,
	ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { beforeEach, describe, expect, it, vi } from "vitest";
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
	} as unknown as ExtensionAPI;

	backgroundBashExtension(pi);
	if (!tool) throw new Error("bash tool was not registered");

	return { appendEntry, handlers, sendMessage, tool };
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

		const { appendEntry, sendMessage, tool } = setupExtension(exec);

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
		expect(exec).toHaveBeenNthCalledWith(1, "zmx", ["list"], {
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
				"-c",
				expect.stringContaining("pi_bg_exit_code"),
				"pi-bg-control",
				expect.any(String),
				"just check",
				expect.stringMatching(/^__PI_BG_OUTPUT_START_/),
				expect.stringMatching(/^__PI_BG_OUTPUT_END_/),
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
		const startMarker = launchArgs.at(-2) ?? "";
		const endMarker = launchArgs.at(-1) ?? "";
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

	it("reports how many managed tasks remain after each completion", async () => {
		const finishWaits: Array<(result: ExecResult) => void> = [];
		const exec = vi.fn(async (_command: string, args: string[]) => {
			if (!isQuietWait(args)) return execResult();
			return new Promise<ExecResult>((resolve) => finishWaits.push(resolve));
		});
		const { sendMessage, tool } = setupExtension(exec);

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
				expect.objectContaining({ state: "running", timeoutNotified: true }),
			);

			finishWait?.(execResult());
			await vi.advanceTimersByTimeAsync(0);
			expect(sendMessage).toHaveBeenCalledTimes(2);
			expect(sendMessage).toHaveBeenLastCalledWith(
				expect.objectContaining({
					customType: "background-bash-finished",
					content: expect.stringContaining("exit 0"),
				}),
				{ deliverAs: "steer", triggerTurn: true },
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
			await vi.advanceTimersByTimeAsync(0);
			expect(sendMessage).toHaveBeenCalledOnce();
			expect(sendMessage).toHaveBeenLastCalledWith(
				expect.objectContaining({
					customType: "background-bash-finished",
				}),
				{ deliverAs: "steer", triggerTurn: true },
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
		const listOutput = [
			`name=pi-bg-old\tpid=1\tclients=0\tcreated=1\tended=${old}\texit_code=0`,
			`name=pi-bg-recent\tpid=2\tclients=0\tcreated=1\tended=${recent}\texit_code=0`,
			`name=pi-bg-running\tpid=3\tclients=0\tcreated=1`,
			`name=pi-bg-attached\tpid=4\tclients=1\tcreated=1\tended=${old}\texit_code=0`,
			`name=unrelated\tpid=5\tclients=0\tcreated=1\tended=${old}\texit_code=0`,
		].join("\n");
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
			expect.arrayContaining(["zmx", "run", "-d", "gauntlet-review"]),
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

	it("restores running task watchers from session state", async () => {
		const sessionName = "pi-bg-restored-call-123";
		const waitResult = new Promise<ExecResult>(() => {});
		const exec = vi.fn(async (_command: string, args: string[]) => {
			if (args[0] === "list") {
				return execResult({
					stdout: `name=${sessionName}\tpid=1\tclients=0\tcreated=1`,
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

		expect(exec).toHaveBeenCalledWith("zmx", ["list"], { cwd: "/tmp" });
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
