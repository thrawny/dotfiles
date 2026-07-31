import { execFileSync } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { UserMessageComponent } from "@earendil-works/pi-coding-agent";
import { Box, Text } from "@earendil-works/pi-tui";

type ThinkingLevel = ReturnType<ExtensionAPI["getThinkingLevel"]>;

export interface GcContext {
	status: string;
	diff: string;
	log: string;
}

let thinkingBeforeGc: ThinkingLevel | undefined;

function git(cwd: string, args: string[]): string {
	return execFileSync("git", args, {
		cwd,
		encoding: "utf8",
		stdio: ["ignore", "pipe", "pipe"],
	}).trim();
}

function readGcContext(cwd: string): GcContext {
	return {
		status: git(cwd, ["status"]),
		diff: git(cwd, ["diff", "HEAD"]),
		log: git(cwd, ["log", "--oneline", "-10"]),
	};
}

export function buildGcPrompt(args: string, context: GcContext): string {
	const userInstruction = args.trim()
		? `User commit instruction: ${args}\n\n`
		: "";

	return `## Context

### Git status

${context.status}

### Diff (staged and unstaged)

${context.diff}

### Recent commits

${context.log}

## Your task

${userInstruction}Create a single git commit for only the changes you have been working on in this session.

Do not stage unrelated worktree changes, even if they appear in the status or diff. Use the conversation context to identify your changes. If the user supplied explicit commit instructions, follow them instead; for example, \`all\`, \`--all\`, or \`-a\` means include every changed file, and explicit paths/scopes mean include matching files.

You have the capability to call multiple tools in a single response. Stage the selected files and create the commit using a single message. Do not use any other tools or do anything else. Do not send any other text or messages besides these tool calls.
`;
}

function restoreThinking(pi: ExtensionAPI): void {
	if (thinkingBeforeGc !== undefined) {
		pi.setThinkingLevel(thinkingBeforeGc);
	}
	thinkingBeforeGc = undefined;
}

export default function gcExtension(pi: ExtensionAPI) {
	pi.registerMessageRenderer("gc-prompt", (message, options, theme) => {
		const { invocation } = message.details as { invocation: string };
		const content = message.content as string;

		if (!options.expanded) return new UserMessageComponent(invocation);

		const box = new Box(1, 1, (text) => theme.bg("userMessageBg", text));
		box.addChild(
			new Text(
				theme.fg("userMessageText", `${invocation}\n\n${content}`),
				0,
				0,
			),
		);
		return box;
	});

	pi.registerCommand("gc", {
		description: "Create a git commit",
		handler: async (args, ctx) => {
			const invocation = `/gc${args.trim() ? ` ${args.trim()}` : ""}`;
			const prompt = buildGcPrompt(args, readGcContext(ctx.cwd));

			thinkingBeforeGc = pi.getThinkingLevel();
			pi.setThinkingLevel("off");
			pi.sendMessage(
				{
					customType: "gc-prompt",
					content: prompt,
					display: true,
					details: { invocation },
				},
				{ triggerTurn: true },
			);
		},
	});

	pi.on("agent_end", () => {
		restoreThinking(pi);
	});
}
