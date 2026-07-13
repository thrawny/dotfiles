import type {
	ExecOptions,
	ExecResult,
	ExtensionAPI,
	ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { describe, expect, it, vi } from "vitest";
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
	const pi = {
		exec,
		on(event: string, handler: EventHandler) {
			handlers.set(event, handler);
		},
		registerTool(value: RegisteredBashTool) {
			tool = value;
		},
		sendMessage,
	} as unknown as ExtensionAPI;

	backgroundBashExtension(pi);
	if (!tool) throw new Error("bash tool was not registered");

	return { handlers, sendMessage, tool };
}

const ctx = { cwd: "/tmp", mode: "tui" } as unknown as ExtensionContext;

describe("background bash", () => {
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

	it("returns immediately and wakes the agent when the zmx task finishes", async () => {
		let finishWait: ((result: ExecResult) => void) | undefined;
		const waitResult = new Promise<ExecResult>((resolve) => {
			finishWait = resolve;
		});
		const exec = vi.fn(
			async (_command: string, args: string[], _options?: ExecOptions) =>
				args[0] === "wait" ? waitResult : execResult(),
		);

		const { sendMessage, tool } = setupExtension(exec);

		expect(tool.parameters.properties).toHaveProperty("background");
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
				"just check",
			],
			{ cwd: "/tmp" },
		);
		expect(exec).toHaveBeenNthCalledWith(
			3,
			"zmx",
			["wait", expect.stringMatching(/^pi-bg-/)],
			expect.objectContaining({ cwd: "/tmp" }),
		);
		expect(sendMessage).not.toHaveBeenCalled();

		finishWait?.(execResult());
		await vi.waitFor(() => expect(sendMessage).toHaveBeenCalledOnce());
		expect(sendMessage).toHaveBeenCalledWith(
			expect.objectContaining({
				customType: "background-bash-finished",
				content: expect.stringContaining("exit 0"),
				display: true,
			}),
			{ deliverAs: "steer", triggerTurn: true },
		);
	});

	it("wakes on a background timeout without stopping the command", async () => {
		vi.useFakeTimers();
		try {
			let finishWait: ((result: ExecResult) => void) | undefined;
			const waitResult = new Promise<ExecResult>((resolve) => {
				finishWait = resolve;
			});
			const exec = vi.fn(async (_command: string, args: string[]) =>
				args[0] === "wait" ? waitResult : execResult(),
			);
			const { sendMessage, tool } = setupExtension(exec);

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

	it("preserves foreground bash behavior in the context working directory", async () => {
		const exec = vi.fn(async () => execResult());
		const { tool } = setupExtension(exec);

		const result = await tool.execute(
			"call-foreground",
			{ command: "pwd" },
			undefined,
			undefined,
			ctx,
		);

		expect(result.content[0]?.text.trim()).toBe("/tmp");
		expect(exec).not.toHaveBeenCalled();
	});

	it("stops watching without killing zmx work when the Pi session closes", async () => {
		let finishWait: ((result: ExecResult) => void) | undefined;
		const waitResult = new Promise<ExecResult>((resolve) => {
			finishWait = resolve;
		});
		const exec = vi.fn(
			async (_command: string, args: string[], _options?: ExecOptions) =>
				args[0] === "wait" ? waitResult : execResult(),
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
			args[0] === "wait"
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
