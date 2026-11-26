// The API view's types, and the path rules of each language it covers.
// Shared by the server and the browser, so no Bun or DOM APIs here.

export type LanguageId = "go" | "python" | "typescript";

// A module's API at one commit. targets has one entry per line: an index
// into sources and a line number there, or -1 and 0 for a line without a
// source, such as a blank one.
export type ApiSide = {
	lines: string[];
	sources: string[];
	targets: [number, number][];
};

// One module of a pull request: a Go package, or a Python or TypeScript file
// or package. base or head is null when the module has no files at that
// commit.
export type ApiModule = {
	// A path for the file tree, such as "internal/store/package store".
	id: string;
	language: LanguageId;
	// The changed files the module covers, by their path at the head commit.
	files: string[];
	base: ApiSide | null;
	head: ApiSide | null;
};

export type ApiView = {
	baseSha: string;
	headSha: string;
	modules: ApiModule[];
	// What went wrong for a language, such as a missing toolchain. Its files
	// then keep their line diffs.
	errors: string[];
};

export type ChangedPath = { path: string; prevPath: string | null };

// What an extractor takes: the files the pull request changed in its
// language, and every file read at each commit, by path.
export type ExtractRequest = {
	comments: boolean;
	// Adds unexported declarations and private members.
	private: boolean;
	changed: ChangedPath[];
	base: Record<string, string>;
	head: Record<string, string>;
};

export type ExtractedModule = Omit<ApiModule, "language">;

function basename(path: string) {
	return path.slice(path.lastIndexOf("/") + 1);
}

export function dirname(path: string) {
	const slash = path.lastIndexOf("/");
	return slash < 0 ? "." : path.slice(0, slash);
}

type Language = {
	id: LanguageId;
	// Whether a file is source in this language, a test or not.
	source(name: string): boolean;
	// Whether a file is a test. A test is no part of a module's API, so it
	// keeps its line diff.
	test(path: string): boolean;
	// The files to read from a directory, given the names in it and the names
	// of the changed files there.
	wanted(names: string[], changed: string[]): string[];
};

const inFolder = (path: string, folders: string[]) =>
	path
		.split("/")
		.slice(0, -1)
		.some((part) => folders.includes(part));

const go: Language = {
	id: "go",
	source: (name) => name.endsWith(".go"),
	test: (path) => path.endsWith("_test.go"),
	// A package is every file of its directory.
	wanted: (names) => names.filter((name) => go.source(name) && !go.test(name)),
};

const python: Language = {
	id: "python",
	source: (name) => name.endsWith(".py"),
	test: (path) =>
		/^(test_.*|.*_test|conftest)\.py$/.test(basename(path)) ||
		inFolder(path, ["tests", "test"]),
	// A package's __init__.py can re-export from any file beside it.
	wanted: (names, changed) =>
		names.includes("__init__.py")
			? names.filter(python.source)
			: changed.filter((name) => names.includes(name)),
};

const BARRELS = ["index.ts", "index.tsx"];

const typescript: Language = {
	id: "typescript",
	source: (name) => /\.([mc]?ts|tsx)$/.test(name),
	test: (path) =>
		/\.(test|spec)\.[mc]?tsx?$/.test(path) || inFolder(path, ["__tests__"]),
	// An index.ts can re-export from any file beside it.
	wanted: (names, changed) =>
		names.some((name) => BARRELS.includes(name))
			? names.filter(typescript.source)
			: changed.filter((name) => names.includes(name)),
};

export const LANGUAGES: Language[] = [go, python, typescript];

// The language whose API view covers a file, or null: a file in another
// language, or a test.
export function apiLanguage(path: string): Language | null {
	const language = LANGUAGES.find((l) => l.source(basename(path)));
	return language && !language.test(path) ? language : null;
}

// Per commit, the directories to list for a language's changed files. A file
// can be new or gone at one commit while its module is there, so both
// commits list the directories of both paths.
export function directories(changed: ChangedPath[]): string[] {
	const dirs = new Set<string>();
	for (const file of changed) {
		dirs.add(dirname(file.path));
		if (file.prevPath) dirs.add(dirname(file.prevPath));
	}
	return [...dirs].sort();
}

// The paths to read at one commit, out of the files listed there.
export function pathsToRead(
	language: Language,
	changed: ChangedPath[],
	listed: string[],
): string[] {
	const byDir = new Map<string, string[]>();
	for (const path of listed) {
		const dir = dirname(path);
		byDir.set(dir, [...(byDir.get(dir) ?? []), basename(path)]);
	}
	const paths: string[] = [];
	for (const dir of directories(changed)) {
		const names = byDir.get(dir) ?? [];
		const here = changed
			.flatMap((file) => [file.path, file.prevPath ?? file.path])
			.filter((path) => dirname(path) === dir)
			.map(basename);
		for (const name of new Set(language.wanted(names, here)))
			paths.push(dir === "." ? name : `${dir}/${name}`);
	}
	return paths;
}
