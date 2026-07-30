import { beforeEach, describe, expect, it, vi } from "vitest";

const { accessSync, execFileSync } = vi.hoisted(() => ({
	accessSync: vi.fn(),
	execFileSync: vi.fn(),
}));

vi.mock("node:child_process", () => ({ execFileSync }));
vi.mock("node:fs", () => ({ accessSync, constants: { X_OK: 1 } }));

import agentSwitch from "../extensions/agent-switch.ts";

type Handler = (event: unknown, ctx: unknown) => Promise<void>;

describe("agent-switch lifecycle mapping", () => {
	beforeEach(() => {
		accessSync.mockReset();
		execFileSync.mockReset();
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
