import { execFileSync } from "node:child_process";
import type {
	ExtensionAPI,
	ExtensionContext,
} from "@mariozechner/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@mariozechner/pi-tui";
import { SESSION_NAMED_EVENT } from "./session-namer";

const START_CAP = "\ue0b6";
const SEP = "\ue0b4";
const END_CAP = "\ue0b4";
const RESET = "\x1b[0m";

const COLORS = {
	white: "#ffffff",
	black: "#000000",
	darkRed: "#8b4a48",
	yellow: "#ffd602",
	blue: "#5f87d7",
	green: "#87af87",
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

function bgTrue(hex: string): string {
	const [r, g, b] = hexToRgb(hex);
	return `\x1b[48;2;${r};${g};${b}m`;
}

function reset(): string {
	return RESET;
}

function segment(
	text: string,
	fg: string,
	bg: string,
	nextBg?: string,
): string {
	let out = `${fgTrue(fg)}${bgTrue(bg)} ${text} `;
	if (nextBg) {
		out += `${fgTrue(bg)}${bgTrue(nextBg)}${SEP}`;
		return out;
	}
	out += `${reset()}${fgTrue(bg)}${END_CAP}${reset()}`;
	return out;
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

function envFlagSet(name: string): boolean {
	const value = process.env[name];
	if (!value) return false;
	const normalized = value.trim().toLowerCase();
	return normalized !== "0" && normalized !== "false";
}

function getRuntimeBadge(): { text: string; fg: string; bg: string } | null {
	if (envFlagSet("SANDBOX")) {
		return {
			text: "🫧",
			fg: COLORS.white,
			bg: COLORS.darkRed,
		};
	}

	const incusContainer = process.env.INCUS_CONTAINER?.trim();
	if (incusContainer) {
		return {
			text: `🐳 ${incusContainer}`,
			fg: COLORS.white,
			bg: COLORS.blue,
		};
	}

	return null;
}

function getGitChanges(): { added: number; removed: number } | null {
	try {
		const out = execFileSync("git", ["diff", "--shortstat"], {
			encoding: "utf8",
			timeout: 250,
			stdio: ["ignore", "pipe", "ignore"],
		}).trim();
		if (!out) return { added: 0, removed: 0 };

		const addMatch = out.match(/(\d+) insertion/);
		const delMatch = out.match(/(\d+) deletion/);
		return {
			added: addMatch ? Number.parseInt(addMatch[1], 10) : 0,
			removed: delMatch ? Number.parseInt(delMatch[1], 10) : 0,
		};
	} catch {
		return null;
	}
}

function install(
	ctx: ExtensionContext,
	getThinkingLevel: () => string,
	getSessionName: () => string | undefined,
) {
	ctx.ui.setFooter((tui, _theme, footerData) => {
		const unsub = footerData.onBranchChange(() => tui.requestRender());

		return {
			dispose: unsub,
			invalidate() {},
			render(width: number): string[] {
				const branch = footerData.getGitBranch();
				const sessionName = getSessionName()?.trim();
				const changes = getGitChanges();
				const runtimeBadge = getRuntimeBadge();
				const usage = ctx.getContextUsage();

				let tokens = usage?.tokens ?? 0;
				let percent = usage?.percent ?? 0;
				if (!Number.isFinite(percent)) percent = 0;
				if (!Number.isFinite(tokens)) tokens = 0;

				let ctxFg = COLORS.black;
				let ctxBg = COLORS.yellow;
				let warn = "";
				if (percent >= 90) {
					ctxFg = COLORS.white;
					ctxBg = COLORS.darkRed;
					warn = "\uf0e7 ";
				} else if (percent >= 67) {
					warn = "\uf071 ";
				}

				const segmentSpecs: Array<{ text: string; fg: string; bg: string }> = [
					{
						text: `${warn}${formatTokens(Math.max(0, Math.round(tokens)))} ${percent.toFixed(1)}%`,
						fg: ctxFg,
						bg: ctxBg,
					},
				];

				if (branch) {
					segmentSpecs.push({
						text: `\ue0a0 ${truncate(branch)}`,
						fg: COLORS.white,
						bg: COLORS.blue,
					});
				}

				if (changes) {
					segmentSpecs.push({
						text: `+${changes.added}, -${changes.removed}`,
						fg: COLORS.black,
						bg: COLORS.green,
					});
				}

				if (runtimeBadge) {
					segmentSpecs.push(runtimeBadge);
				}

				const segments = segmentSpecs.map((part, index) =>
					segment(part.text, part.fg, part.bg, segmentSpecs[index + 1]?.bg),
				);

				const left = `${fgTrue(segmentSpecs[0].bg)}${START_CAP}${reset()}${segments.join("")}`;

				const thinking = getThinkingLevel();
				let rightText = ctx.model?.id || "no-model";
				if (ctx.model?.reasoning) {
					rightText =
						thinking === "off"
							? `${rightText} • thinking off`
							: `${rightText} • ${thinking}`;
				}
				const right = `\x1b[2m${rightText}\x1b[0m`;

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
							const rightPad = " ".repeat(centerPad - Math.floor(centerPad / 2));
							return [`${left}${leftPad}${renderedCenter}${rightPad}${right}`];
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
		install(ctx, () => pi.getThinkingLevel(), () => pi.getSessionName());
	};

	pi.on("session_start", async (_event, ctx) => {
		apply(ctx);
	});

	pi.on("session_switch", async (_event, ctx) => {
		apply(ctx);
	});

	pi.on("session_shutdown", async () => {
		currentCtx = undefined;
	});

	pi.events.on(SESSION_NAMED_EVENT, () => {
		if (currentCtx) {
			apply(currentCtx);
		}
	});

	pi.registerCommand("statusline", {
		description: "Apply Claude-like powerline status footer",
		handler: async (_args, ctx) => {
			apply(ctx);
			ctx.ui.notify("Applied status line", "info");
		},
	});
}
