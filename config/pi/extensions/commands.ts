import { execFileSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { UserMessageComponent, type ExtensionAPI } from "@mariozechner/pi-coding-agent";

interface CommandFile {
	name: string;
	description?: string;
	argumentHint?: string;
	thinking?: "off" | "minimal" | "low" | "medium" | "high" | "xhigh";
	body: string;
}

interface PendingState {
	previousThinking?: ReturnType<ExtensionAPI["getThinkingLevel"]>;
}

let pendingState: PendingState | undefined;

function extensionDir(): string {
	return path.dirname(fileURLToPath(import.meta.url));
}

function commandsDir(): string {
	return path.resolve(extensionDir(), "..", "commands");
}

function parseCommandFile(filePath: string): CommandFile {
	const name = path.basename(filePath, ".md");
	const text = readFileSync(filePath, "utf8");
	const match = text.match(/^---\n([\s\S]*?)\n---\n?/);
	const frontmatter = match?.[1] ?? "";
	const body = match ? text.slice(match[0].length) : text;

	return {
		name,
		description: frontmatterValue(frontmatter, "description"),
		argumentHint: frontmatterValue(frontmatter, "argument-hint"),
		thinking: parseThinking(frontmatterValue(frontmatter, "thinking")),
		body,
	};
}

function frontmatterValue(frontmatter: string, key: string): string | undefined {
	const line = frontmatter.split("\n").find((item) => item.trim().startsWith(`${key}:`));
	return line?.slice(line.indexOf(":") + 1).trim().replace(/^['"]|['"]$/g, "") || undefined;
}

function parseThinking(value: string | undefined): CommandFile["thinking"] | undefined {
	if (!value) return undefined;
	if (["off", "minimal", "low", "medium", "high", "xhigh"].includes(value)) return value as CommandFile["thinking"];
	throw new Error(`Invalid thinking level: ${value}`);
}

function expandArguments(template: string, args: string): string {
	const parts = args.trim() ? args.trim().split(/\s+/) : [];
	return template
		.replace(/\$ARGUMENTS/g, args)
		.replace(/\$@/g, args)
		.replace(/\$(\d+)/g, (_match, index: string) => parts[Number(index) - 1] ?? "");
}

function expandShell(template: string, cwd: string): string {
	return template.replace(/!`([^`]+)`/g, (_match, command: string) => shell(cwd, command));
}

function shell(cwd: string, command: string): string {
	return execFileSync("bash", ["-lc", command], {
		cwd,
		encoding: "utf8",
		stdio: ["ignore", "pipe", "pipe"],
	}).trim();
}

function restoreState(pi: ExtensionAPI): void {
	if (!pendingState) return;
	if (pendingState.previousThinking) pi.setThinkingLevel(pendingState.previousThinking);
	pendingState = undefined;
}

export default function (pi: ExtensionAPI) {
	pi.registerMessageRenderer("command-prompt", (message, options, theme) => {
		const details = message.details as { commandName?: string; invocation?: string } | undefined;
		const commandName = details?.commandName ?? "command";
		const invocation = details?.invocation ?? `/${commandName}`;
		const content = typeof message.content === "string" ? message.content : JSON.stringify(message.content, null, 2);

		if (!options.expanded) {
			return new UserMessageComponent(invocation);
		}

		return new UserMessageComponent(`${invocation}\n\n${content}`);
	});

	const dir = commandsDir();
	if (!existsSync(dir)) return;

	for (const file of readdirSync(dir).filter((entry) => entry.endsWith(".md"))) {
		const command = parseCommandFile(path.join(dir, file));

		pi.registerCommand(command.name, {
			description: command.description,
			getArgumentCompletions: () => null,
			handler: async (args, ctx) => {
				const invocation = `/${command.name}${args.trim() ? ` ${args.trim()}` : ""}`;
				const expanded = expandShell(expandArguments(command.body, args), ctx.cwd);

				pendingState = {
					previousThinking: command.thinking ? pi.getThinkingLevel() : undefined,
				};

				if (command.thinking) pi.setThinkingLevel(command.thinking);

				pi.sendMessage(
					{
						customType: "command-prompt",
						content: expanded,
						display: true,
						details: { commandName: command.name, invocation },
					},
					{ triggerTurn: true },
				);
			},
		});
	}

	pi.on("agent_end", async () => {
		restoreState(pi);
	});
}
