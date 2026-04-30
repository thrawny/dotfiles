import { appendFileSync, mkdirSync } from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import type { AssistantMessage } from "@mariozechner/pi-ai";
import { completeSimple } from "@mariozechner/pi-ai";
import type {
	ExtensionAPI,
	ExtensionContext,
} from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";

const DEFAULT_SHORTCUT = "ctrl+space";
const MAX_PROMPT_CHARS = 600;
const MAX_USER_MESSAGE_CHARS = 180;
const MAX_ASSISTANT_MESSAGE_CHARS = 120;
const RECENT_USER_MESSAGES = 2;
const RECENT_ASSISTANT_MESSAGES = 2;
const KEYWORD_CONTEXT_MESSAGES = 20;
const MAX_DYNAMIC_KEYWORDS = 20;
const TRIGGER_DEBOUNCE_MS = 750;

let inFlight = false;
let lastTriggerAt = 0;
let dynamicKeywords: string[] = [];

interface WayvoiceRequest {
	cmd: "toggle";
	overrides?: {
		prompt: string;
		extra_keywords: string[];
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
	return (
		process.env.PI_WAYVOICE_SOCKET ||
		path.join(process.env.XDG_RUNTIME_DIR || os.tmpdir(), "wayvoice.sock")
	);
}

function isDebug(): boolean {
	return process.env.PI_WAYVOICE_DEBUG === "1";
}

function debug(message: string): void {
	if (isDebug()) console.error(`[pi-wayvoice] ${message}`);
}

function logPath(): string {
	return path.join(
		process.env.XDG_CACHE_HOME || path.join(os.homedir(), ".cache"),
		"pi",
		"wayvoice.log",
	);
}

function log(message: string): void {
	const line = `[${new Date().toISOString()}] ${message}\n`;
	if (isDebug()) console.error(`[pi-wayvoice] ${message}`);
	mkdirSync(path.dirname(logPath()), { recursive: true });
	appendFileSync(logPath(), line);
}

function logError(message: string): void {
	log(`ERROR ${message}`);
}

let assumedRecording = false;

async function callWayvoice(
	request: WayvoiceRequest,
): Promise<WayvoiceResponse> {
	const starting = !assumedRecording;
	const line = starting ? `start-json ${JSON.stringify(request)}` : "stop-json";
	debug(
		`socket request: ${starting ? `start-json ${requestSummary(request)}` : line}`,
	);
	const output = await sendSocketLine(line);
	debug(`socket response: ${JSON.stringify(output)}`);

	if (starting && output === "recording") assumedRecording = true;
	else if (!starting) assumedRecording = false;

	if (!output) return {};

	if (
		["recording", "transcribing", "busy", "idle", "cancelled"].includes(output)
	)
		return { status: output };
	if (output.startsWith("{") && output.endsWith("}"))
		return JSON.parse(output) as WayvoiceResponse;
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

function contentText(
	content: string | Array<{ type: string; text?: string; thinking?: string }>,
): string {
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
		message?: {
			role: string;
			content:
				| string
				| Array<{ type: string; text?: string; thinking?: string }>;
		};
	}>;

	for (const entry of [...branch].reverse()) {
		const message = entry.message;
		if (!message) continue;
		if (message.role === "user" && users < RECENT_USER_MESSAGES) {
			selected.push(
				`User: ${truncateText(contentText(message.content), MAX_USER_MESSAGE_CHARS)}`,
			);
			users++;
		} else if (
			message.role === "assistant" &&
			assistants < RECENT_ASSISTANT_MESSAGES
		) {
			selected.push(
				`Assistant: ${truncateText(contentText(message.content), MAX_ASSISTANT_MESSAGE_CHARS)}`,
			);
			assistants++;
		}
		if (
			users >= RECENT_USER_MESSAGES &&
			assistants >= RECENT_ASSISTANT_MESSAGES
		)
			break;
	}

	return selected.reverse().join("\n\n");
}

function truncatePrompt(prompt: string): string {
	return truncateText(prompt, MAX_PROMPT_CHARS);
}

function showDebugWidget(ctx: ExtensionContext, message: string): void {
	if (!isDebug()) return;
	ctx.ui.setWidget("wayvoice-keywords", [message], {
		placement: "belowEditor",
	});
	setTimeout(() => ctx.ui.setWidget("wayvoice-keywords", undefined), 8_000);
}

function requestSummary(request: WayvoiceRequest): string {
	const overrides = request.overrides;
	if (!overrides) return JSON.stringify({ cmd: request.cmd });
	return JSON.stringify({
		cmd: request.cmd,
		inject_mode: overrides.inject_mode,
		prompt_chars: overrides.prompt.length,
		keyword_count: overrides.extra_keywords.length,
		keywords: overrides.extra_keywords,
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
			extra_keywords: dynamicKeywords,
			prompt: truncatePrompt(prompt),
		},
	};
}

function keywordContext(ctx: ExtensionContext): string {
	const lines: string[] = [];
	const branch = ctx.sessionManager.getBranch() as Array<{
		message?: {
			role: string;
			content:
				| string
				| Array<{ type: string; text?: string; thinking?: string }>;
		};
	}>;

	for (const entry of [...branch].reverse()) {
		const message = entry.message;
		if (!message || (message.role !== "user" && message.role !== "assistant"))
			continue;
		lines.push(
			`${message.role}: ${truncateText(contentText(message.content), 400)}`,
		);
		if (lines.length >= KEYWORD_CONTEXT_MESSAGES) break;
	}

	return lines.reverse().join("\n\n");
}

function assistantText(message: AssistantMessage): string {
	const text = message.content
		.map((block) => {
			if (block.type === "text") return block.text;
			if (block.type === "thinking") return block.thinking;
			return JSON.stringify(block);
		})
		.join("\n")
		.trim();
	if (!text)
		throw new Error(`empty keyword response: ${JSON.stringify(message)}`);
	return text;
}

function parseKeywords(text: string): string[] {
	const json = text.match(/\{[\s\S]*\}/)?.[0];
	if (!json)
		throw new Error(`keyword response was not JSON: ${JSON.stringify(text)}`);
	const parsed = JSON.parse(json) as { keywords: unknown };
	if (!Array.isArray(parsed.keywords))
		throw new Error(`keyword response did not include keywords array: ${json}`);
	return parsed.keywords
		.filter((keyword): keyword is string => typeof keyword === "string")
		.map((keyword) => keyword.trim())
		.filter(
			(keyword) =>
				keyword.length >= 2 &&
				keyword.length <= 60 &&
				!keyword.includes("/") &&
				!keyword.match(/\.[a-z0-9]{1,6}$/i),
		)
		.filter(
			(keyword) =>
				![
					"debug flag",
					"typecheck",
					"reload",
					"temperature",
					"openai-codex-responses",
					"wayvoice_debug_inject",
				].includes(keyword.toLowerCase()),
		)
		.slice(0, MAX_DYNAMIC_KEYWORDS);
}

function mergeKeywords(previous: string[], extracted: string[]): string[] {
	const merged = [...previous];
	for (const keyword of extracted) {
		if (
			!merged.some(
				(existing) => existing.toLowerCase() === keyword.toLowerCase(),
			)
		)
			merged.push(keyword);
	}
	return merged.slice(0, MAX_DYNAMIC_KEYWORDS);
}

function addDebugMessage(pi: ExtensionAPI, content: string): void {
	if (!isDebug()) return;
	pi.sendMessage(
		{
			customType: "wayvoice-debug",
			content,
			display: true,
			details: { ts: new Date().toISOString() },
		},
		{ triggerTurn: false },
	);
}

async function updateDynamicKeywords(
	pi: ExtensionAPI,
	ctx: ExtensionContext,
	transcript: string,
): Promise<void> {
	if (!ctx.model) throw new Error("no current model");
	const auth = await ctx.modelRegistry.getApiKeyAndHeaders(ctx.model);
	if (!auth.ok) throw new Error(auth.error);
	const keywordResponse = await completeSimple(
		ctx.model,
		{
			systemPrompt: [
				"Extract spoken technical vocabulary that would help future speech-to-text dictation.",
				'Return JSON only: {"keywords":["term"]}.',
				"Include project/tool/product names, acronyms, commands, and uncommon technical terms likely to be spoken aloud.",
				"Exclude filenames, file paths, ids, hashes, generic prose, and normal English words.",
			].join("\n"),
			messages: [
				{
					role: "user",
					content: `Latest transcript:\n${transcript}\n\nRecent context:\n${keywordContext(ctx)}\n\nCurrent keywords:\n${dynamicKeywords.join(", ")}`,
					timestamp: Date.now(),
				},
			],
		},
		{
			apiKey: auth.apiKey,
			headers: auth.headers,
			reasoning: "minimal",
			maxTokens: 200,
		},
	);
	const nextKeywords = mergeKeywords(
		dynamicKeywords,
		parseKeywords(assistantText(keywordResponse)),
	);
	if (JSON.stringify(nextKeywords) === JSON.stringify(dynamicKeywords)) {
		const message = `wayvoice keywords unchanged: ${dynamicKeywords.join(", ") || "none"}`;
		showDebugWidget(ctx, message);
		addDebugMessage(pi, message);
		return;
	}
	dynamicKeywords = nextKeywords;
	debug(`dynamic keywords: ${JSON.stringify(dynamicKeywords)}`);
	if (isDebug()) log(`keywords updated: ${JSON.stringify(dynamicKeywords)}`);
	const keywordList = dynamicKeywords.join(", ");
	const message = `wayvoice keywords: ${keywordList || "none"}`;
	showDebugWidget(ctx, message);
	addDebugMessage(pi, message);
}

async function toggleVoice(
	pi: ExtensionAPI,
	ctx: ExtensionContext,
): Promise<void> {
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
		if (response.error) {
			ctx.ui.notify(`wayvoice ${response.error.toLowerCase()}`, "info");
			return;
		}

		if (response.text?.trim()) {
			const transcript = response.text.trim();
			ctx.ui.pasteToEditor(transcript);
			showDebugWidget(ctx, "wayvoice: updating keywords…");
			void updateDynamicKeywords(pi, ctx, transcript).catch((error) => {
				logError(
					`keyword update failed: ${error instanceof Error ? error.stack || error.message : String(error)}`,
				);
				const message = `wayvoice keyword update failed: ${error}`;
				showDebugWidget(ctx, message);
				addDebugMessage(pi, message);
			});
			ctx.ui.notify("wayvoice transcript inserted", "info");
			return;
		}

		if (response.status && response.status !== "recording")
			ctx.ui.notify(`wayvoice: ${response.status}`, "info");
	} finally {
		inFlight = false;
		ctx.ui.setStatus("wayvoice", undefined);
	}
}

