import { execFileSync } from "node:child_process";
import type {
	ExtensionAPI,
	ExtensionContext,
} from "@mariozechner/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@mariozechner/pi-tui";

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

function install(ctx: ExtensionContext, getThinkingLevel: () => string) {
	ctx.ui.setFooter((tui, _theme, footerData) => {
		const unsub = footerData.onBranchChange(() => tui.requestRender());

		return {
			dispose: unsub,
			invalidate() {},
			render(width: number): string[] {
				const branch = footerData.getGitBranch();
				const changes = getGitChanges();
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

				const segments: string[] = [];
				const hasBranch = branch !== null;
				const hasChanges = changes !== null;

				segments.push(
					segment(
						`${warn}${formatTokens(Math.max(0, Math.round(tokens)))} ${percent.toFixed(1)}%`,
						ctxFg,
						ctxBg,
						hasBranch ? COLORS.blue : hasChanges ? COLORS.green : undefined,
					),
				);

				if (branch) {
					segments.push(
						segment(
							`\ue0a0 ${truncate(branch)}`,
							COLORS.white,
							COLORS.blue,
							hasChanges ? COLORS.green : undefined,
						),
					);
				}

				if (changes) {
					segments.push(
						segment(
							`+${changes.added}, -${changes.removed}`,
							COLORS.black,
							COLORS.green,
						),
					);
				}

				const left = `${fgTrue(ctxBg)}${START_CAP}${reset()}${segments.join("")}`;

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
	pi.on("session_start", async (_event, ctx) => {
		install(ctx, () => pi.getThinkingLevel());
	});

	pi.registerCommand("statusline", {
		description: "Apply Claude-like powerline status footer",
		handler: async (_args, ctx) => {
			install(ctx, () => pi.getThinkingLevel());
			ctx.ui.notify("Applied status line", "info");
		},
	});
}
