// Reads source files of a repository at a commit, for the API view. GitHub's
// patches hold only the changed lines, and a module's API needs every file of
// the module.
//
// Each repository gets a bare git repository in the cache folder. It holds
// only what the API views asked for: the commits fetched at depth 1 without
// their blobs, and the blobs of the directories that were read.
import { mkdir, readdir, rm, stat, utimes } from "node:fs/promises";
import { join } from "node:path";

export type Repo = {
	// The bare repository's folder.
	dir: string;
	url: string;
	// The value of an Authorization header, or null for a remote that needs
	// none. git gets it through the environment, so it never reaches the disk
	// or a log.
	auth: string | null;
};

type Run = { stdin?: string; network?: boolean };

// A fetch that takes longer than this is given up.
const GIT_TIMEOUT_MS = 120_000;

async function git(repo: Repo, args: string[], run: Run = {}): Promise<Buffer> {
	const env: Record<string, string | undefined> = {
		...Bun.env,
		GIT_TERMINAL_PROMPT: "0",
		GIT_ASKPASS: "true",
		// A read never fetches by itself: a missing commit would pull in its
		// whole history. Every fetch below is explicit.
		GIT_NO_LAZY_FETCH: "1",
		// The user's own git settings, such as a rewrite of https URLs to ssh,
		// stay out of it.
		GIT_CONFIG_GLOBAL: "/dev/null",
	};
	// No credential helper: one that asks, such as the macOS keychain, would
	// leave a refused fetch waiting for an answer.
	const config = [["credential.helper", ""]];
	if (run.network && repo.auth)
		config.push(["http.extraHeader", `Authorization: ${repo.auth}`]);
	env.GIT_CONFIG_COUNT = String(config.length);
	config.forEach(([key, value], i) => {
		env[`GIT_CONFIG_KEY_${i}`] = key;
		env[`GIT_CONFIG_VALUE_${i}`] = value;
	});
	const proc = Bun.spawn(["git", "-C", repo.dir, ...args], {
		env,
		stdin: run.stdin === undefined ? "ignore" : Buffer.from(run.stdin),
		stdout: "pipe",
		stderr: "pipe",
		timeout: GIT_TIMEOUT_MS,
	});
	const [out, err, code] = await Promise.all([
		new Response(proc.stdout).arrayBuffer(),
		new Response(proc.stderr).text(),
		proc.exited,
	]);
	if (code !== 0) {
		const why = proc.signalCode ? "timed out" : err.trim() || `exit ${code}`;
		throw new Error(
			`git ${args.find((arg) => /^[a-z][a-z-]*$/.test(arg))}: ${why}`,
		);
	}
	return Buffer.from(out);
}

async function exists(path: string) {
	return stat(path).then(
		() => true,
		() => false,
	);
}

async function init(repo: Repo) {
	if (await exists(join(repo.dir, "HEAD"))) return;
	await mkdir(repo.dir, { recursive: true });
	await git(repo, ["init", "--bare", "--quiet"]);
	// A partial clone of origin: git accepts that blobs are missing.
	for (const [key, value] of [
		["remote.origin.url", repo.url],
		["remote.origin.promisor", "true"],
		["remote.origin.partialclonefilter", "blob:none"],
		["core.repositoryformatversion", "1"],
		["extensions.partialclone", "origin"],
		// No ref points at what the fetches bring in, so a collection would
		// throw it away.
		["gc.auto", "0"],
	])
		await git(repo, ["config", key, value]);
}

// One git command at a time in each repository.
const queues = new Map<string, Promise<unknown>>();

export function locked<T>(repo: Repo, work: () => Promise<T>): Promise<T> {
	const next = (queues.get(repo.dir) ?? Promise.resolve()).then(work, work);
	queues.set(
		repo.dir,
		next.catch(() => {}),
	);
	return next;
}

const FETCH = [
	"fetch",
	"--quiet",
	"--no-tags",
	"--no-write-fetch-head",
	"--filter=blob:none",
];