export default function (pi: ExtensionAPI) {
	pi.registerShortcut(
		(process.env.PI_WAYVOICE_SHORTCUT || DEFAULT_SHORTCUT) as never,
		{
			description: "Toggle wayvoice dictation into Pi",
			handler: async (ctx) => toggleVoice(pi, ctx),
		},
	);

	pi.registerCommand("voice", {
		description: "Toggle wayvoice dictation into the Pi editor",
		handler: async (_args, ctx) => toggleVoice(pi, ctx),
	});

	pi.registerCommand("voice-keywords", {
		description: "Show current wayvoice dynamic keywords",
		handler: async (_args, ctx) => {
			ctx.ui.setWidget(
				"wayvoice-keywords",
				[`wayvoice keywords: ${dynamicKeywords.join(", ") || "none"}`],
				{ placement: "belowEditor" },
			);
			setTimeout(() => ctx.ui.setWidget("wayvoice-keywords", undefined), 8_000);
		},
	});

	if (isDebug()) {
		pi.registerCommand("voice-log", {
			description: "Show wayvoice extension log path",
			handler: async (_args, ctx) => {
				ctx.ui.setWidget("wayvoice-keywords", [`wayvoice log: ${logPath()}`], {
					placement: "belowEditor",
				});
				setTimeout(
					() => ctx.ui.setWidget("wayvoice-keywords", undefined),
					8_000,
				);
			},
		});

		pi.registerTool({
			name: "wayvoice_debug_inject",
			label: "Wayvoice Debug Inject",
			description:
				"Debug wayvoice keyword extraction by pretending a transcript was inserted into the Pi editor.",
			parameters: Type.Object({
				transcript: Type.String({
					description:
						"Mock transcript text to insert and feed to keyword extraction",
				}),
			}),
			async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
				ctx.ui.pasteToEditor(params.transcript);
				showDebugWidget(ctx, "wayvoice debug: updating keywords…");
				await updateDynamicKeywords(pi, ctx, params.transcript);
				return {
					content: [
						{
							type: "text",
							text: `Inserted mock transcript and updated keywords: ${dynamicKeywords.join(", ") || "none"}`,
						},
					],
					details: { keywords: dynamicKeywords },
				};
			},
		});
	}
}
