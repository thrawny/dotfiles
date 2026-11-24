// Builds a pull request's API view: what each changed module exports at the
// base and at the head commit, without function bodies.
import { mkdir, rename, stat } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import {
	type ApiModule,
	type ApiView,
	apiLanguage,
	type ChangedPath,
	directories,
	type ExtractedModule,
	type ExtractRequest,
	LANGUAGES,
	type LanguageId,
	pathsToRead,
} from "./languages.ts";
import {
	fetchCommits,
	listFiles,
	locked,
	prune,
	type Repo,
	readBlobs,
} from "./sources.ts";
import { extractTypeScript } from "./typescript.ts";

export const CACHE_DIR = join(
	Bun.env.XDG_CACHE_HOME || join(homedir(), ".cache"),
	"mission-control",
);
// The bare repositories together stay under this size.
const REPOS_MAX_BYTES = 2 * 1024 ** 3;

type Extractor = (request: ExtractRequest) => Promise<ExtractedModule[]>;

async function helper(
	command: string[],
	request: ExtractRequest,
): Promise<ExtractedModule[]> {
	const proc = Bun.spawn(command, {
		stdin: Buffer.from(JSON.stringify(request)),
		stdout: "pipe",
		stderr: "pipe",
	});
	const [out, err, code] = await Promise.all([
		new Response(proc.stdout).text(),
		new Response(proc.stderr).text(),
		proc.exited,
	]);
	if (code !== 0) throw new Error(err.trim() || `exit ${code}`);
	return (JSON.parse(out) as { modules: ExtractedModule[] }).modules;
}

let goBinary: Promise<string> | null = null;

// The Go helper, built once into the cache folder. Its name carries a hash of
// its source, so an edit builds a new one.
export function buildGoHelper(): Promise<string> {
	goBinary ??= (async () => {
		const source = join(import.meta.dir, "goapi");
		const hash = Bun.hash(await Bun.file(join(source, "main.go")).bytes());
		const dir = join(CACHE_DIR, "bin");
		const binary = join(dir, `goapi-${hash.toString(16)}`);
		if (await stat(binary).catch(() => null)) return binary;
		await mkdir(dir, { recursive: true });
		const partial = `${binary}.${process.pid}`;
		const proc = Bun.spawn(["go", "build", "-o", partial, "."], {
			cwd: source,
			stdout: "ignore",
			stderr: "pipe",
		});
		const [err, code] = await Promise.all([
			new Response(proc.stderr).text(),
			proc.exited,
		]);
		if (code !== 0) throw new Error(`go build: ${err.trim()}`);
		await rename(partial, binary);
		return binary;
	})();
	// A failed build is tried again on the next request.
	goBinary.catch(() => {
		goBinary = null;
	});
	return goBinary;
}

export const EXTRACTORS: Partial<Record<LanguageId, Extractor>> = {
	go: async (request) => helper([await buildGoHelper()], request),
	// -I keeps Python from importing code of the reviewed repository.
	python: (request) =>
		helper(["python3", "-I", join(import.meta.dir, "pyapi.py")], request),
	typescript: extractTypeScript,
};

const NAMES: Record<LanguageId, string> = {
	go: "Go",
	python: "Python",
	typescript: "TypeScript",
};

export type Changed = ChangedPath & { status: string };

// The API view of the files a pull request changed, between two commits.
// repo is where the sources are read from.
export async function apiView(
	repo: Repo,
	baseSha: string,
	headSha: string,
	files: Changed[],
	comments: boolean,
): Promise<ApiView> {
	const view: ApiView = { baseSha, headSha, modules: [], errors: [] };
	// Per language, its changed files that have an API view.
	const jobs = LANGUAGES.flatMap((language) => {
		const changed = files
			.filter(
				(file) =>
					apiLanguage(file.path) === language ||
					(file.prevPath && apiLanguage(file.prevPath) === language),
			)
			.map((file) => ({ path: file.path, prevPath: file.prevPath }));
		const extract = EXTRACTORS[language.id];
		return changed.length > 0 && extract
			? [{ language, changed, extract }]
			: [];
	});
	if (jobs.length === 0) return view;

	// Every blob of both commits comes in one read, so in one fetch at most.
	const requests = await locked(repo, async () => {
		await fetchCommits(repo, [baseSha, headSha]);
		const dirs = directories(jobs.flatMap((job) => job.changed));
		const [base, head] = await Promise.all(
			[baseSha, headSha].map((sha) => listFiles(repo, sha, dirs)),
		);
		const wanted = jobs.map((job) => ({
			base: pathsToRead(job.language, job.changed, [...base.keys()]),
			head: pathsToRead(job.language, job.changed, [...head.keys()]),
		}));
		const ids = (paths: string[], listed: Map<string, string>) =>
			paths.map((path) => listed.get(path) as string);
		const texts = await readBlobs(
			repo,
			wanted.flatMap((w) => [...ids(w.base, base), ...ids(w.head, head)]),
		);
		const read = (paths: string[], listed: Map<string, string>) =>
			Object.fromEntries(
				paths.map((path) => [
					path,
					texts.get(listed.get(path) as string) ?? "",
				]),
			);
		await prune(join(repo.dir, ".."), REPOS_MAX_BYTES, repo.dir).catch(
			() => {},
		);
		return wanted.map(
			(w): ExtractRequest => ({
				comments,
				changed: [],
				base: read(w.base, base),
				head: read(w.head, head),
			}),
		);
	});

	await Promise.all(
		jobs.map(async (job, i) => {
			try {
				const modules = await job.extract({
					...requests[i],
					changed: job.changed,
				});
				// A module that exports nothing at either commit has no API
				// view.
				for (const module of modules)
					if (module.base?.lines.length || module.head?.lines.length)
						view.modules.push({ ...module, language: job.language.id });
			} catch (error) {
				view.errors.push(
					`${NAMES[job.language.id]}: ${(error as Error).message}`,
				);
			}
		}),
	);
	view.modules.sort((a: ApiModule, b: ApiModule) => a.id.localeCompare(b.id));
	return view;
}
