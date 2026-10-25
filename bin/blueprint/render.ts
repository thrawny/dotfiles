import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join } from "node:path";
import hljs from "highlight.js";
import MarkdownIt from "markdown-it";

export const escapeHTML = (text: string) => Bun.escapeHTML(text);
const anchorPattern = /([\w./-]+):(\d+)(?:-(\d+))?/g;
const diffKinds = new Set(["callstack", "filetree", "contract", "signatures"]);
const markers: Record<string, string> = { "+": "add", "-": "del", "~": "mod" };

export function frontmatter(text: string) {
	const match = text.match(/^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/);
	const meta: Record<string, string> = {};
	if (match) {
		for (const line of match[1].split(/\r?\n/)) {
			const pair = line.match(/^([^#:\s][^:]*):\s*(.*)$/);
			if (pair)
				meta[pair[1].trim()] = pair[2].trim().replace(/^(["'])(.*)\1$/, "$2");
		}
	}
	return { meta, body: match ? text.slice(match[0].length) : text };
}

function loadPalette(): Record<string, Record<string, string>> {
	const candidates = [
		Bun.env.BLUEPRINT_THEME,
		join(import.meta.dir, "../../nix/themes/monokai.json"),
		join(
			Bun.env.XDG_CONFIG_HOME || join(homedir(), ".config"),
			"dotfiles/theme.json",
		),
	].filter(Boolean) as string[];
	for (const file of candidates) {
		try {
			const theme = JSON.parse(readFileSync(file, "utf8"));
			if (theme.applications?.blueprint) return theme.applications.blueprint;
		} catch {
			/* Try the published theme when running from the Nix store. */
		}
	}
	throw new Error(
		"Blueprint palette missing; run just switch-hm or set BLUEPRINT_THEME to the central theme JSON.",
	);
}

const palette = loadPalette();
const variables = (mode: string) =>
	Object.entries(palette[mode])
		.map(([key, value]) => `--${key}:${value};`)
		.join("");
export const css = `:root{${variables("light")}color-scheme:light}
:root[data-theme="dark"]{${variables("dark")}color-scheme:dark}
@media(prefers-color-scheme:dark){:root:not([data-theme="light"]){${variables("dark")}color-scheme:dark}}
${readFileSync(join(import.meta.dir, "style.css"), "utf8")}`;
const themeScript = readFileSync(join(import.meta.dir, "theme.js"), "utf8");
const zoomScript = readFileSync(join(import.meta.dir, "zoom.js"), "utf8");

export function page(
	title: string,
	content: string,
	extraCSS = "",
	scripts = "",
) {
	const icon = `data:image/svg+xml,${encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><rect width="64" height="64" rx="12" fill="${palette.light.add}"/><path d="M16 20h32M16 30h24M16 40h28M16 50h18" stroke="${palette.light.bg}" stroke-width="5" stroke-linecap="round"/></svg>`)}`;
	return `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escapeHTML(title)}</title><link rel="icon" href="${escapeHTML(icon)}"><style>${css}${extraCSS}</style>
<script>${themeScript}</script></head><body>
<button id="themebtn" class="themebtn" title="Toggle light/dark" aria-label="Toggle light/dark">◐</button>
<main>${content}</main>${scripts}</body></html>`;
}

function linkAnchor(
	path: string,
	start: string,
	end: string | undefined,
	inner: string,
	base?: string,
) {
	if (!base) return `<span class="anchor">${inner}</span>`;
	const query = /\.(md|mdx|markdown)$/.test(path) ? "?plain=1" : "";
	const href = `${base.replace(/\/$/, "")}/${path.replace(/^\.\//, "")}${query}#L${start}${end ? `-L${end}` : ""}`;
	return `<a class="anchor" href="${escapeHTML(href)}" target="_blank" rel="noopener">${inner}</a>`;
}

function highlight(code: string, language: string, warnings: string[]) {
	if (!language) return escapeHTML(code);
	if (!hljs.getLanguage(language)) {
		warnings.push(`unknown fence type '${language}' rendered as plain code`);
		return escapeHTML(code);
	}
	return hljs.highlight(code, { language, ignoreIllegals: true }).value;
}

function diffBlock(kind: string, content: string, linkBase?: string) {
	const lines = content
		.replace(/\n$/, "")
		.split("\n")
		.map((line) => {
			const cls = markers[line[0]] || "ctx";
			const commentAt = line.search(/\s#\s?/);
			const body = commentAt < 0 ? line : line.slice(0, commentAt);
			const comment =
				commentAt < 0
					? ""
					: `<span class="comment">${escapeHTML(line.slice(commentAt)).replace(
							anchorPattern,
							(whole, path, start, end) =>
								linkAnchor(path, start, end, whole, linkBase),
						)}</span>`;
			const prefix = cls === "ctx" ? "" : body[0];
			const code = cls === "ctx" ? body : body.slice(1);
			const rendered =
				kind === "signatures"
					? escapeHTML(prefix) + highlight(code, "typescript", [])
					: escapeHTML(body);
			return `<span class="ln ${cls}">${rendered}${comment}\n</span>`;
		})
		.join("");
	return `<div class="block"><span class="badge">${kind}</span><pre class="diffish hl">${lines}</pre></div>\n`;
}

async function diagram(content: string, salt: string, warnings: string[]) {
	const fallback = () =>
		`<div class="block"><span class="badge">d2</span><pre class="diffish">${escapeHTML(content)}</pre></div>`;
	if (!Bun.which("d2")) {
		warnings.push("d2 not found on PATH, diagram kept as source text");
		return fallback();
	}
	const child = Bun.spawn(
		[
			"d2",
			"--no-xml-tag",
			"--omit-version",
			"--pad",
			"20",
			"--theme",
			"0",
			"--scale",
			"1",
			"--salt",
			salt,
			"-",
			"-",
		],
		{
			stdin: new Blob([content]),
			stdout: "pipe",
			stderr: "pipe",
		},
	);
	let timedOut = false;
	const timer = setTimeout(() => {
		timedOut = true;
		child.kill();
	}, 30_000);
	try {
		const [svg, error, exit] = await Promise.all([
			new Response(child.stdout).text(),
			new Response(child.stderr).text(),
			child.exited,
		]);
		if (exit !== 0 || timedOut) {
			warnings.push(
				timedOut
					? "d2 timed out after 30s, diagram kept as source text"
					: `d2 failed, diagram kept as source text: ${error.trim().split("\n")[0] || `exit ${exit}`}`,
			);
			return fallback();
		}
		return `<div class="figure d2-figure">${svg}</div>`;
	} finally {
		clearTimeout(timer);
	}
}

export async function render(text: string, source: string, linkBase?: string) {
	const { meta, body } = frontmatter(text);
	const warnings: string[] = [];
	const title =
		meta.title || basename(source).replace(/(?:\.blueprint)?\.md$/, "");
	if (!meta.title) warnings.push(`no title in frontmatter, using '${title}'`);
	const md = new MarkdownIt("commonmark")
		.enable("table")
		.enable("strikethrough");
	const diagrams: { placeholder: string; content: string }[] = [];
	// A per-render token prevents document text from colliding with placeholders.
	const nonce = crypto.randomUUID();
	md.renderer.rules.fence = (tokens, index) => {
		const { content, info } = tokens[index];
		const kind = info.trim().split(/\s+/)[0];
		if (diffKinds.has(kind)) return diffBlock(kind, content, linkBase);
		if (kind === "mockup")
			return `<div class="block"><span class="badge">mockup</span><iframe title="Mockup" class="mockup" sandbox="" srcdoc="${escapeHTML(content)}"></iframe></div>\n`;
		if (kind === "d2") {
			const placeholder = `<!--${nonce}-${diagrams.length}-->`;
			diagrams.push({ placeholder, content });
			return placeholder;
		}
		return `<pre class="hl"><code>${highlight(content, kind, warnings)}</code></pre>\n`;
	};
	if (linkBase)
		md.renderer.rules.code_inline = (tokens, index) => {
			const text = tokens[index].content;
			const code = `<code>${escapeHTML(text)}</code>`;
			const match = text.match(/^([\w./-]+):(\d+)(?:-(\d+))?$/);
			return match
				? linkAnchor(match[1], match[2], match[3], code, linkBase)
				: code;
		};
	const tokens = md.parse(body, {});
	const toc: { slug: string; title: string }[] = [];
	const slugs = new Set<string>();
	for (let i = 0; i < tokens.length; i++) {
		if (tokens[i].type !== "heading_open" || tokens[i].tag !== "h2") continue;
		const heading = tokens[i + 1].content;
		const base =
			heading
				.toLowerCase()
				.replace(/[^a-z0-9]+/g, "-")
				.replace(/^-|-$/g, "") || "section";
		let slug = base;
		for (let n = 2; slugs.has(slug); n++) slug = `${base}-${n}`;
		slugs.add(slug);
		tokens[i].attrSet("id", slug);
		toc.push({ slug, title: heading });
	}
	let html = md.renderer.render(tokens, md.options, {});
	// Sequential compilation bounds D2 CPU/memory use for large documents.
	for (const [i, item] of diagrams.entries())
		html = html.replace(
			item.placeholder,
			await diagram(item.content, `bp${i}`, warnings),
		);
	const nav =
		toc.length < 4
			? ""
			: `<nav class="toc">${toc.map(({ slug, title }) => `<a href="#${slug}">${escapeHTML(title)}</a>`).join("")}</nav>`;
	const header = `<header class="meta">${meta.tier ? `<span class="tier">${escapeHTML(meta.tier)}</span>` : ""}<h1>${escapeHTML(title)}</h1>${meta.description ? `<p>${escapeHTML(meta.description)}</p>` : ""}</header>`;
	const footer = `<footer>Rendered from <code>${escapeHTML(source)}</code> on ${new Date().toISOString().slice(0, 10)} — source file is the single source of truth.</footer>`;
	return {
		html: page(
			title,
			header + nav + html + footer,
			"",
			diagrams.length ? `<script>${zoomScript}</script>` : "",
		),
		warnings,
	};
}
