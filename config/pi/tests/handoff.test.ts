import { describe, expect, it, vi } from "vitest";
import handoffExtension, {
	buildFreshSessionPrompt,
	buildHandoffRequest,
} from "../extensions/handoff.ts";

type CommandHandler = (args: string, ctx: never) => Promise<void>;

describe("handoff extension", () => {
	it("asks the live agent for a bounded transfer note", () => {
		const request = buildHandoffRequest(
			"implement phase two",
			"```text\n M src/main.ts\n```",
		);
		expect(request).toContain("native compaction");
		expect(request).toContain("## Decisions and rationale");
		expect(request).toContain(" M src/main.ts");
		expect(request).toContain("Do not call tools");
	});

	it("marks parent retrieval as narrow and optional", () => {
		const prompt = buildFreshSessionPrompt(
			"implement phase two",
			"## Current state\nPhase one is complete.",
			"/sessions/parent.jsonl",
			"Working tree clean.",
		);
		expect(prompt).toContain("## Task\n\nimplement phase two");
		expect(prompt).toContain("Parent session: `/sessions/parent.jsonl`");
		expect(prompt).toContain("specific missing fact");
		expect(prompt).toContain("Do not reconstruct");
	});

	it("generates with tools disabled and opens a parent-linked review session", async () => {
		const commands = new Map<string, CommandHandler>();
		const branch: unknown[] = [
			{
				type: "message",
				message: { role: "user", content: "current task" },
			},
		];
		const setActiveTools = vi.fn();
		const setEditorText = vi.fn();
		const notify = vi.fn();
		const newSession = vi.fn(
			async (options: {
				parentSession?: string;
				withSession?: (ctx: unknown) => Promise<void>;
			}) => {
				await options.withSession?.({
					ui: { setEditorText, notify },
				});
				return { cancelled: false };
			},
		);
		const pi = {
			registerCommand(name: string, command: { handler: CommandHandler }) {
				commands.set(name, command.handler);
			},
			getActiveTools: () => ["read", "bash"],
			setActiveTools,
			sendMessage: vi.fn(() => {
				branch.push({
					type: "message",
					message: {
						role: "assistant",
						stopReason: "stop",
						content: [{ type: "text", text: "## Current state\nReady." }],
					},
				});
			}),
			exec: vi.fn(async (_command: string, args: string[]) => ({
				code: 0,
				stdout:
					args[0] === "status"
						? "## main\n M src/main.ts\n"
						: "1 file changed\n",
				stderr: "",
				killed: false,
			})),
		};
		const ctx = {
			model: { id: "gpt-test" },
			cwd: "/repo",
			isIdle: () => true,
			ui: { notify },
			sessionManager: {
				getSessionFile: () => "/sessions/parent.jsonl",
				getBranch: () => branch,
			},
			newSession,
		};

		handoffExtension(pi as never);
		await commands.get("handoff")?.("implement phase two", ctx as never);

		expect(setActiveTools.mock.calls).toEqual([[[]], [["read", "bash"]]]);
		expect(newSession).toHaveBeenCalledWith(
			expect.objectContaining({ parentSession: "/sessions/parent.jsonl" }),
		);
		expect(setEditorText).toHaveBeenCalledOnce();
		expect(setEditorText.mock.calls[0][0]).toContain(
			"## Current state\nReady.",
		);
		expect(setEditorText.mock.calls[0][0]).toContain("M src/main.ts");
	});
});
