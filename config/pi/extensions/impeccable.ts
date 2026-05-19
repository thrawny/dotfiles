import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import {
	type ExtensionAPI,
	type ExtensionCommandContext,
	UserMessageComponent,
} from "@mariozechner/pi-coding-agent";
import { type AutocompleteItem, Box, Text } from "@mariozechner/pi-tui";

interface CommandMetadata {
	description?: string;
	argumentHint?: string;
}

const FALLBACK_SUBCOMMANDS = [
	"craft",
	"shape",
	"audit",
	"critique",
	"animate",
	"bolder",
	"colorize",
	"delight",
	"layout",
	"overdrive",
	"quieter",
	"typeset",
	"adapt",
	"clarify",
	"distill",
	"harden",
	"onboard",
	"optimize",
	"polish",
	"teach",
	"document",
	"extract",
	"live",
] as const;

function parseFrontmatter(markdown: string): {
	frontmatter: Record<string, string>;
	body: string;
} {
	const match = markdown.match(/^---\n([\s\S]*?)\n---\n?/);
	if (!match) return { frontmatter: {}, body: markdown.trim() };

	const frontmatter: Record<string, string> = {};
	for (const line of match[1]?.split("\n") ?? []) {
		const separator = line.indexOf(":");
		if (separator <= 0) continue;
		const key = line.slice(0, separator).trim();
		const value = line
			.slice(separator + 1)
			.trim()
			.replace(/^['"]|['"]$/g, "");
		frontmatter[key] = value;
	}

	return { frontmatter, body: markdown.slice(match[0].length).trim() };
}

function stripFrontmatter(markdown: string): string {
	return parseFrontmatter(markdown).body;
}

function findGitRoot(start: string): string | undefined {
	let current = path.resolve(start);
	while (true) {
		if (existsSync(path.join(current, ".git"))) return current;
		const parent = path.dirname(current);
		if (parent === current) return undefined;
		current = parent;
	}
}

function findImpeccableSkill(cwd: string): string | undefined {
	const root = findGitRoot(cwd);
	let current = path.resolve(cwd);

	while (true) {
		for (const relative of [
			path.join(".pi", "skills", "impeccable", "SKILL.md"),
			path.join(".agents", "skills", "impeccable", "SKILL.md"),
		]) {
			const candidate = path.join(current, relative);
			if (existsSync(candidate)) return candidate;
		}

		if (current === root) return undefined;
		const parent = path.dirname(current);
		if (parent === current) return undefined;
		current = parent;
	}
}

function loadCommandMetadata(
	skillPath: string,
): Record<string, CommandMetadata> {
	const metadataPath = path.join(
		path.dirname(skillPath),
		"scripts",
		"command-metadata.json",
	);
	if (existsSync(metadataPath)) {
		const parsed = JSON.parse(readFileSync(metadataPath, "utf8")) as Record<
			string,
			CommandMetadata
		>;
		return parsed;
	}

	const { frontmatter } = parseFrontmatter(readFileSync(skillPath, "utf8"));
	const argumentHint = frontmatter["argument-hint"] ?? "";
	const commandGroup = argumentHint.match(/\[([^\]]*\|[^\]]*)\]/)?.[1] ?? "";
	const names = commandGroup
		.split(/[|·]/)
		.map((name) => name.trim())
		.filter(Boolean);

	return Object.fromEntries(
		(names.length > 0 ? names : FALLBACK_SUBCOMMANDS).map((name) => [
			name,
			{ argumentHint: "[target]" },
		]),
	);
}

function buildSubcommandReferenceBlock(
	skillPath: string,
	args: string,
): string | undefined {
	const subcommand = args.trim().split(/\s+/, 1)[0]?.toLowerCase();
	if (!subcommand) return undefined;
	if (!loadCommandMetadata(skillPath)[subcommand]) return undefined;

	const referencePath = path.join(
		path.dirname(skillPath),
		"reference",
		`${subcommand}.md`,
	);
	if (!existsSync(referencePath)) return undefined;

	const location = referencePath.replaceAll("\\", "/");
	const body = readFileSync(referencePath, "utf8").trim();
	return `<reference name="${subcommand}" location="${location}">\n${body}\n</reference>`;
}

function buildSkillPrompt(skillPath: string, args: string): string {
	const body = stripFrontmatter(readFileSync(skillPath, "utf8"));
	const baseDir = path.dirname(skillPath).replaceAll("\\", "/");
	const location = skillPath.replaceAll("\\", "/");
	const userArgs =
		args.trim() || "Use the impeccable skill for the current design task.";
	const referenceBlock = buildSubcommandReferenceBlock(skillPath, args);
	const blocks = [
		`<skill name="impeccable" location="${location}">\nReferences and scripts are relative to ${baseDir}.\n\n${body}\n</skill>`,
		referenceBlock,
		`User: ${userArgs}`,
	].filter(Boolean);

	return blocks.join("\n\n");
}

function completeSubcommand(
	skillPath: string,
	prefix: string,
): AutocompleteItem[] | null {
	if (prefix.trim().includes(" ")) return null;

	const query = prefix.trim().toLowerCase();
	const metadata = loadCommandMetadata(skillPath);
	const matches = Object.entries(metadata)
		.filter(([name]) => name.toLowerCase().startsWith(query))
		.map(([name, command]) => ({
			value: name,
			label: command.argumentHint
				? `${name} ${command.argumentHint}`.trim()
				: name,
			description: command.description,
		}));

	return matches.length > 0 ? matches : null;
}

function registerImpeccableCommand(pi: ExtensionAPI, skillPath: string): void {
	pi.registerCommand("impeccable", {
		description: "Run the project-local Impeccable skill",
		getArgumentCompletions: (prefix: string) => {
			const currentSkillPath = findImpeccableSkill(process.cwd()) ?? skillPath;
			return completeSubcommand(currentSkillPath, prefix);
		},
		handler: async (args: string, ctx: ExtensionCommandContext) => {
			const currentSkillPath = findImpeccableSkill(ctx.cwd) ?? skillPath;
			const trimmedArgs = args.trim();
			const invocation = trimmedArgs
				? `/impeccable ${trimmedArgs}`
				: "/impeccable";

			pi.sendMessage(
				{
					customType: "impeccable-prompt",
					content: buildSkillPrompt(currentSkillPath, trimmedArgs),
					display: true,
					details: { invocation },
				},
				{ triggerTurn: true },
			);
		},
	});
}

export default function (pi: ExtensionAPI) {
	pi.registerMessageRenderer("impeccable-prompt", (message, options, theme) => {
		const details = message.details as { invocation?: string } | undefined;
		const invocation = details?.invocation ?? "/impeccable";

		if (!options.expanded) return new UserMessageComponent(invocation);

		const content =
			typeof message.content === "string"
				? message.content
				: JSON.stringify(message.content, null, 2);
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

	let registered = false;
	pi.on("session_start", async (_event, ctx) => {
		if (registered) return;
		const skillPath = findImpeccableSkill(ctx.cwd);
		if (!skillPath) return;
		registerImpeccableCommand(pi, skillPath);
		registered = true;
	});
}
