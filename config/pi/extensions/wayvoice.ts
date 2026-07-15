import { randomUUID } from "node:crypto";
import {
	appendFileSync,
	mkdirSync,
	readFileSync,
	writeFileSync,
} from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import type { AssistantMessage } from "@earendil-works/pi-ai";
import { completeSimple } from "@earendil-works/pi-ai/compat";
import type {
	ExtensionAPI,
	ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { Type } from "@sinclair/typebox";

const DEFAULT_SHORTCUT = "ctrl+space";
const KEYWORD_CONTEXT_MESSAGES = 20;
const MAX_DYNAMIC_KEYWORDS = 20;
const MAX_DYNAMIC_FRAGMENTS = 12;
const TRIGGER_DEBOUNCE_MS = 750;

let inFlight = false;
let lastTriggerAt = 0;
let dynamicKeywords: string[] = [];
let dynamicFragments: string[] = [];
let pendingTranscript: PendingTranscript | undefined;

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

interface PendingTranscript {
	id: string;
	transcript: string;
	request: WayvoiceRequest;
	cwd: string;
	sessionFile?: string;
	insertedAt: string;
}

interface HintState {
	keywords: string[];
	fragments: string[];
}

function runtimeDir(): string {
	return process.env.XDG_RUNTIME_DIR || os.tmpdir();
}

function socketPaths(): string[] {
	if (process.env.PI_WAYVOICE_SOCKET) return [process.env.PI_WAYVOICE_SOCKET];
	return [
		path.join(runtimeDir(), "wayvoice", "wayvoice.sock"),
		path.join(runtimeDir(), "wayvoice.sock"),
	];
}

function socketPath(): string {
	return socketPaths()[0];
}

function isDebug(): boolean {
	return process.env.PI_WAYVOICE_DEBUG === "1";
}

function debug(message: string): void {
	if (isDebug()) console.error(`[pi-wayvoice] ${message}`);
}

function cachePath(name: string): string {
	return path.join(
		process.env.XDG_CACHE_HOME || path.join(os.homedir(), ".cache"),
		"pi",
		name,
	);
}

function logPath(): string {
	return cachePath("wayvoice.log");
}

function transcriptLogPath(): string {
	return cachePath("wayvoice-transcripts.jsonl");
}

function hintStatePath(): string {
	return cachePath("wayvoice-hints.json");
}

function log(message: string): void {
	const line = `[${new Date().toISOString()}] ${message}\n`;
	if (isDebug()) console.error(`[pi-wayvoice] ${message}`);
	mkdirSync(path.dirname(logPath()), { recursive: true });
	appendFileSync(logPath(), line);
}

function logTranscriptEvent(event: Record<string, unknown>): void {
	mkdirSync(path.dirname(transcriptLogPath()), { recursive: true });
	appendFileSync(
		transcriptLogPath(),
		`${JSON.stringify({ ts: new Date().toISOString(), ...event })}\n`,
	);
}

function logError(message: string): void {
	log(`ERROR ${message}`);
}

function loadHintState(): void {
	try {
		const parsed = JSON.parse(
			readFileSync(hintStatePath(), "utf8"),
		) as Partial<HintState>;
		dynamicKeywords = cleanKeywords(parsed.keywords ?? []).slice(
			0,
			MAX_DYNAMIC_KEYWORDS,
		);
		dynamicFragments = cleanFragments(parsed.fragments ?? []).slice(
			0,
			MAX_DYNAMIC_FRAGMENTS,
		);
		log(
			`hints loaded: ${JSON.stringify({ keywords: dynamicKeywords, fragments: dynamicFragments })}`,
		);
	} catch (error) {
		if ((error as { code?: unknown }).code !== "ENOENT") {
			logError(`failed to load hint state: ${errorMessage(error)}`);
		}
	}
}

function saveHintState(): void {
	mkdirSync(path.dirname(hintStatePath()), { recursive: true });
	writeFileSync(
		hintStatePath(),
		`${JSON.stringify({ keywords: dynamicKeywords, fragments: dynamicFragments }, null, "\t")}\n`,
	);
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

function isEnoent(error: unknown): boolean {
	return (
		typeof error === "object" &&
		error !== null &&
		"code" in error &&
		(error as { code?: unknown }).code === "ENOENT"
	);
}

function errorMessage(error: unknown): string {
	return error instanceof Error ? error.message : String(error);
}

async function sendSocketLine(line: string): Promise<string> {
	const paths = socketPaths();
	const failures: string[] = [];
	for (const [index, currentSocketPath] of paths.entries()) {
		try {
			return await sendSocketLineToPath(currentSocketPath, line);
		} catch (error) {
			failures.push(`${currentSocketPath}: ${errorMessage(error)}`);
			if (isEnoent(error) && index < paths.length - 1) continue;
			if (failures.length > 1)
				throw new Error(
					`could not connect to wayvoice (${failures.join("; ")})`,
				);
			throw error;
		}
	}
	throw new Error(`could not connect to wayvoice (${failures.join("; ")})`);
}

async function sendSocketLineToPath(
	currentSocketPath: string,
	line: string,
): Promise<string> {
	return new Promise((resolve, reject) => {
		const socket = net.createConnection(currentSocketPath);
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

function promptHints(): string[] {
	return [...dynamicKeywords, ...dynamicFragments];
}

function sessionFile(ctx: ExtensionContext): string | undefined {
	return ctx.sessionManager.getSessionFile() ?? undefined;
}

function normalizedWords(text: string): string[] {
	return text
		.toLowerCase()
		.replace(/[^\p{L}\p{N}]+/gu, " ")
		.trim()
		.split(/\s+/)
		.filter(Boolean);
}

function editDistance<T>(left: T[], right: T[]): number {
	const previous = Array.from(
		{ length: right.length + 1 },
		(_, index) => index,
	);
	const current = Array.from({ length: right.length + 1 }, () => 0);
	for (let i = 0; i < left.length; i++) {
		current[0] = i + 1;
		for (let j = 0; j < right.length; j++) {
			const substitution = previous[j] + (left[i] === right[j] ? 0 : 1);
			const insertion = current[j] + 1;
			const deletion = previous[j + 1] + 1;
			current[j + 1] = Math.min(substitution, insertion, deletion);
		}
		for (let j = 0; j < previous.length; j++) previous[j] = current[j];
	}
	return previous[right.length];
}

function correctionStats(transcript: string, finalText: string) {
	const transcriptWords = normalizedWords(transcript);
	const finalWords = normalizedWords(finalText);
	const wordDistance = editDistance(transcriptWords, finalWords);
	const transcriptChars = [...transcript.toLowerCase().replace(/\s+/g, "")];
	const finalChars = [...finalText.toLowerCase().replace(/\s+/g, "")];
	const charDistance = editDistance(transcriptChars, finalChars);
	return {
		edited: transcript.trim() !== finalText.trim(),
		word_distance: wordDistance,
		word_error_rate: wordDistance / Math.max(transcriptWords.length, 1),
		char_distance: charDistance,
		char_error_rate: charDistance / Math.max(transcriptChars.length, 1),
	};
}

function buildRequest(_ctx: ExtensionContext): WayvoiceRequest {
	return {
		cmd: "toggle",
		overrides: {
			inject_mode: "stdout",
			use_default_keywords: false,
			extra_keywords: promptHints(),
			prompt: "",
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
		if (message?.role !== "user") continue;
		lines.push(`user: ${truncateText(contentText(message.content), 400)}`);
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

interface PromptHints {
	keywords: string[];
	fragments: string[];
}

function parsePromptHints(text: string): PromptHints {
	const json = text.match(/\{[\s\S]*\}/)?.[0];
	if (!json)
		throw new Error(`keyword response was not JSON: ${JSON.stringify(text)}`);
	const parsed = JSON.parse(json) as { keywords: unknown; fragments?: unknown };
	if (!Array.isArray(parsed.keywords))
		throw new Error(`keyword response did not include keywords array: ${json}`);

	return {
		keywords: cleanKeywords(parsed.keywords).slice(0, MAX_DYNAMIC_KEYWORDS),
		fragments: cleanFragments(parsed.fragments ?? []).slice(
			0,
			MAX_DYNAMIC_FRAGMENTS,
		),
	};
}

function cleanKeywords(values: unknown): string[] {
	if (!Array.isArray(values)) return [];
	return values
		.filter((keyword): keyword is string => typeof keyword === "string")
		.map((keyword) => keyword.trim())
		.filter(isCleanKeyword)
		.filter((keyword) => !isBlockedHint(keyword));
}

function cleanFragments(values: unknown): string[] {
	if (!Array.isArray(values)) return [];
	return values
		.filter((fragment): fragment is string => typeof fragment === "string")
		.map((fragment) => fragment.trim())
		.filter(isCleanFragment)
		.filter((fragment) => !isBlockedHint(fragment));
}

function isCleanKeyword(keyword: string): boolean {
	return (
		keyword.length >= 2 &&
		keyword.length <= 60 &&
		!hasUnsafePromptChars(keyword) &&
		!keyword.includes("/") &&
		!keyword.match(/\.[a-z0-9]{1,6}$/i)
	);
}

function isCleanFragment(fragment: string): boolean {
	const words = fragment.split(/\s+/).filter(Boolean);
	return (
		fragment.length >= 6 &&
		fragment.length <= 80 &&
		words.length >= 2 &&
		words.length <= 6 &&
		!hasUnsafePromptChars(fragment) &&
		!fragment.includes("/") &&
		!fragment.match(/\.[a-z0-9]{1,6}$/i)
	);
}

function hasUnsafePromptChars(value: string): boolean {
	return /[\n\r{}[\]`"<>]/.test(value);
}

function isBlockedHint(value: string): boolean {
	return [
		"debug flag",
		"typecheck",
		"reload",
		"temperature",
		"openai-codex-responses",
		"wayvoice_debug_inject",
	].includes(value.toLowerCase());
}

function mergeHints(
	previous: string[],
	extracted: string[],
	limit: number,
): string[] {
	const merged = [...previous];
	for (const hint of extracted) {
		if (
			!merged.some((existing) => existing.toLowerCase() === hint.toLowerCase())
		)
			merged.push(hint);
	}
	return merged.slice(0, limit);
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
				"Extract prompt hints that help future Whisper-style speech-to-text dictation.",
				'Return JSON only: {"keywords":["term"],"fragments":["short phrase"]}.',
				"keywords: project/tool/product names, acronyms, commands, and uncommon technical terms likely to be spoken aloud.",
				"fragments: short 2-6 word domain fragments likely to be spoken, such as 'transcript logs' or 'eval suite'.",
				"Use the latest transcript and recent user context; do not copy assistant prose, JSON, markdown, tool output, file paths, ids, hashes, or generic prose.",
			].join("\n"),
			messages: [
				{
					role: "user",
					content: `Latest transcript:\n${transcript}\n\nRecent user context:\n${keywordContext(ctx)}\n\nCurrent keywords:\n${dynamicKeywords.join(", ")}\n\nCurrent fragments:\n${dynamicFragments.join(". ")}`,
					timestamp: Date.now(),
				},
			],
		},
		{
			apiKey: auth.apiKey,
			headers: auth.headers,
			reasoning: "minimal",
			maxTokens: 260,
		},
	);
	const hints = parsePromptHints(assistantText(keywordResponse));
	const nextKeywords = mergeHints(
		dynamicKeywords,
		hints.keywords,
		MAX_DYNAMIC_KEYWORDS,
	);
	const nextFragments = mergeHints(
		dynamicFragments,
		hints.fragments,
		MAX_DYNAMIC_FRAGMENTS,
	);
	if (
		JSON.stringify(nextKeywords) === JSON.stringify(dynamicKeywords) &&
		JSON.stringify(nextFragments) === JSON.stringify(dynamicFragments)
	) {
		const message = `wayvoice hints unchanged: ${promptHints().join(", ") || "none"}`;
		showDebugWidget(ctx, message);
		addDebugMessage(pi, message);
		return;
	}
	dynamicKeywords = nextKeywords;
	dynamicFragments = nextFragments;
	saveHintState();
	debug(`dynamic keywords: ${JSON.stringify(dynamicKeywords)}`);
	debug(`dynamic fragments: ${JSON.stringify(dynamicFragments)}`);
	log(
		`hints updated: ${JSON.stringify({ keywords: dynamicKeywords, fragments: dynamicFragments })}`,
	);
	const message = `wayvoice hints: ${promptHints().join(", ") || "none"}`;
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
			const insertedAt = new Date().toISOString();
			pendingTranscript = {
				id: randomUUID(),
				transcript,
				request,
				cwd: ctx.cwd,
				sessionFile: sessionFile(ctx),
				insertedAt,
			};
			logTranscriptEvent({
				event: "voice_inserted",
				id: pendingTranscript.id,
				cwd: pendingTranscript.cwd,
				session_file: pendingTranscript.sessionFile,
				inserted_at: insertedAt,
				transcript,
				request: request.overrides,
				keywords: dynamicKeywords,
				fragments: dynamicFragments,
			});
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
	loadHintState();

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

	pi.on("input", async (event, ctx) => {
		if (!pendingTranscript || event.source === "extension") {
			return { action: "continue" };
		}
		const pending = pendingTranscript;
		pendingTranscript = undefined;
		const stats = correctionStats(pending.transcript, event.text);
		logTranscriptEvent({
			event: "voice_submitted",
			id: pending.id,
			cwd: ctx.cwd,
			session_file: sessionFile(ctx),
			inserted_at: pending.insertedAt,
			submitted_at: new Date().toISOString(),
			transcript: pending.transcript,
			final_text: event.text,
			...stats,
		});
		return { action: "continue" };
	});

	pi.registerCommand("voice-keywords", {
		description: "Show current wayvoice dynamic prompt hints",
		handler: async (_args, ctx) => {
			ctx.ui.setWidget(
				"wayvoice-keywords",
				[
					`wayvoice keywords: ${dynamicKeywords.join(", ") || "none"}`,
					`wayvoice fragments: ${dynamicFragments.join(", ") || "none"}`,
				],
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
				"Debug wayvoice prompt hint extraction by pretending a transcript was inserted into the Pi editor.",
			parameters: Type.Object({
				transcript: Type.String({
					description:
						"Mock transcript text to insert and feed to prompt hint extraction",
				}),
			}),
			async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
				ctx.ui.pasteToEditor(params.transcript);
				showDebugWidget(ctx, "wayvoice debug: updating prompt hints…");
				await updateDynamicKeywords(pi, ctx, params.transcript);
				return {
					content: [
						{
							type: "text",
							text: `Inserted mock transcript and updated hints: ${promptHints().join(", ") || "none"}`,
						},
					],
					details: { keywords: dynamicKeywords, fragments: dynamicFragments },
				};
			},
		});
	}
}
