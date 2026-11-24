import { afterAll, describe, expect, test } from "bun:test";
import { mkdtemp, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
	type ApiSide,
	apiLanguage,
	type ExtractedModule,
	type ExtractRequest,
	LANGUAGES,
	pathsToRead,
} from "./languages.ts";
import { apiView, EXTRACTORS } from "./view.ts";

const TESTDATA = join(import.meta.dir, "testdata");

// A case file holds the sources of both commits, each under a line such as
// `=== head internal/store/store.go`.
function parseCase(text: string): Pick<ExtractRequest, "base" | "head"> {
	const sides: Record<string, Record<string, string>> = { base: {}, head: {} };
	let lines: string[] | null = null;
	let end = () => {};
	for (const line of text.split("\n")) {
		const header = line.match(/^=== (base|head) (.+)$/);
		if (!header) {
			lines?.push(line);
			continue;
		}
		end();
		const collected: string[] = [];
		lines = collected;
		end = () => {
			sides[header[1]][header[2]] = `${collected.join("\n").trimEnd()}\n`;
		};
	}
	end();
	return { base: sides.base, head: sides.head };
}

// The API text with the source of each line beside it.
function renderSide(side: ApiSide | null): string {
	if (!side) return "(none)";
	const at = side.targets.map(([file, line]) =>
		file < 0 ? "" : `${side.sources[file]}:${line}`,
	);
	const width = Math.max(0, ...at.map((text) => text.length));
	return side.lines
		.map((line, i) => `${at[i].padEnd(width)} | ${line}`.trimEnd())
		.join("\n");
}

function render(modules: ExtractedModule[]): string {
	return modules
		.map(
			(module) =>
				`## ${module.id}\nfiles: ${module.files.join(", ")}\n-- base\n${renderSide(module.base)}\n-- head\n${renderSide(module.head)}\n`,
		)
		.join("\n");
}

// Each case's expected API text is beside it, in <case>.api.txt. Run the
// tests with UPDATE_GOLDEN=1 to write it again.
describe("extractors", async () => {
	const cases = (await readdir(TESTDATA)).filter(
		(name) => name.endsWith(".txt") && !name.endsWith(".api.txt"),
	);
	for (const name of cases) {
		const language = LANGUAGES.find((l) => name.startsWith(`${l.id}-`));
		const extract = language && EXTRACTORS[language.id];
		if (!language || !extract) throw new Error(`No extractor for ${name}`);
		test(name, async () => {
			const sources = parseCase(await Bun.file(join(TESTDATA, name)).text());
			const changed = [
				...new Set([
					...Object.keys(sources.base),
					...Object.keys(sources.head),
				]),
			]
				.filter((path) => sources.base[path] !== sources.head[path])
				.filter((path) => apiLanguage(path) === language)
				.sort()
				.map((path) => ({ path, prevPath: null }));
			let actual = "";
			for (const comments of [false, true])
				actual += `# comments ${comments ? "shown" : "hidden"}\n\n${render(
					await extract({ ...sources, comments, changed }),
				)}\n`;
			const golden = Bun.file(
				join(TESTDATA, name.replace(/\.txt$/, ".api.txt")),
			);
			if (Bun.env.UPDATE_GOLDEN) await Bun.write(golden, actual);
			expect(actual).toBe(await golden.text());
		});
	}
});

describe("paths", () => {
	test("a test file has no API view", () => {
		expect(apiLanguage("pkg/store.go")?.id).toBe("go");
		expect(apiLanguage("pkg/store_test.go")).toBeNull();
		expect(apiLanguage("app/tests/helpers.py")).toBeNull();
		expect(apiLanguage("app/test_server.py")).toBeNull();
		expect(apiLanguage("web/list.test.tsx")).toBeNull();
		expect(apiLanguage("web/list.tsx")?.id).toBe("typescript");
		expect(apiLanguage("README.md")).toBeNull();
	});

	test("a Go package reads every file of its directory but tests", () => {
		const [go] = LANGUAGES;
		expect(
			pathsToRead(
				go,
				[{ path: "pkg/a.go", prevPath: null }],
				["pkg/a.go", "pkg/b.go", "pkg/a_test.go", "pkg/notes.md", "main.go"],
			),
		).toEqual(["pkg/a.go", "pkg/b.go"]);
	});

	test("a Python file reads its package only where one exists", () => {
		const python = LANGUAGES[1];
		const changed = [
			{ path: "app/server.py", prevPath: null },
			{ path: "tool.py", prevPath: "scripts/tool.py" },
		];
		expect(
			pathsToRead(python, changed, [
				"app/__init__.py",
				"app/server.py",
				"app/client.py",
				"tool.py",
				"setup.py",
			]),
		).toEqual(["tool.py", "app/__init__.py", "app/server.py", "app/client.py"]);
		// At the base commit the renamed file is under its old path.
		expect(
			pathsToRead(python, changed, ["scripts/tool.py", "scripts/other.py"]),
		).toEqual(["scripts/tool.py"]);
	});
});

