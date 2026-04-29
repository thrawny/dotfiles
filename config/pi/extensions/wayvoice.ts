import net from "node:net";
import os from "node:os";
import path from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";

const DEFAULT_SHORTCUT = "ctrl+space";
const MAX_PROMPT_CHARS = 600;
const MAX_USER_MESSAGE_CHARS = 180;
const MAX_ASSISTANT_MESSAGE_CHARS = 120;
const RECENT_USER_MESSAGES = 2;
const RECENT_ASSISTANT_MESSAGES = 2;
const TRIGGER_DEBOUNCE_MS = 750;

let inFlight = false;
let lastTriggerAt = 0;

interface WayvoiceRequest {
	cmd: "toggle";
	overrides?: {
		prompt: string;
		inject_mode: "stdout";
		use_default_keywords: false;
	};
}

interface WayvoiceResponse {
	status?: string;
	text?: string;
	error?: string;
}

function socketPath(): string {
	return process.env.PI_WAYVOICE_SOCKET || path.join(process.env.XDG_RUNTIME_DIR || os.tmpdir(), "wayvoice.sock");
}

function debug(message: string): void {
	if (process.env.PI_WAYVOICE_DEBUG === "1") console.error(`[pi-wayvoice] ${message}`);
}

let assumedRecording = false;

async function callWayvoice(request: WayvoiceRequest): Promise<WayvoiceResponse> {
	const starting = !assumedRecording;
	const line = starting ? `start-json ${JSON.stringify(request)}` : "stop-json";
	debug(`socket request: ${starting ? `start-json ${requestSummary(request)}` : line}`);
	const output = await sendSocketLine(line);
	debug(`socket response: ${JSON.stringify(output)}`);

	if (starting && output === "recording") assumedRecording = true;
	else if (!starting) assumedRecording = false;

	if (!output) return {};

	if (["recording", "transcribing", "busy", "idle", "cancelled"].includes(output)) return { status: output };
	if (output.startsWith("{") && output.endsWith("}")) return JSON.parse(output) as WayvoiceResponse;
	return { status: "done", text: output };
}

async function sendSocketLine(line: string): Promise<string> {
	return new Promise((resolve, reject) => {
		const socket = net.createConnection(socketPath());
		let output = "";
		const timer = setTimeout(() => {
			socket.destroy();
			reject(new Error("timed out"));
		}, 120_000);

		socket.setEncoding("utf8");
		socket.on("connect", () => socket.write(`${line}\n`));
		socket.on("data", (chunk: string) => {
			output += chunk;
		});
		socket.on("error", (error) => {
			clearTimeout(timer);
			reject(error);
		});
		socket.on("end", () => {
			clearTimeout(timer);
			resolve(output.trim());
		});
	});
}

function contentText(content: string | Array<{ type: string; text?: string; thinking?: string }>): string {
	if (typeof content === "string") return content;
	return content
		.filter((block) => block.type === "text" || block.type === "thinking")
		.map((block) => block.text ?? block.thinking ?? "")
		.join("\n");
}

function truncateText(text: string, maxChars: number): string {
	return text.length <= maxChars ? text : text.slice(0, maxChars).trimEnd();
}

function recentPromptContext(ctx: ExtensionContext): string {
	const selected: string[] = [];
	let users = 0;
	let assistants = 0;
	const branch = ctx.sessionManager.getBranch() as Array<{
		message?: { role: string; content: string | Array<{ type: string; text?: string; thinking?: string }> };
	}>;

	for (const entry of [...branch].reverse()) {
		const message = entry.message;
		if (!message) continue;
		if (message.role === "user" && users < RECENT_USER_MESSAGES) {
			selected.push(`User: ${truncateText(contentText(message.content), MAX_USER_MESSAGE_CHARS)}`);
			users++;
		} else if (message.role === "assistant" && assistants < RECENT_ASSISTANT_MESSAGES) {
			selected.push(`Assistant: ${truncateText(contentText(message.content), MAX_ASSISTANT_MESSAGE_CHARS)}`);
			assistants++;
		}
		if (users >= RECENT_USER_MESSAGES && assistants >= RECENT_ASSISTANT_MESSAGES) break;
	}

	return selected.reverse().join("\n\n");
}

function truncatePrompt(prompt: string): string {
	return truncateText(prompt, MAX_PROMPT_CHARS);
}

function requestSummary(request: WayvoiceRequest): string {
	const overrides = request.overrides;
	if (!overrides) return JSON.stringify({ cmd: request.cmd });
	return JSON.stringify({
		cmd: request.cmd,
		inject_mode: overrides.inject_mode,
		prompt_chars: overrides.prompt.length,
		use_default_keywords: overrides.use_default_keywords,
	});
}

function buildRequest(ctx: ExtensionContext): WayvoiceRequest {
	const context = recentPromptContext(ctx);
	const prompt = context || `User: ${path.basename(ctx.cwd)}`;

	return {
		cmd: "toggle",
		overrides: {
			inject_mode: "stdout",
			use_default_keywords: false,
			prompt: truncatePrompt(prompt),
		},
	};
}

async function toggleVoice(ctx: ExtensionContext): Promise<void> {
	const now = Date.now();
	if (inFlight || now - lastTriggerAt < TRIGGER_DEBOUNCE_MS) return;
	inFlight = true;
	lastTriggerAt = now;
	ctx.ui.setStatus("wayvoice", "voice…");
	try {
		const request = buildRequest(ctx);
		debug(`socket: ${socketPath()}`);
		debug(`built request: ${requestSummary(request)}`);
		const response = await callWayvoice(request);
		debug(`parsed response: ${JSON.stringify(response)}`);
		if (response.error) throw new Error(response.error);

		if (response.text?.trim()) {
			ctx.ui.pasteToEditor(response.text.trim());
			ctx.ui.notify("wayvoice transcript inserted", "info");
			return;
		}

		if (response.status) ctx.ui.notify(`wayvoice: ${response.status}`, "info");
	} finally {
		inFlight = false;
		ctx.ui.setStatus("wayvoice", undefined);
	}
}

export default function (pi: ExtensionAPI) {
	pi.registerShortcut((process.env.PI_WAYVOICE_SHORTCUT || DEFAULT_SHORTCUT) as never, {
		description: "Toggle wayvoice dictation into Pi",
		handler: async (ctx) => toggleVoice(ctx),
	});

	pi.registerCommand("voice", {
		description: "Toggle wayvoice dictation into the Pi editor",
		handler: async (_args, ctx) => toggleVoice(ctx),
	});
}
