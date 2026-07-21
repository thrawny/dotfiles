import { describe, expect, it, vi } from "vitest";
import historyQueryExtension from "../extensions/history-query.ts";

describe("history query extension", () => {
	it("defaults to the parent and enforces bounded CLI arguments", async () => {
		let tool: { execute: (...args: never[]) => Promise<unknown> } | undefined;
		const exec = vi.fn(async () => ({
			code: 0,
			stdout: '{"matches":[]}',
			stderr: "",
			killed: false,
		}));
		const pi = {
			registerTool(value: typeof tool) {
				tool = value;
			},
			exec,
		};
		historyQueryExtension(pi as never);

		const result = (await tool?.execute(
			"call-1" as never,
			{ query: "sqlite rationale", limit: 99 } as never,
			undefined as never,
			undefined as never,
			{
				cwd: "/repo",
				sessionManager: {
					getHeader: () => ({ parentSession: "/sessions/parent.jsonl" }),
				},
			} as never,
		)) as { content: { text: string }[] };

		expect(exec).toHaveBeenCalledWith(
			"agent-history",
			[
				"query",
				"/sessions/parent.jsonl",
				"sqlite rationale",
				"--limit",
				"3",
				"--max-chars",
				"8000",
			],
			expect.objectContaining({ cwd: "/repo", timeout: 15_000 }),
		);
		expect(result.content[0].text).toBe('{"matches":[]}');
	});
});
