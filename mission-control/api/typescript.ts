// The API view for TypeScript: what a module exports, as its declaration
// file. The compiler writes it from one file alone, without a type check.
//
// A module is one file. A file that its directory's index.ts re-exports from
// belongs to the directory instead: the API of index.ts, with each re-export
// followed by the declarations it brings in.
//
// The rules follow codediff.nvim's API view (lua/codediff/api/typescript.lua).
import type TS from "typescript5";
import {
	type ApiSide,
	dirname,
	type ExtractedModule,
	type ExtractRequest,
} from "./languages.ts";

type Line = { text: string; file?: string; row?: number };

// One top-level statement of a declaration file: its lines, and the source
// rows it spans.
type Entry = {
	lines: Line[];
	file?: string;
	first: number;
	last: number;
	// A group always stands apart from its neighbours.
	group?: boolean;
	// The names the statement declares, "default" for a default export.
	names: string[];
	node?: TS.Statement;
};

type Declared = {
	path: string;
	source: string[];
	entries: Entry[];
};

const BARRELS = ["index.ts", "index.tsx"];
// The extensions a sibling module's file can have, in the order an import
// without one finds them.
const EXTENSIONS = [".ts", ".tsx", ".d.ts", ".mts", ".cts"];

const BASE64 =
	"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

// Per line of generated text, the 1-based source row of its first mapping,
// read from a source map's mappings.
export function mappedRows(mappings: string): (number | undefined)[] {
	const rows: (number | undefined)[] = [];
	let sourceRow = 0;
	for (const line of mappings.split(";")) {
		let first: number | undefined;
		for (const segment of line.split(",")) {
			const fields: number[] = [];
			let value = 0;
			let shift = 0;
			for (const char of segment) {
				const digit = BASE64.indexOf(char);
				value += (digit & 31) << shift;
				shift += 5;
				// The sixth bit says another digit follows.
				if (digit & 32) continue;
				fields.push(value & 1 ? -(value >> 1) : value >> 1);
				value = 0;
				shift = 0;
			}
			// A segment is the generated column, then the source file, row and
			// column, each as a difference from the segment before.
			if (fields.length < 4) continue;
			sourceRow += fields[2];
			first ??= sourceRow + 1;
		}
		rows.push(first);
	}
	return rows;
}

// A return type, a variable's type or a property's type at the end of a
// line, where the compiler wrote a type it could not work out.
const UNKNOWN_TYPE =
	/(\)|^\s*(?:export )?(?:declare )?(?:const|let|var) [\w$]+|^\s+(?:readonly )?[\w$]+\??): (?:any|unknown);$/;

class Extractor {
	private declared = new Map<string, Declared | null>();

	constructor(
		private ts: typeof TS,
		private sources: Record<string, string>,
		private comments: boolean,
		// Whether the view keeps declarations without `export`, and private
		// class members.
		private unexported: boolean,
	) {}

	// The declaration file of one source file, as entries.
	declare(path: string): Declared | null {
		const known = this.declared.get(path);
		if (known !== undefined) return known;
		const text = this.sources[path];
		const result = text === undefined ? null : this.declarationsOf(path, text);
		this.declared.set(path, result);
		return result;
	}

