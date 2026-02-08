import * as fs from "node:fs";
import * as path from "node:path";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

type Rule = {
	name: string;
	path: string;
	content: string;
	alwaysApply: boolean;
	exts: Set<string>;
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

function parseFrontmatter(raw: string): {
	content: string;
	alwaysApply: boolean;
	globs: string[];
} {
	if (!raw.startsWith("---\n")) {
		return { content: raw, alwaysApply: false, globs: [] };
	}
	const end = raw.indexOf("\n---\n", 4);
	if (end === -1) {
		return { content: raw, alwaysApply: false, globs: [] };
	}
	const fm = raw.slice(4, end);
	const content = raw.slice(end + 5).trim();

	const alwaysApply = /alwaysApply:\s*true/i.test(fm);
	const globs: string[] = [];
	for (const line of fm.split("\n")) {
		const m = line.match(/^\s*globs:\s*(.+)\s*$/i);
		if (!m) continue;
		const value = m[1].trim();
		globs.push(value.replace(/^['"]|['"]$/g, ""));
	}

	return { content, alwaysApply, globs };
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

	return {
		name: path.basename(filePath, ".md"),
		path: filePath,
		content: parsed.content,
		alwaysApply: parsed.alwaysApply,
		exts,
	};
}

function promptMentionsExt(prompt: string, ext: string): boolean {
	const normalized = ` ${prompt.toLowerCase()} `;
	if (normalized.includes(`.${ext}`)) return true;
	const keywords = LANGUAGE_KEYWORDS[ext] ?? [];
	return keywords.some((k) => normalized.includes(k));
}

function pickRules(rules: Rule[], prompt: string): Rule[] {
	return rules.filter((rule) => {
		if (rule.alwaysApply) return true;
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
