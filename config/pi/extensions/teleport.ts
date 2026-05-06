import { spawn } from "node:child_process";
import type {
	ExtensionAPI,
	ExtensionContext,
} from "@mariozechner/pi-coding-agent";
import { DynamicBorder } from "@mariozechner/pi-coding-agent";

type TeleportTheme = {
	fg(color: "accent" | "border" | "muted", text: string): string;
	bg(color: "customMessageBg", text: string): string;
};

import { Box, type Component, Container, Text } from "@mariozechner/pi-tui";

type TeleportState = {
	status: string;
	lines: string[];
};

function sessionFile(ctx: ExtensionContext): string {
	const file = ctx.sessionManager.getSessionFile();
	if (!file) throw new Error("Cannot teleport before Pi has a session file.");
	return file;
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
				["--cwd", ctx.cwd, "--session", sessionFile(ctx), "--prompt", args],
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
