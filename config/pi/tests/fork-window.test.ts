import type {
	ExtensionAPI,
	ExtensionCommandContext,
} from "@earendil-works/pi-coding-agent";
import { describe, expect, it, vi } from "vitest";
import forkWindow from "../extensions/fork-window.ts";

function setup() {
	let handler!: (args: string, ctx: ExtensionCommandContext) => Promise<void>;
	const exec = vi.fn().mockResolvedValue({
		code: 0,
		stdout: "Fork launch requested.\n",
		stderr: "",
	});
	forkWindow({
		registerCommand(
			name: string,
			options: Parameters<ExtensionAPI["registerCommand"]>[1],
		) {
			expect(name).toBe("fork-window");
			handler = options.handler as typeof handler;
		},
		exec,
	} as unknown as ExtensionAPI);
	const notify = vi.fn();
	const ctx = {
		cwd: "/project with spaces",
		isIdle: () => true,
		sessionManager: { getSessionFile: () => "/sessions/current.jsonl" },
		ui: { notify },
	} as unknown as ExtensionCommandContext;
	return { handler, exec, notify, ctx };
}

describe("fork-window", () => {
	it("passes the exact session and cwd without changing the original session", async () => {
		const { handler, exec, notify, ctx } = setup();
		await handler("", ctx);
		expect(exec).toHaveBeenCalledWith("fork-window", [
			"pi",
			"/sessions/current.jsonl",
			"--cwd",
			"/project with spaces",
		]);
		expect(notify).toHaveBeenCalledWith("Fork launch requested.", "info");
	});

	it.each(["arguments", "busy", "ephemeral"])("rejects %s", async (reason) => {
		const { handler, exec, notify, ctx } = setup();
		if (reason === "busy") ctx.isIdle = () => false;
		if (reason === "ephemeral")
			ctx.sessionManager.getSessionFile = () => undefined;
		await handler(reason === "arguments" ? "extra" : "", ctx);
		expect(exec).not.toHaveBeenCalled();
		expect(notify).toHaveBeenCalledWith(expect.any(String), "error");
	});

	it("reports launch errors", async () => {
		const { handler, exec, notify, ctx } = setup();
		exec.mockResolvedValue({ code: 1, stdout: "", stderr: "No desktop\n" });
		await handler("", ctx);
		expect(notify).toHaveBeenCalledWith("No desktop", "error");
	});

	it("reports an unavailable launcher", async () => {
		const { handler, exec, notify, ctx } = setup();
		exec.mockRejectedValue(new Error("ENOENT"));
		await handler("", ctx);
		expect(notify).toHaveBeenCalledWith("Error: ENOENT", "error");
	});
});