// Makes the commits and their trees available, without their blobs.
export async function fetchCommits(repo: Repo, shas: string[]) {
	await init(repo);
	const missing: string[] = [];
	for (const sha of new Set(shas)) {
		const has = await git(repo, ["cat-file", "-e", `${sha}^{tree}`]).then(
			() => true,
			() => false,
		);
		if (!has) missing.push(sha);
	}
	if (missing.length > 0)
		await git(repo, [...FETCH, "--depth=1", "origin", ...missing], {
			network: true,
		});
	await utimes(repo.dir, new Date(), new Date()).catch(() => {});
}

// The files directly in the given directories at a commit, as a map from
// path to blob id. "." is the repository's root.
export async function listFiles(
	repo: Repo,
	commit: string,
	dirs: string[],
): Promise<Map<string, string>> {
	const files = new Map<string, string>();
	const read = async (paths: string[]) => {
		const out = await git(repo, ["ls-tree", "-z", commit, "--", ...paths]);
		for (const entry of out.toString().split("\0")) {
			// <mode> <type> <id>\t<path>
			const tab = entry.indexOf("\t");
			if (tab < 0) continue;
			const [mode, type, id] = entry.slice(0, tab).split(" ");
			// A symlink is a blob too, with the link's target as its text.
			if (type === "blob" && mode !== "120000")
				files.set(entry.slice(tab + 1), id);
		}
	};
	const nested = dirs.filter((dir) => dir !== ".").map((dir) => `${dir}/`);
	if (nested.length > 0) await read(nested);
	if (dirs.includes(".")) await read([]);
	return files;
}

// The text of each blob, by id. Blobs the repository lacks are fetched in one
// request.
export async function readBlobs(
	repo: Repo,
	ids: string[],
): Promise<Map<string, string>> {
	const unique = [...new Set(ids)];
	const texts = new Map<string, string>();
	if (unique.length === 0) return texts;
	const stdin = `${unique.join("\n")}\n`;
	const check = await git(repo, ["cat-file", "--batch-check"], { stdin });
	const missing = check
		.toString()
		.split("\n")
		.filter((line) => line.endsWith(" missing"))
		.map((line) => line.split(" ")[0]);
	if (missing.length > 0)
		await git(
			repo,
			["-c", "fetch.negotiationAlgorithm=noop", ...FETCH, "--stdin", "origin"],
			{ stdin: `${missing.join("\n")}\n`, network: true },
		);
	// <id> blob <size>\n<bytes>\n, once per blob, in the order asked.
	const out = await git(repo, ["cat-file", "--batch"], { stdin });
	let at = 0;
	for (const id of unique) {
		const end = out.indexOf("\n", at);
		if (end < 0) break;
		const header = out.subarray(at, end).toString().split(" ");
		if (header[1] === "missing") {
			at = end + 1;
			continue;
		}
		const size = Number(header[2]);
		texts.set(id, out.subarray(end + 1, end + 1 + size).toString("utf8"));
		at = end + 1 + size + 1;
	}
	return texts;
}

async function folderBytes(dir: string): Promise<number> {
	let total = 0;
	for (const entry of await readdir(dir, { withFileTypes: true })) {
		const path = join(dir, entry.name);
		if (entry.isDirectory()) total += await folderBytes(path);
		else total += (await stat(path).catch(() => ({ size: 0 }))).size;
	}
	return total;
}

// Keeps the repositories under root within maxBytes. The repository that was
// used longest ago goes first. The one in use goes last, when it alone is
// over the limit.
export async function prune(root: string, maxBytes: number, inUse: string) {
	const names = await readdir(root).catch(() => [] as string[]);
	const repos = await Promise.all(
		names.map(async (name) => {
			const dir = join(root, name);
			return {
				dir,
				bytes: await folderBytes(dir).catch(() => 0),
				usedAt: dir === inUse ? Infinity : (await stat(dir)).mtimeMs,
			};
		}),
	);
	let total = repos.reduce((sum, repo) => sum + repo.bytes, 0);
	for (const repo of repos.sort((a, b) => a.usedAt - b.usedAt)) {
		if (total <= maxBytes) break;
		await rm(repo.dir, { recursive: true, force: true });
		total -= repo.bytes;
	}
}