// A pull request against a real git repository: the sources come from a
// fetch, as they do from GitHub.
describe("apiView", () => {
	const dirs: string[] = [];
	afterAll(async () => {
		for (const dir of dirs) await rm(dir, { recursive: true, force: true });
	});

	async function git(cwd: string, ...args: string[]) {
		const proc = Bun.spawn(["git", ...args], {
			cwd,
			env: {
				...Bun.env,
				GIT_CONFIG_GLOBAL: "/dev/null",
				GIT_AUTHOR_NAME: "test",
				GIT_AUTHOR_EMAIL: "test@example.com",
				GIT_COMMITTER_NAME: "test",
				GIT_COMMITTER_EMAIL: "test@example.com",
			},
			stdout: "pipe",
			stderr: "pipe",
		});
		const [out, code] = await Promise.all([
			new Response(proc.stdout).text(),
			proc.exited,
		]);
		if (code !== 0) throw new Error(`git ${args.join(" ")} failed`);
		return out.trim();
	}

	test("reads each module at both commits", async () => {
		const root = await mkdtemp(join(tmpdir(), "mission-control-api-"));
		dirs.push(root);
		const origin = join(root, "origin");
		await git(root, "init", "--quiet", "--initial-branch=main", origin);
		// What GitHub allows: a fetch of any commit or blob, without blobs.
		await git(origin, "config", "uploadpack.allowFilter", "true");
		await git(origin, "config", "uploadpack.allowAnySHA1InWant", "true");
		const commit = async (files: Record<string, string | null>) => {
			for (const [path, text] of Object.entries(files)) {
				if (text === null) await git(origin, "rm", "--quiet", path);
				else await Bun.write(join(origin, path), text);
			}
			await git(origin, "add", "--all");
			await git(origin, "commit", "--quiet", "--message", "change");
			return git(origin, "rev-parse", "HEAD");
		};
		const base = await commit({
			"store/store.go": "package store\n\nfunc Open() {}\n",
			"store/keys.go": "package store\n\ntype Key string\n",
			"old/old.go": "package old\n\nfunc Gone() {}\n",
			"README.md": "# Store\n",
		});
		const head = await commit({
			"store/store.go": "package store\n\nfunc Open(path string) {}\n",
			"store/store_test.go": "package store\n\nfunc TestOpen() {}\n",
			"fresh/fresh.go": "package fresh\n\nfunc New() {}\n",
			"old/old.go": null,
			"README.md": "# The store\n",
		});

		const view = await apiView(
			{ dir: join(root, "cache.git"), url: `file://${origin}`, auth: null },
			base,
			head,
			[
				{ path: "store/store.go", prevPath: null, status: "modified" },
				{ path: "store/store_test.go", prevPath: null, status: "added" },
				{ path: "fresh/fresh.go", prevPath: null, status: "added" },
				{ path: "old/old.go", prevPath: null, status: "removed" },
				{ path: "README.md", prevPath: null, status: "modified" },
			],
			false,
		);

		expect(view.errors).toEqual([]);
		expect(
			view.modules.map((m) => ({
				id: m.id,
				files: m.files,
				base: m.base?.lines ?? null,
				head: m.head?.lines ?? null,
			})),
		).toEqual([
			{
				id: "fresh/package fresh",
				files: ["fresh/fresh.go"],
				base: null,
				head: ["package fresh", "", "func New()"],
			},
			{
				id: "old/package old",
				files: ["old/old.go"],
				base: ["package old", "", "func Gone()"],
				head: null,
			},
			{
				id: "store/package store",
				files: ["store/store.go"],
				// keys.go did not change, and its type is in the API all the same.
				base: ["package store", "", "func Open()", "", "type Key string"],
				head: [
					"package store",
					"",
					"func Open(path string)",
					"",
					"type Key string",
				],
			},
		]);
	});
});
