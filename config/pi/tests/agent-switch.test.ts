import { beforeEach, describe, expect, it, vi } from "vitest";

const { execFileSync } = vi.hoisted(() => ({
	execFileSync: vi.fn(),
}));

vi.mock("node:child_process", () => ({ execFileSync }));

import agentSwitch from "../extensions/agent-switch.ts";

type Handler = (event: unknown, ctx: unknown) => Promise<void>;

describe("agent-switch lifecycle mapping", () => {
	beforeEach(() => {
		execFileSync.mockReset();
	});

	it("tracks prompt-level starts and fully settled stops", async () => {
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
