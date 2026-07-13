import * as fs from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

type Rule = {
	name: string;
	path: string;
	content: string;
	alwaysApply: boolean;
	exts: Set<string>;
	pathHints: Set<string>;
};

function findMarkdownFiles(dir: string): string[] {
	if (!fs.existsSync(dir)) return [];
	const out: string[] = [];
	for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
		const full = path.join(dir, entry.name);
		if (entry.isDirectory()) out.push(...findMarkdownFiles(full));
		if (entry.isFile() && entry.name.endsWith(".md")) out.push(full);
	}
	return out;
}

function parseFrontmatterList(fm: string, key: string): string[] {
	const lines = fm.split("\n");
	const values: string[] = [];
	const keyRegex = new RegExp(`^\\s*${key}:\\s*(.*)$`, "i");

	for (let i = 0; i < lines.length; i++) {
		const match = lines[i].match(keyRegex);
		if (!match) continue;

		const inlineValue = match[1].trim();
		if (inlineValue.length > 0) {
			if (inlineValue.startsWith("[") && inlineValue.endsWith("]")) {
				for (const part of inlineValue.slice(1, -1).split(",")) {
					const cleaned = part.trim().replace(/^['"]|['"]$/g, "");
					if (cleaned) values.push(cleaned);
				}
			} else {
				values.push(inlineValue.replace(/^['"]|['"]$/g, ""));
			}
			continue;
		}

		for (let j = i + 1; j < lines.length; j++) {
			const next = lines[j];
			if (/^\s*$/.test(next)) continue;

			const itemMatch = next.match(/^\s*-\s*(.+)\s*$/);
			if (!itemMatch) break;

			const item = itemMatch[1].trim().replace(/^['"]|['"]$/g, "");
			if (item) values.push(item);
			i = j;
		}
	}

	return values;
}

function parseFrontmatter(raw: string): {
	content: string;
	alwaysApply: boolean;
	globs: string[];
	paths: string[];
} {
	if (!raw.startsWith("---\n")) {
		return { content: raw, alwaysApply: false, globs: [], paths: [] };
	}
	const end = raw.indexOf("\n---\n", 4);
	if (end === -1) {
		return { content: raw, alwaysApply: false, globs: [], paths: [] };
	}
	const fm = raw.slice(4, end);
	const content = raw.slice(end + 5).trim();

	const alwaysApply = /alwaysApply:\s*true/i.test(fm);
	const globs = parseFrontmatterList(fm, "globs");
	const paths = parseFrontmatterList(fm, "paths");

	return { content, alwaysApply, globs, paths };
}

function globToExts(glob: string): string[] {
	const out = new Set<string>();

	const brace = glob.match(/\.\{([^}]+)\}/);
	if (brace) {
		for (const part of brace[1].split(",")) {
			const ext = part.trim().toLowerCase();
			if (ext) out.add(ext);
		}
	}

	for (const m of glob.matchAll(/\.([a-z0-9_+-]+)/gi)) {
		out.add(m[1].toLowerCase());
	}

	return [...out];
}

function expandBraces(value: string): string[] {
	const match = value.match(/^(.*)\{([^{}]+)\}(.*)$/);
	if (!match) return [value];

	const [, before, inner, after] = match;
	const out: string[] = [];
	for (const part of inner.split(",")) {
		const trimmed = part.trim();
		if (!trimmed) continue;
		for (const expanded of expandBraces(`${before}${trimmed}${after}`)) {
			out.push(expanded);
		}
	}

	return out.length > 0 ? out : [value];
}

function pathGlobToHints(glob: string): string[] {
	const out = new Set<string>();

	for (const expanded of expandBraces(glob)) {
		let normalized = expanded.trim().replace(/^['"]|['"]$/g, "");
		normalized = normalized.replace(/\\/g, "/");
		normalized = normalized.replace(/^\.\//, "");
		normalized = normalized.replace(/^\/+/, "");
		if (!normalized) continue;

		const wildcardIndex = normalized.search(/[*?[]/);
		let literal =
			wildcardIndex === -1 ? normalized : normalized.slice(0, wildcardIndex);
		literal = literal.replace(/\/+$/, "");
		if (!literal || literal === ".") continue;

		out.add(literal.toLowerCase());
	}

	return [...out];
}

function loadRule(filePath: string): Rule | null {
	let raw = "";
	try {
		raw = fs.readFileSync(filePath, "utf8");
	} catch {
		return null;
	}

	const parsed = parseFrontmatter(raw);
	const exts = new Set<string>();
	for (const glob of parsed.globs) {
		for (const ext of globToExts(glob)) exts.add(ext);
	}

	const pathHints = new Set<string>();
	for (const pathGlob of parsed.paths) {
		for (const hint of pathGlobToHints(pathGlob)) pathHints.add(hint);
	}

	return {
		name: path.basename(filePath, ".md"),
		path: filePath,
		content: parsed.content,
		alwaysApply: parsed.alwaysApply,
		exts,
		pathHints,
	};
}

function pickRulesForRead(rules: Rule[], filePath: string): Rule[] {
	const normalized = filePath.toLowerCase().replace(/\\/g, "/");
	const ext = path.extname(normalized).slice(1);

	return rules.filter((rule) => {
		if (rule.alwaysApply) return true;
		if (rule.exts.has(ext)) return true;

		for (const pathHint of rule.pathHints) {
			if (normalized === pathHint || normalized.startsWith(`${pathHint}/`)) {
				return true;
			}
			if (normalized.includes(`/${pathHint}/`)) return true;
		}

		return false;
	});
}

function renderRules(rules: Rule[]): string {
	const blocks = rules.map((rule) => {
		const displayPath = rule.path.replace(`${process.env.HOME}/`, "~/");
		return `### ${rule.name}\nSource: ${displayPath}\n\n${rule.content}`;
	});
	return blocks.join("\n\n");
}

function existingDir(primary: string, fallback: string): string {
	return fs.existsSync(primary) ? primary : fallback;
}

export default function rulesExtension(pi: ExtensionAPI) {
	let rules: Rule[] = [];
	let appliedRuleNames = new Set<string>();

	pi.on("session_start", async (_event, ctx) => {
		const home = process.env.HOME || "";
		const dirs = [
			existingDir(
				path.join(ctx.cwd, ".pi", "rules"),
				path.join(ctx.cwd, ".claude", "rules"),
			),
			existingDir(
				path.join(home, ".pi", "agent", "rules"),
				path.join(home, ".claude", "rules"),
			),
		];

		const seen = new Set<string>();
		const loaded: Rule[] = [];
		for (const dir of dirs) {
			for (const file of findMarkdownFiles(dir)) {
				if (seen.has(file)) continue;
				seen.add(file);
				const rule = loadRule(file);
				if (rule) loaded.push(rule);
			}
		}

		rules = loaded;
		appliedRuleNames = new Set<string>();
		if (rules.length > 0) {
			ctx.ui.notify(`Loaded ${rules.length} rule(s) for Pi`, "info");
		}
	});

	pi.on("tool_result", async (event, ctx) => {
		if (rules.length === 0 || event.toolName !== "read") return;
		const input = event.input as { path?: unknown };
		if (typeof input.path !== "string") return;

		const matched = pickRulesForRead(rules, input.path);
		const newlyApplied = matched.filter(
			(rule) => !appliedRuleNames.has(rule.name),
		);
		if (newlyApplied.length === 0) return;

		for (const rule of newlyApplied) appliedRuleNames.add(rule.name);

		if (ctx.hasUI) {
			const names = newlyApplied.map((rule) => rule.name).join(", ");
			ctx.ui.notify(`Applied rule(s): ${names}`, "info");
		}

		return {
			content: [
				...event.content,
				{
					type: "text" as const,
					text: `\n\n## Task Rules\nFollow these rules for this task.\n\n${renderRules(newlyApplied)}\n`,
				},
			],
		};
	});

	pi.registerCommand("rules", {
		description: "Show loaded rule files",
		handler: async (_args, ctx) => {
			if (rules.length === 0) {
				ctx.ui.notify("No rules loaded", "warning");
				return;
			}
			const list = rules
				.map((r) => `- ${r.path.replace(`${process.env.HOME}/`, "~/")}`)
				.join("\n");
			ctx.ui.notify(`Loaded rules:\n${list}`, "info");
		},
	});
}
