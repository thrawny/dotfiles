import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const { accessSync, execFileSync, mkdirSync, watch } = vi.hoisted(() => ({
	accessSync: vi.fn(),
	execFileSync: vi.fn(),
	mkdirSync: vi.fn(),
	watch: vi.fn(),
}));

vi.mock("node:child_process", () => ({ execFileSync }));
vi.mock("node:fs", () => ({
	accessSync,
	mkdirSync,
	watch,
	constants: { X_OK: 1 },
}));

import agentSwitch from "../extensions/agent-switch.ts";

type Handler = (event: unknown, ctx: unknown) => Promise<void>;

describe("agent-switch lifecycle mapping", () => {
	beforeEach(() => {
		vi.stubEnv("HERDR_ENV", undefined);
		accessSync.mockReset();
		execFileSync.mockReset();
		mkdirSync.mockReset();
		watch.mockReset();
	});

	afterEach(() => vi.unstubAllEnvs());

	it("does not register hooks or a rename watcher inside Herdr", () => {
		vi.stubEnv("HERDR_ENV", "1");
		const on = vi.fn();
		agentSwitch({ on } as never);
		expect(on).not.toHaveBeenCalled();
		expect(accessSync).not.toHaveBeenCalled();
		expect(execFileSync).not.toHaveBeenCalled();
		expect(mkdirSync).not.toHaveBeenCalled();
		expect(watch).not.toHaveBeenCalled();
	});

	it("still registers hooks when HERDR_ENV is zero", () => {
		vi.stubEnv("HERDR_ENV", "0");
		const on = vi.fn();
		agentSwitch({ on } as never);
		expect(on).toHaveBeenCalled();
	});

	it("stays dormant when agent-switch is not on PATH", () => {
		accessSync.mockImplementation(() => {
			throw new Error("not found");
		});
		const on = vi.fn();

		agentSwitch({ on } as never);

		expect(on).not.toHaveBeenCalled();
		expect(execFileSync).not.toHaveBeenCalled();
	});

	it("tracks prompt-level starts and fully settled stops", async () => {
		accessSync.mockReturnValue(undefined);
		const handlers = new Map<string, Handler>();
		const pi = {
			on(event: string, handler: Handler) {
				handlers.set(event, handler);
			},
			getSessionName() {
				return undefined;
			},
		};
		const ctx = {
			cwd: "/work/project",
			hasUI: false,
			sessionManager: {
				getSessionFile: () => "/sessions/session-123.jsonl",
			},
			ui: { notify: vi.fn() },
		};

		agentSwitch(pi as never);

		expect(handlers.has("before_agent_start")).toBe(true);
		expect(handlers.has("agent_settled")).toBe(true);
		expect(handlers.has("agent_start")).toBe(false);
		expect(handlers.has("agent_end")).toBe(false);

		await handlers.get("before_agent_start")?.({}, ctx);
		await handlers.get("agent_settled")?.({}, ctx);

		expect(execFileSync).toHaveBeenCalledTimes(2);
		expect(execFileSync.mock.calls.map((call) => call[1])).toEqual([
			["track", "prompt-submit"],
			["track", "stop"],
		]);
	});
});
