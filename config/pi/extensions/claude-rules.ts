import * as fs from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

type Rule = {
	name: string;
	path: string;
	content: string;
	alwaysApply: boolean;
	exts: Set<string>;
	pathHints: Set<string>;
};

const LANGUAGE_KEYWORDS: Record<string, string[]> = {
	go: [" go ", " golang "],
	py: [" python ", " pytest ", " ruff "],
	rs: [" rust ", " cargo "],
	ts: [" typescript ", " ts "],
	tsx: [" react ", " tsx "],
	js: [" javascript ", " node "],
	jsx: [" react ", " jsx "],
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

function promptMentionsExt(prompt: string, ext: string): boolean {
	const normalized = ` ${prompt.toLowerCase()} `;
	if (normalized.includes(`.${ext}`)) return true;
	const keywords = LANGUAGE_KEYWORDS[ext] ?? [];
	return keywords.some((k) => normalized.includes(k));
}

function promptMentionsPath(prompt: string, pathHint: string): boolean {
	const normalizedHint = pathHint
		.toLowerCase()
		.replace(/\\/g, "/")
		.replace(/^\.?\//, "")
		.replace(/\/+$/, "");
	if (!normalizedHint) return false;

	const tokens = prompt
		.toLowerCase()
		.replace(/\\/g, "/")
		.split(/[\s`'"(),:;]+/)
		.filter(Boolean);

	for (const token of tokens) {
		const cleaned = token.replace(/^[@./]+/, "").replace(/[)\].,!?;:]+$/g, "");
		if (!cleaned) continue;
		if (cleaned === normalizedHint) return true;
		if (cleaned.startsWith(`${normalizedHint}/`)) return true;
	}

	return false;
}

function pickRules(rules: Rule[], prompt: string): Rule[] {
	return rules.filter((rule) => {
		if (rule.alwaysApply) return true;

		for (const pathHint of rule.pathHints) {
			if (promptMentionsPath(prompt, pathHint)) return true;
		}

		if (rule.exts.size === 0) return false;
		for (const ext of rule.exts) {
			if (promptMentionsExt(prompt, ext)) return true;
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

export default function claudeRulesExtension(pi: ExtensionAPI) {
	let rules: Rule[] = [];
	let appliedRuleNames = new Set<string>();

	pi.on("session_start", async (_event, ctx) => {
		const dirs = [
			path.join(ctx.cwd, ".claude", "rules"),
			path.join(process.env.HOME || "", ".claude", "rules"),
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
			ctx.ui.notify(`Loaded ${rules.length} Claude rule(s) for Pi`, "info");
		}
	});

	pi.on("before_agent_start", async (event, ctx) => {
		if (rules.length === 0) return;
		const matched = pickRules(rules, event.prompt);
		if (matched.length === 0) return;

		const newlyApplied = matched.filter((r) => !appliedRuleNames.has(r.name));
		if (newlyApplied.length === 0) return;

		for (const rule of newlyApplied) appliedRuleNames.add(rule.name);

		if (ctx.hasUI) {
			const names = newlyApplied.map((r) => r.name).join(", ");
			ctx.ui.notify(`Applied rule(s): ${names}`, "info");
		}

		return {
			systemPrompt:
				event.systemPrompt +
				`\n\n## Task Rules\nFollow these rules for this task.\n\n${renderRules(newlyApplied)}\n`,
		};
	});

	pi.registerCommand("rules", {
		description: "Show loaded Claude rule files",
		handler: async (_args, ctx) => {
			if (rules.length === 0) {
				ctx.ui.notify("No Claude rules loaded", "warning");
				return;
			}
			const list = rules
				.map((r) => `- ${r.path.replace(`${process.env.HOME}/`, "~/")}`)
				.join("\n");
			ctx.ui.notify(`Loaded rules:\n${list}`, "info");
		},
	});
}