	private declarationsOf(path: string, text: string): Declared {
		const { ts } = this;
		let lines: string[];
		let rows: (number | undefined)[];
		if (/\.d\.[mc]?ts$/.test(path)) {
			// A declaration file is its own API.
			lines = text.trimEnd().split("\n");
			rows = lines.map((_, i) => i + 1);
		} else {
			// The compiler writes only what a file exports. To show the rest,
			// every declaration is exported first, and the word is taken off
			// its line again below.
			const added = this.unexported ? this.exportAll(path, text) : null;
			const out = ts.transpileDeclaration(added?.text ?? text, {
				fileName: path,
				reportDiagnostics: true,
				compilerOptions: {
					declarationMap: true,
					removeComments: !this.comments,
					jsx: ts.JsxEmit.Preserve,
					target: ts.ScriptTarget.ESNext,
				},
			});
			lines = out.outputText
				.replace(/\n?\/\/# sourceMappingURL=.*\s*$/, "")
				.split("\n");
			rows = mappedRows(
				(JSON.parse(out.sourceMapText ?? "{}") as { mappings?: string })
					.mappings ?? "",
			);
			// Without a type check, a type the file does not spell out comes
			// out as `any` or `unknown`. The compiler says where, so it goes.
			const untyped = new Set(
				(out.diagnostics ?? []).flatMap((d) =>
					d.file && d.start !== undefined
						? [d.file.getLineAndCharacterOfPosition(d.start).line + 1]
						: [],
				),
			);
			lines = lines.map((line, i) => {
				const row = rows[i] ?? 0;
				const typed = untyped.has(row)
					? line.replace(UNKNOWN_TYPE, "$1;")
					: line;
				return added?.rows.has(row) ? typed.replace(/^export /, "") : typed;
			});
		}

		const file = ts.createSourceFile(
			"api.d.ts",
			lines.join("\n"),
			ts.ScriptTarget.ESNext,
			true,
		);
		const lineOf = (pos: number) =>
			file.getLineAndCharacterOfPosition(pos).line;
		const entries: Entry[] = [];
		for (const node of file.statements) {
			// The compiler keeps the imports its declarations name, and marks a
			// file without exports as a module. Neither is API.
			if (ts.isImportDeclaration(node)) continue;
			if (
				ts.isExportDeclaration(node) &&
				!node.moduleSpecifier &&
				node.exportClause &&
				ts.isNamedExports(node.exportClause) &&
				node.exportClause.elements.length === 0
			)
				continue;
			// A statement starts at its comments.
			const from = lineOf(node.getStart(file, true));
			const to = lineOf(node.getEnd());
			const kept: Line[] = [];
			let pendingComment: Line[] = [];
			let mapped: number[] = [];
			for (let i = from; i <= to; i++) {
				const textLine = lines[i];
				// A private member's name is no part of the API. Its comment
				// goes with it.
				if (
					!this.unexported &&
					i > from &&
					/^\s+(private\s|#private;)/.test(textLine)
				) {
					pendingComment = [];
					continue;
				}
				const line: Line = { text: textLine, file: path, row: rows[i] };
				if (rows[i] !== undefined) mapped.push(rows[i] as number);
				if (/^\s*(\/\*\*|\*|\/\/)/.test(textLine)) pendingComment.push(line);
				else {
					kept.push(...pendingComment, line);
					pendingComment = [];
				}
			}
			kept.push(...pendingComment);
			if (mapped.length === 0) mapped = [1];
			// A line the map does not cover, such as a comment, points at the
			// next line that it does.
			let next = mapped[mapped.length - 1];
			for (let i = kept.length - 1; i >= 0; i--) {
				if (kept[i].row === undefined) kept[i].row = next;
				else next = kept[i].row as number;
			}
			entries.push({
				lines: kept,
				file: path,
				first: Math.min(...mapped),
				last: Math.max(...mapped),
				names: this.namesOf(node),
				node,
			});
		}
		return { path, source: text.split("\n"), entries };
	}

	// The source with `export` before each top-level declaration that has
	// none, and the rows where it went. A name an export clause lists is
	// left alone: exported twice, it would not compile.
	private exportAll(path: string, text: string) {
		const { ts } = this;
		const file = ts.createSourceFile(path, text, ts.ScriptTarget.ESNext, true);
		const listed = new Set<string>();
		for (const node of file.statements)
			if (
				ts.isExportDeclaration(node) &&
				!node.moduleSpecifier &&
				node.exportClause &&
				ts.isNamedExports(node.exportClause)
			)
				for (const spec of node.exportClause.elements)
					listed.add((spec.propertyName ?? spec.name).text);
		const rows = new Set<number>();
		let out = text;
		for (const node of [...file.statements].reverse()) {
			const declares =
				ts.isFunctionDeclaration(node) ||
				ts.isClassDeclaration(node) ||
				ts.isInterfaceDeclaration(node) ||
				ts.isTypeAliasDeclaration(node) ||
				ts.isEnumDeclaration(node) ||
				ts.isModuleDeclaration(node) ||
				ts.isVariableStatement(node);
			if (!declares) continue;
			const marked = ts
				.getModifiers(node)
				?.some(
					(m) =>
						m.kind === ts.SyntaxKind.ExportKeyword ||
						m.kind === ts.SyntaxKind.DeclareKeyword,
				);
			if (marked || this.namesOf(node).some((name) => listed.has(name)))
				continue;
			const at = node.getStart(file);
			out = `${out.slice(0, at)}export ${out.slice(at)}`;
			rows.add(file.getLineAndCharacterOfPosition(at).line + 1);
		}
		return { text: out, rows };
	}

	private namesOf(node: TS.Statement): string[] {
		const { ts } = this;
		const isDefault =
			ts.canHaveModifiers(node) &&
			ts
				.getModifiers(node)
				?.some((m) => m.kind === ts.SyntaxKind.DefaultKeyword);
		if (ts.isExportAssignment(node) || isDefault) return ["default"];
		if (ts.isVariableStatement(node))
			return node.declarationList.declarations.flatMap((d) =>
				ts.isIdentifier(d.name) ? [d.name.text] : [],
			);
		const name = (node as { name?: TS.Node }).name;
		return name && ts.isIdentifier(name) ? [name.text] : [];
	}

	// The name of the module in the same directory that a statement imports
	// or re-exports from, such as server in `from "./server"`.
	private sibling(node: TS.Statement): string | null {
		const { ts } = this;
		if (!ts.isExportDeclaration(node) && !ts.isImportDeclaration(node))
			return null;
		const from = node.moduleSpecifier;
		if (!from || !ts.isStringLiteral(from)) return null;
		const name = from.text.match(/^\.\/([^/]+)$/)?.[1];
		return name ? name.replace(/\.[mc]?[jt]sx?$/, "") : null;
	}

	private load(dir: string, name: string): Declared | null {
		for (const extension of EXTENSIONS) {
			const path =
				dir === "." ? name + extension : `${dir}/${name}${extension}`;
			if (path in this.sources) return this.declare(path);
		}
		return null;
	}

	// Per name a module imports from a module in its directory: that module
	// and the name there.
	private importsOf(
		path: string,
	): Map<string, { module: string; name: string }> {
		const { ts } = this;
		const imports = new Map<string, { module: string; name: string }>();
		const file = ts.createSourceFile(
			path,
			this.sources[path] ?? "",
			ts.ScriptTarget.ESNext,
			false,
		);
		for (const node of file.statements) {
			const module = this.sibling(node);
			if (!module || !ts.isImportDeclaration(node)) continue;
			const clause = node.importClause;
			if (clause?.name)
				imports.set(clause.name.text, { module, name: "default" });
			const named = clause?.namedBindings;
			if (named && ts.isNamedImports(named))
				for (const spec of named.elements)
					imports.set(spec.name.text, {
						module,
						name: (spec.propertyName ?? spec.name).text,
					});
		}
		return imports;
	}

	// The declarations of what a module exports as name, following its
	// imports and re-exports from other modules of the directory.
	private resolve(
		dir: string,
		module: string,
		name: string,
		visited: Set<string>,
	): Entry[] {
		const { ts } = this;
		const declared = this.load(dir, module);
		if (!declared || visited.has(declared.path)) return [];
		visited.add(declared.path);

		// `export { a as b }` gives a its outside name.
		let local = name;
		for (const { node } of declared.entries)
			if (
				node &&
				ts.isExportDeclaration(node) &&
				!node.moduleSpecifier &&
				node.exportClause &&
				ts.isNamedExports(node.exportClause)
			)
				for (const spec of node.exportClause.elements)
					if (spec.name.text === name)
						local = (spec.propertyName ?? spec.name).text;

		const found = declared.entries.filter((e) => e.names.includes(local));
		if (found.length > 0) return found;

		const imported = this.importsOf(declared.path).get(local);
		if (imported)
			return this.resolve(dir, imported.module, imported.name, visited);
		for (const { node } of declared.entries) {
			const sibling = node && this.sibling(node);
			if (!sibling || !node || !ts.isExportDeclaration(node)) continue;
			const clause = node.exportClause;
			if (!clause) {
				// export * from "./x"
				const all = this.resolve(dir, sibling, name, visited);
				if (all.length > 0) return all;
			} else if (ts.isNamedExports(clause))
				for (const spec of clause.elements)
					if (spec.name.text === name)
						return this.resolve(
							dir,
							sibling,
							(spec.propertyName ?? spec.name).text,
							visited,
						);
		}
		return [];
	}

	// The directory's API, from its index.ts: its own entries, and each
	// re-export from another module of the directory followed by the
	// declarations it brings in.
	private barrelEntries(barrel: Declared): Entry[] {
		const { ts } = this;
		const dir = dirname(barrel.path);
		const imports = this.importsOf(barrel.path);
		return barrel.entries.map((entry): Entry => {
			const node = entry.node;
			if (!node || !ts.isExportDeclaration(node)) return entry;
			const sibling = this.sibling(node);
			const clause = node.exportClause;
			let definitions: Entry[] = [];
			if (clause && ts.isNamedExports(clause)) {
				for (const spec of clause.elements) {
					const original = (spec.propertyName ?? spec.name).text;
					// import { X } from "./x"; export { X }
					const imported = imports.get(original);
					if (sibling)
						definitions.push(
							...this.resolve(dir, sibling, original, new Set()),
						);
					else if (imported)
						definitions.push(
							...this.resolve(dir, imported.module, imported.name, new Set()),
						);
				}
			} else if (sibling) {
				// export * from "./x", or export * as x from "./x"
				definitions = (this.load(dir, sibling)?.entries ?? []).filter(
					(e) => !e.names.includes("default"),
				);
			}
			if (definitions.length === 0) return entry;
			return {
				...entry,
				lines: this.join(definitions, [...entry.lines]),
				group: true,
			};
		});
	}

	// Whether two entries in a row are apart in the source: a blank line
	// between them. Groups, entries from different files and entries out of
	// source order are always apart.
	private apart(above: Entry, below: Entry): boolean {
		if (above.group || below.group || above.file !== below.file) return true;
		if (below.first <= above.last) return true;
		const source = this.declare(above.file ?? "")?.source ?? [];
		for (let row = above.last + 1; row < below.first; row++)
			if (!(source[row - 1] ?? "").trim()) return true;
		return false;
	}

	private join(entries: Entry[], out: Line[] = []): Line[] {
		let previous: Entry | null = null;
		for (const entry of entries) {
			if (previous && this.apart(previous, entry)) out.push({ text: "" });
			out.push(...entry.lines);
			previous = entry;
		}
		return out;
	}

	// The API of the file at path, or of the directory it is the index.ts of.
	view(path: string, barrel: boolean): Line[] {
		const declared = this.declare(path);
		if (!declared) return [];
		return this.join(barrel ? this.barrelEntries(declared) : declared.entries);
	}
}

function side(lines: Line[]): ApiSide {
	const sources = [
		...new Set(lines.flatMap((line) => (line.file ? [line.file] : []))),
	].sort();
	return {
		lines: lines.map((line) => line.text),
		sources,
		targets: lines.map((line) =>
			line.file && line.row !== undefined
				? [sources.indexOf(line.file), line.row]
				: [-1, 0],
		),
	};
}

// The directory's index.ts, or its index.tsx without one.
function barrelOf(sources: Record<string, string>, path: string) {
	const dir = dirname(path);
	return BARRELS.map((name) => (dir === "." ? name : `${dir}/${name}`)).find(
		(barrel) => barrel in sources,
	);
}

let compiler: Promise<typeof TS> | null = null;

export async function extractTypeScript(
	request: ExtractRequest,
): Promise<ExtractedModule[]> {
	// The compiler is large, so it loads with the first TypeScript module.
	compiler ??= import("typescript5").then((module) => module.default);
	const ts = await compiler;
	if (typeof ts.transpileDeclaration !== "function")
		throw new Error("typescript5 is not installed as TypeScript 5");
	const sides = { base: request.base, head: request.head };
	const extractors = {
		base: new Extractor(ts, request.base, request.comments, request.private),
		head: new Extractor(ts, request.head, request.comments, request.private),
	};
	// Which files a directory's API comes from never depends on the settings.
	const plain = {
		base: new Extractor(ts, request.base, false, false),
		head: new Extractor(ts, request.head, false, false),
	};
	const inBarrel = (at: "base" | "head", path: string) => {
		const barrel = barrelOf(sides[at], path);
		if (!barrel) return false;
		return (
			barrel === path ||
			plain[at].view(barrel, true).some((line) => line.file === path)
		);
	};

	type Found = { files: string[]; barrel: boolean; base: string; head: string };
	const found = new Map<string, Found>();
	for (const changed of request.changed) {
		const headPath = changed.path;
		const basePath = changed.prevPath ?? headPath;
		// The head commit decides the module. A deleted file goes by the base
		// commit.
		let grouped: boolean;
		let barrel: string | undefined;
		if (headPath in sides.head) {
			grouped = inBarrel("head", headPath);
			barrel = barrelOf(sides.head, headPath);
		} else if (basePath in sides.base) {
			grouped = inBarrel("base", basePath);
			barrel = barrelOf(sides.base, basePath);
		} else continue;
		const key = grouped && barrel ? barrel : headPath;
		const module = found.get(key) ?? {
			files: [],
			barrel: grouped,
			base: grouped ? key : basePath,
			head: key,
		};
		module.files.push(headPath);
		found.set(key, module);
	}

	return [...found.entries()]
		.sort(([a], [b]) => a.localeCompare(b))
		.map(([id, module]) => ({
			id,
			files: module.files.sort(),
			base:
				module.base in sides.base
					? side(extractors.base.view(module.base, module.barrel))
					: null,
			head:
				module.head in sides.head
					? side(extractors.head.view(module.head, module.barrel))
					: null,
		}));
}
