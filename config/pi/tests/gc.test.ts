import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { describe, expect, it } from "vitest";
import gcExtension, { buildGcPrompt } from "../extensions/gc.ts";

const context = {
	status: "STATUS",
	diff: "DIFF",
	log: "LOG",
};

describe("gc prompt expansion", () => {
	it("includes Git context and the user instruction", () => {
		expect(buildGcPrompt("all", context)).toBe(`## Context

### Git status

STATUS

### Diff (staged and unstaged)

DIFF

### Recent commits

LOG

## Your task

User commit instruction: all

Create a single git commit for only the changes you have been working on in this session.

Do not stage unrelated worktree changes, even if they appear in the status or diff. Use the conversation context to identify your changes. If the user supplied explicit commit instructions, follow them instead; for example, \`all\`, \`--all\`, or \`-a\` means include every changed file, and explicit paths/scopes mean include matching files.

You have the capability to call multiple tools in a single response. Stage the selected files and create the commit using a single message. Do not use any other tools or do anything else. Do not send any other text or messages besides these tool calls.
`);
	});

	it("omits the user instruction when no arguments are supplied", () => {
		const prompt = buildGcPrompt("", context);

		expect(prompt).not.toContain("User commit instruction:");
		expect(prompt).toContain("## Your task\n\nCreate a single git commit");
	});
});

describe("gc extension", () => {
	it("temporarily disables thinking and sends the expanded visible prompt", async () => {
		let command:
			| ((args: string, ctx: { cwd: string }) => Promise<void> | void)
			| undefined;
		let agentEnd: (() => Promise<void> | void) | undefined;
		let thinking = "high";
		const sent: Array<{ message: unknown; options: unknown }> = [];

		const pi = {
			registerMessageRenderer() {},
			registerCommand(
				name: string,
				options: {
					handler: (args: string, ctx: { cwd: string }) => Promise<void> | void;
				},
			) {
				expect(name).toBe("gc");
				command = options.handler;
			},
			on(event: string, handler: () => Promise<void> | void) {
				if (event === "agent_end") agentEnd = handler;
			},
			getThinkingLevel: () => thinking,
			setThinkingLevel(level: string) {
				thinking = level;
			},
			sendMessage(message: unknown, options: unknown) {
				sent.push({ message, options });
			},
		} as unknown as ExtensionAPI;

		gcExtension(pi);
		await command?.("all", { cwd: process.cwd() });

		expect(thinking).toBe("off");
		expect(sent).toHaveLength(1);
		expect(sent[0]).toMatchObject({
			message: {
				customType: "gc-prompt",
				display: true,
				details: { invocation: "/gc all" },
				content: expect.stringContaining("User commit instruction: all"),
			},
			options: { triggerTurn: true },
		});

		await agentEnd?.();
		expect(thinking).toBe("high");
	});
});
