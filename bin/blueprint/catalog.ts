import { readdir, realpath, stat } from "node:fs/promises";
import { isAbsolute, relative, resolve } from "node:path";
import { frontmatter } from "./render.ts";

const ignored = new Set(["node_modules", "vendor", "target", "__pycache__"]);
export const allowed = (path: string) =>
	path
		.split(/[\\/]/)
		.every((part) => !part.startsWith(".") && !ignored.has(part));
export const urlPath = (path: string) =>
	path.split("/").map(encodeURIComponent).join("/");
export type Document = {
	file: string;
	route: string;
	title: string;
	description: string;
	modified: number;
	kind: string;
};

export async function safeFile(root: string, path: string) {
	if (!path || !allowed(path)) return null;
	try {
		const actual = await realpath(resolve(root, path));
		const within = relative(root, actual);
		if (
			!within ||
			within.startsWith("..") ||
			isAbsolute(within) ||
			!allowed(within)
		)
			return null;
		return (await stat(actual)).isFile() ? actual : null;
	} catch {
		return null;
	}
}

export async function discover(root: string): Promise<Document[]> {
	const files: string[] = [];
	async function walk(folder: string, prefix = "") {
		for (const entry of await readdir(folder, { withFileTypes: true })) {
			const file = prefix + entry.name;
			if (!allowed(file) || entry.isSymbolicLink()) continue;
			if (entry.isDirectory())
				await walk(resolve(folder, entry.name), `${file}/`);
			else if (entry.isFile() && /\.(md|html?)$/i.test(file)) files.push(file);
		}
	}
	await walk(root);
	files.sort();
	const all = new Set(files);
	const docs: Document[] = [];
	for (const file of files) {
		const html = /\.html?$/i.test(file);
		const stem = file.replace(/(?:\.blueprint)?\.(md|html?)$/i, "");
		// Exported HTML is a disposable view when its Markdown source is present.
		if (html && (all.has(`${stem}.blueprint.md`) || all.has(`${stem}.md`)))
			continue;
		const actual = await safeFile(root, file);
		if (!actual) continue;
		try {
			const text = await Bun.file(actual).text();
			const meta = html ? {} : frontmatter(text).meta;
			const title = html
				? text.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1]?.trim()
				: meta.title || text.match(/^#\s+(.+)$/m)?.[1];
			const collision =
				!html &&
				!file.endsWith(".blueprint.md") &&
				all.has(`${stem}.blueprint.md`);
			docs.push({
				file,
				route: collision ? `/source/${file}` : `/docs/${stem}/`,
				title: title || stem.split("/").at(-1) || file,
				description: meta.description || "",
				modified: (await stat(actual)).mtimeMs,
				kind: html
					? "HTML"
					: file.endsWith(".blueprint.md")
						? "Blueprint"
						: "Markdown",
			});
		} catch (error) {
			// Editors may rename/delete a file between discovery and reading it.
			if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error;
		}
	}
	const occupied = new Set<string>();
	const rank = (doc: Document) =>
		doc.kind === "Blueprint" ? 0 : doc.kind === "Markdown" ? 1 : 2;
	for (const doc of [...docs].sort(
		(a, b) => rank(a) - rank(b) || a.file.localeCompare(b.file),
	)) {
		if (occupied.has(doc.route)) doc.route = `/source/${doc.file}`;
		occupied.add(doc.route);
	}
	return docs.sort(
		(a, b) => b.modified - a.modified || a.file.localeCompare(b.file),
	);
}
