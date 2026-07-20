import { execFile } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type {
	ExtensionAPI,
	ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

const RESET = "\x1b[0m";
const BOLD = "\x1b[1m";
const DIM = "\x1b[2m";

const BRANCH_GLYPH = "";
const BOLT = "";

// Monokai
const MK = {
	cyan: "#66d9ef",
	yellow: "#e6db74",
	orange: "#fd971f",
	red: "#f92672",
	pink: "#f92672",
	purple: "#ae81ff",
	gray: "#75715e",
	lightGray: "#a59f85",
	line: "#49483e",
};

function hexToRgb(hex: string): [number, number, number] {
	const clean = hex.replace("#", "");
	return [
		Number.parseInt(clean.slice(0, 2), 16),
		Number.parseInt(clean.slice(2, 4), 16),
		Number.parseInt(clean.slice(4, 6), 16),
	];
}

function fgTrue(hex: string): string {
	const [r, g, b] = hexToRgb(hex);
	return `\x1b[38;2;${r};${g};${b}m`;
}

const DIVIDER = ` ${fgTrue(MK.line)}│${RESET} `;

/** Shorten known model ids, e.g. "gpt-5.6-sol" → "Sol 5.6". */
function modelDisplayName(id: string): string {
	const match = id.match(/gpt-(\d+(?:\.\d+)?)-(sol|terra|luna)/);
	if (match) {
		const [, version, codename] = match;
		return `${codename[0].toUpperCase()}${codename.slice(1)} ${version}`;
	}
	return id;
}

function formatTokens(tokens: number): string {
	if (tokens >= 1_000_000) return `${(tokens / 1_000_000).toFixed(1)}M`;
	if (tokens >= 1_000) return `${(tokens / 1_000).toFixed(1)}k`;
	return `${tokens}`;
}

function truncate(text: string, maxLen = 20): string {
	if (text.length <= maxLen) return text;
	return `${text.slice(0, maxLen - 1)}…`;
}

function stripAnsi(text: string): string {
	return text.replace(
		new RegExp(`${String.fromCharCode(27)}\\[[0-9;]*m`, "g"),
		"",
	);
}

export function normalizeExtensionStatuses(
	statuses: Iterable<string>,
): string[] {
	let hasFast = false;
	const normalized: string[] = [];

	for (const status of statuses) {
		const parts = status
			.split("•")
			.map((part) => part.trim())
			.filter((part) => part.length > 0);

		const keptParts = parts.filter((part) => {
			if (stripAnsi(part).trim().toLowerCase() !== "fast") return true;
			hasFast = true;
			return false;
		});

		if (keptParts.length > 0) {
			normalized.push(keptParts.join(" • "));
		}
	}

	return hasFast ? ["fast", ...normalized] : normalized;
}

export function partitionExtensionStatuses(statuses: Iterable<string>): {
	backgroundStatus?: string;
	remaining: string[];
} {
	let backgroundStatus: string | undefined;
	const remaining: string[] = [];
	for (const status of normalizeExtensionStatuses(statuses)) {
		const plain = stripAnsi(status).trim();
		if (/^(?:\s*\d+|(?:[●]\s*)?bg\s+\d+)$/i.test(plain)) {
			backgroundStatus = plain;
		} else {
			remaining.push(status);
		}
	}
	return { backgroundStatus, remaining };
}

function envFlagSet(name: string): boolean {
	const value = process.env[name];
	if (!value) return false;
	const normalized = value.trim().toLowerCase();
	return normalized !== "0" && normalized !== "false";
}

export function isCodexFastEnabled(
	configPath = join(homedir(), ".pi", "agent", "pi-codex-conversion.json"),
): boolean {
	try {
		if (!existsSync(configPath)) return false;
		const config = JSON.parse(readFileSync(configPath, "utf8")) as unknown;
		if (!config || typeof config !== "object") return false;
		const openai = (config as { openai?: unknown }).openai;
		return Boolean(
			openai &&
			typeof openai === "object" &&
			(openai as { fast?: unknown }).fast === true,
		);
	} catch {
		return false;
	}
}

function getRuntimeBadge(): string | null {
	if (envFlagSet("SANDBOX")) {
		return "🫧";
	}

	const incusContainer = process.env.INCUS_CONTAINER?.trim();
	if (incusContainer) {
		return `🐳 ${fgTrue(MK.lightGray)}${incusContainer}${RESET}`;
	}

	return null;
}

const GIT_POLL_INTERVAL_MS = 2_000;

export interface GitInfo {
	branch: string | null;
	symbols: string;
}

/** Parse `git status --porcelain=v2 --branch` into branch + starship-style symbols. */
export function parseGitStatusV2(out: string): GitInfo {
	let branch: string | null = null;
	let ahead = 0;
	let behind = 0;
	let conflicted = false;
	let deleted = false;
	let renamed = false;
	let modified = false;
	let staged = false;
	let untracked = false;

	for (const line of out.split("\n")) {
		if (line.startsWith("# branch.head ")) {
			const head = line.slice("# branch.head ".length);
			branch = head === "(detached)" ? "detached" : head;
		} else if (line.startsWith("# branch.ab ")) {
			const parts = line.split(" ");
			ahead = Math.abs(Number.parseInt(parts[2], 10)) || 0;
			behind = Math.abs(Number.parseInt(parts[3], 10)) || 0;
		} else if (line.startsWith("1 ") || line.startsWith("2 ")) {
			const xy = line.split(" ", 3)[1];
			const x = xy[0];
			const y = xy[1];
			if (x === "R" || y === "R") renamed = true;
			if (x === "D" || y === "D") deleted = true;
			if (x !== "." && x !== "R" && x !== "D") staged = true;
			if (y !== "." && y !== "R" && y !== "D") modified = true;
		} else if (line.startsWith("u ")) {
			conflicted = true;
		} else if (line.startsWith("? ")) {
			untracked = true;
		}
	}

	let symbols = "";
	if (conflicted) symbols += "=";
	if (deleted) symbols += "✘";
	if (renamed) symbols += "»";
	if (modified) symbols += "!";
	if (staged) symbols += "+";
	if (untracked) symbols += "?";
	if (ahead && behind) symbols += "⇕";
	else if (ahead) symbols += "⇡";
	else if (behind) symbols += "⇣";

	return { branch, symbols };
}

/**
 * Async branch + dirty-state poll. Complements Pi's git metadata watcher
 * (which only covers branch changes) and keeps git out of the render path.
 */
export function resolveGitInfo(cwd: string): Promise<GitInfo | null> {
	return new Promise((resolve) => {
		execFile(
			"git",
			["--no-optional-locks", "status", "--porcelain=v2", "--branch"],
			{ cwd, encoding: "utf8", timeout: 1_500, maxBuffer: 10 * 1024 * 1024 },
			(error, stdout) => {
				resolve(error ? null : parseGitStatusV2(stdout));
			},
		);
	});
}

function install(
	ctx: ExtensionContext,
	getCurrentCtx: () => ExtensionContext | undefined,
	getThinkingLevel: () => string,
) {
	ctx.ui.setFooter((tui, _theme, footerData) => {
		let branch = footerData.getGitBranch();
		let statusSymbols = "";
		let disposed = false;
		let gitPollTimer: ReturnType<typeof setTimeout> | undefined;

		const runGitPoll = () => {
			if (disposed) return;
			const cwd = getCurrentCtx()?.cwd ?? process.cwd();
			const startedAt = Date.now();
			void resolveGitInfo(cwd)
				.then((info) => {
					// null means git was unavailable or cwd is not a repository. Keep
					// the last known values rather than flickering on failures.
					if (disposed || !info) return;
					const nextBranch = info.branch ?? branch;
					if (nextBranch !== branch || info.symbols !== statusSymbols) {
						branch = nextBranch;
						statusSymbols = info.symbols;
						tui.requestRender();
					}
				})
				.finally(() => {
					if (disposed) return;
					// Back off proportionally in repos where status is slow, so
					// polling never uses more than a sliver of a core: a 20ms
					// status polls every 2s, a 1s status only every 20s.
					const duration = Date.now() - startedAt;
					gitPollTimer = setTimeout(
						runGitPoll,
						Math.max(GIT_POLL_INTERVAL_MS, duration * 20),
					);
					gitPollTimer.unref();
				});
		};

		const unsub = footerData.onBranchChange(() => {
			branch = footerData.getGitBranch();
			tui.requestRender();
		});
		runGitPoll();

		const safe = <T>(fn: () => T, fallback: T): T => {
			try {
				return fn();
			} catch {
				return fallback;
			}
		};

		return {
			dispose() {
				disposed = true;
				if (gitPollTimer) clearTimeout(gitPollTimer);
				unsub();
			},
			invalidate() {},
			render(width: number): string[] {
				const activeCtx = getCurrentCtx();
				const sessionName = activeCtx
					? safe(
							() => activeCtx.sessionManager.getSessionName()?.trim(),
							undefined,
						)
					: undefined;
				const runtimeBadge = getRuntimeBadge();
				const { backgroundStatus, remaining: extensionStatuses } =
					partitionExtensionStatuses(
						footerData.getExtensionStatuses().values(),
					);
				if (isCodexFastEnabled() && !extensionStatuses.includes("fast")) {
					extensionStatuses.unshift("fast");
				}
				const usage = activeCtx
					? safe(() => activeCtx.getContextUsage(), undefined)
					: undefined;

				let tokens = usage?.tokens ?? 0;
				let percent = usage?.percent ?? 0;
				if (!Number.isFinite(percent)) percent = 0;
				if (!Number.isFinite(tokens)) tokens = 0;

				const ctxText = `${formatTokens(Math.max(0, Math.round(tokens)))} ${percent.toFixed(0)}%`;
				let ctxPart: string;
				if (percent >= 90) {
					ctxPart = `${BOLD}${fgTrue(MK.red)}${BOLT} ${ctxText}${RESET}`;
				} else if (percent >= 80) {
					ctxPart = `${fgTrue(MK.orange)}${ctxText}${RESET}`;
				} else {
					ctxPart = `${fgTrue(MK.gray)}${ctxText}${RESET}`;
				}

				const model = activeCtx
					? safe(() => activeCtx.model, undefined)
					: undefined;
				const thinking = activeCtx ? safe(getThinkingLevel, "off") : "off";
				const modelPart = model
					? `${BOLD}${fgTrue(MK.cyan)}${modelDisplayName(model.id)}${RESET}`
					: `${fgTrue(MK.gray)}no-model${RESET}`;

				const parts: string[] = [modelPart, ctxPart];

				const cwd = activeCtx?.cwd ?? process.cwd();
				const dirname = cwd.replace(/\/+$/, "").split("/").pop() || "/";
				parts.push(`${fgTrue(MK.purple)}${truncate(dirname)}${RESET}`);

				if (branch) {
					let gitPart = `${fgTrue(MK.yellow)}${BRANCH_GLYPH} ${truncate(branch, 32)}${RESET}`;
					if (statusSymbols) {
						gitPart += ` ${fgTrue(MK.orange)}${statusSymbols}${RESET}`;
					}
					parts.push(gitPart);
				}

				if (runtimeBadge) {
					parts.push(runtimeBadge);
				}

				if (backgroundStatus) {
					parts.push(`${fgTrue(MK.pink)}${backgroundStatus}${RESET}`);
				}

				const left = parts.join(DIVIDER);

				const rightPieces: string[] = [];
				if (model?.reasoning) {
					rightPieces.push(thinking === "off" ? "thinking off" : thinking);
				}
				// Strip embedded ANSI so extension statuses can't override the
				// uniform dim styling of the right side.
				rightPieces.push(...extensionStatuses.map(stripAnsi));
				const right =
					rightPieces.length > 0
						? `${DIM}${rightPieces.join(" • ")}${RESET}`
						: "";

				const leftWidth = visibleWidth(left);
				const rightWidth = visibleWidth(right);
				const centerText = sessionName ? ` ${sessionName} ` : "";
				const centerSlot = width - leftWidth - rightWidth;
				if (centerText && centerSlot > 1) {
					const renderedCenter = truncateToWidth(centerText, centerSlot, "");
					if (renderedCenter) {
						const centerWidth = visibleWidth(renderedCenter);
						const centerPad = centerSlot - centerWidth;
						if (centerPad >= 0) {
							const leftPad = " ".repeat(Math.floor(centerPad / 2));
							const rightPad = " ".repeat(
								centerPad - Math.floor(centerPad / 2),
							);
							return [
								`${left}${leftPad}${DIM}${renderedCenter}${RESET}${rightPad}${right}`,
							];
						}
					}
				}

				if (leftWidth + 2 + rightWidth <= width) {
					const pad = " ".repeat(Math.max(2, width - leftWidth - rightWidth));
					return [`${left}${pad}${right}`];
				}

				return [truncateToWidth(left, width, "")];
			},
		};
	});
}

export default function (pi: ExtensionAPI) {
	let currentCtx: ExtensionContext | undefined;

	const apply = (ctx: ExtensionContext) => {
		currentCtx = ctx;
		install(
			ctx,
			() => currentCtx,
			() => pi.getThinkingLevel(),
		);
	};

	pi.on("session_start", async (_event, ctx) => {
		apply(ctx);
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		currentCtx = undefined;
		ctx.ui.setFooter(undefined);
	});

	pi.registerCommand("statusline", {
		description: "Apply minimal monokai status footer",
		handler: async (_args, ctx) => {
			apply(ctx);
			ctx.ui.notify("Applied status line", "info");
		},
	});
}
