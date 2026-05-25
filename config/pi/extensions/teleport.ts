import { execFileSync, spawn } from "node:child_process";
import path from "node:path";
import type {
	ExtensionAPI,
	ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { DynamicBorder } from "@earendil-works/pi-coding-agent";

type TeleportTheme = {
	fg(color: "accent" | "border" | "muted", text: string): string;
	bg(color: "customMessageBg", text: string): string;
};

import { Box, type Component, Container, Text } from "@earendil-works/pi-tui";

type TeleportState = {
	status: string;
	lines: string[];
};

type TeleportArgs = {
	target?: string;
	prompt: string;
};

function sanitize(value: string): string {
	return (
		value
			.toLowerCase()
			.replace(/[^a-z0-9_.-]+/g, "-")
			.replace(/^-+|-+$/g, "") || "workspace"
	);
}

function sessionFile(ctx: ExtensionContext): string {
	const file = ctx.sessionManager.getSessionFile();
	if (!file) throw new Error("Cannot teleport before Pi has a session file.");
	return file;
}

function inferredContainer(ctx: ExtensionContext): string {
	return sanitize(`teleport-${path.basename(ctx.cwd)}`);
}

function parseTeleportArgs(args: string): TeleportArgs {
	const tokens = args.match(/"[^"]*"|'[^']*'|\S+/g) ?? [];
	const targetIndex = tokens.findIndex(
		(token) => token === "--target" || token.startsWith("--target="),
	);
	if (targetIndex === -1) return { prompt: args };

	const token = tokens[targetIndex];
	const target = token.startsWith("--target=")
		? token.slice("--target=".length)
		: tokens[targetIndex + 1];
	if (!target) throw new Error("Missing value for --target.");

	const removeCount = token.startsWith("--target=") ? 1 : 2;
	tokens.splice(targetIndex, removeCount);
	return { target: unquote(target), prompt: tokens.join(" ") };
}

function unquote(value: string): string {
	const trimmed = value.trim();
	if (trimmed.length >= 2 && trimmed[0] === trimmed.at(-1)) {
		if (trimmed[0] === '"' || trimmed[0] === "'") return trimmed.slice(1, -1);
	}
	return trimmed;
}

function incusRemotes(): string[] {
	try {
		const output = execFileSync(
			"incus",
			["remote", "list", "--format", "csv"],
			{
				encoding: "utf8",
				stdio: ["ignore", "pipe", "ignore"],
				timeout: 2_000,
			},
		);
		return output
			.split("\n")
			.map((line) =>
				line
					.split(",")[0]
					?.trim()
					.replace(/\s+\(current\)$/, ""),
			)
			.filter((name): name is string => Boolean(name && name !== "images"))
			.filter((name, index, names) => names.indexOf(name) === index)
			.sort((a, b) =>
				a === "local" ? -1 : b === "local" ? 1 : a.localeCompare(b),
			);
	} catch {
		return ["local"];
	}
}

async function pickTarget(ctx: ExtensionContext): Promise<string | undefined> {
	const container = inferredContainer(ctx);
	const options = incusRemotes().map((remote) =>
		remote === "local" ? container : `${remote}:${container}`,
	);
	return ctx.ui.select("Teleport target", options, { timeout: 30_000 });
}

function widgetText(state: TeleportState): string {
	const lines = state.lines.slice(-12);
	return lines.join("\n");
}

function teleportWidget(state: TeleportState, theme: TeleportTheme): Component {
	const container = new Container();
	const border = (text: string) => theme.fg("border", text);
	const accent = (text: string) => theme.fg("accent", text);
	const muted = (text: string) => theme.fg("muted", text);
	const output = widgetText(state);
	const box = new Box(1, 1, (text) => theme.bg("customMessageBg", text));

	container.addChild(new DynamicBorder(border));
	box.addChild(
		new Text(
			`${accent("Teleport")} ${muted(state.status)}${output ? `\n\n${output}` : ""}`,
		),
	);
	container.addChild(box);
	container.addChild(new DynamicBorder(border));
	return container;
}

function appendOutput(state: TeleportState, chunk: Buffer | string): void {
	const text = String(chunk).replace(/\r/g, "\n");
	for (const line of text.split("\n")) {
		const trimmed = line.trim();
		if (trimmed) state.lines.push(trimmed);
	}
}

export default function (pi: ExtensionAPI) {
	pi.registerCommand("teleport", {
		description: "Prepare this Pi session to continue in an Incus container",
		getArgumentCompletions: () => null,
		handler: async (args, ctx) => {
			const parsed = parseTeleportArgs(args);
			const target = parsed.target ?? (await pickTarget(ctx));
			if (!target) return;

			const state: TeleportState = {
				status: "starting",
				lines: [],
			};
			const update = () => {
				ctx.ui.setWidget(
					"teleport",
					(_tui, theme) => teleportWidget(state, theme),
					{
						placement: "aboveEditor",
					},
				);
				ctx.ui.setStatus("teleport", state.status);
			};

			const child = spawn(
				"pi-teleport",
				[
					"--cwd",
					ctx.cwd,
					"--session",
					sessionFile(ctx),
					"--target",
					target,
					"--prompt",
					parsed.prompt,
				],
				{ stdio: ["ignore", "pipe", "pipe"] },
			);

			update();

			child.stdout.on("data", (chunk) => {
				state.status = "preparing";
				appendOutput(state, chunk);
				update();
			});
			child.stderr.on("data", (chunk) => {
				state.status = "preparing";
				appendOutput(state, chunk);
				update();
			});
			child.on("error", (error) => {
				state.status = "failed";
				state.lines.push(error.message);
				update();
				ctx.ui.notify(`teleport failed: ${error.message}`, "error");
			});
			child.on("close", (code) => {
				state.status = code === 0 ? "ready" : `failed (${code})`;
				update();
				ctx.ui.setStatus("teleport", undefined);
				if (code !== 0) {
					ctx.ui.notify(`teleport failed with exit code ${code}`, "error");
				}
			});
		},
	});
}
