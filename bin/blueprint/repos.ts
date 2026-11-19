import { type FSWatcher, watch } from "node:fs";
import { readdir, stat } from "node:fs/promises";
import { basename, dirname, join } from "node:path";
import {
	allowed,
	catalog,
	type Document,
	type Entry,
	isDocument,
	safeFile,
} from "./catalog.ts";
import { escapeHTML, page } from "./render.ts";
import {
	documentRows,
	indexCSS,
	type Site,
	type Source,
	type SourceFile,
	searchScript,
} from "./server.ts";

const pollInterval = 2000;
const originInterval = 60_000;
const decoder = new TextDecoder();

async function run(args: string[], input?: Uint8Array) {
	try {
		const proc = Bun.spawn(args, {
			stdin: input ?? "ignore",
			stdout: "pipe",
			stderr: "ignore",
		});
		const [bytes, code] = await Promise.all([
			new Response(proc.stdout).bytes(),
			proc.exited,
		]);
		return { bytes, code };
	} catch {
		return { bytes: new Uint8Array(), code: -1 };
	}
}

async function git(cwd: string, ...args: string[]) {
	const { bytes, code } = await run(["git", "-C", cwd, ...args]);
	return code === 0 ? decoder.decode(bytes) : null;
}

const fileType = (file: string) =>
	Bun.file(file).type || "application/octet-stream";
const slug = (text: string) =>
	text
		.toLowerCase()
		.replace(/[^a-z0-9._-]+/g, "-")
		.replace(/^[-.]+|-+$/g, "") || "repo";

/** Picks id, or id-2, id-3 and so on, so two keys never share an id. */
function unique(ids: Map<string, string>, key: string, id: string) {
	const known = ids.get(key);
	if (known) return known;
	const taken = new Set(ids.values());
	let candidate = id;
	for (let n = 2; taken.has(candidate); n++) candidate = `${id}-${n}`;
	ids.set(key, candidate);
	return candidate;
}

/** A checkout open in Herdr: its working tree, with the files git tracks or does not ignore. */
class Checkout implements Source {
	docs: Document[] = [];
	files = new Set<string>();
	private signature = "";
	private scanning: Promise<void> = Promise.resolve();
	private watcher?: FSWatcher;
	private timer?: ReturnType<typeof setTimeout>;
	private touched = new Set<string>();

	constructor(
		readonly path: string,
		readonly repo: string,
		readonly id: string,
		public branch: string,
		private changed: () => void,
	) {}

	get topic() {
		return `open/${this.repo}/${this.id}`;
	}

	start() {
		this.scanning = this.scan().then(() => {});
		try {
			this.watcher = watch(this.path, { recursive: true }, (_event, name) => {
				if (name && !allowed(String(name))) return;
				if (name) this.touched.add(String(name));
				clearTimeout(this.timer);
				this.timer = setTimeout(() => this.rescan(), 200);
			});
			this.watcher.on("error", (error) =>
				console.error(`blueprint-serve: ${this.path}: ${error.message}`),
			);
		} catch (error) {
			console.error(
				`blueprint-serve: cannot watch ${this.path}: ${(error as Error).message}`,
			);
		}
		return this.scanning;
	}

	ready() {
		return this.scanning;
	}

	private rescan() {
		const touched = this.touched;
		this.touched = new Set();
		// Serialize scans so a slow scan cannot publish an older catalog last.
		this.scanning = this.scanning
			.then(async () => {
				const before = this.files;
				const listChanged = await this.scan();
				// A saved image or stylesheet changes no document, but its pages show it.
				const assetChanged = [...touched].some(
					(name) => before.has(name) || this.files.has(name),
				);
				if (listChanged || assetChanged) this.changed();
			})
			.catch((error) => console.error(`blueprint-serve: ${error.message}`));
	}

	/** Lists the checkout again. Returns whether the document list changed. */
	private async scan() {
		const listing = await git(
			this.path,
			"ls-files",
			"-z",
			"--cached",
			"--others",
			"--exclude-standard",
		);
		if (listing === null) return false;
		const files = new Set(listing.split("\0").filter((f) => f && allowed(f)));
		const entries: Entry[] = [];
		for (const file of files) {
			if (!isDocument(file)) continue;
			const actual = await safeFile(this.path, file);
			if (!actual) continue;
			try {
				const modified = (await stat(actual)).mtimeMs;
				entries.push({ file, modified, text: () => Bun.file(actual).text() });
			} catch {}
		}
		this.files = files;
		this.docs = await catalog(entries);
		const signature = JSON.stringify(this.docs);
		const changed = signature !== this.signature;
		this.signature = signature;
		return changed;
	}

	async open(file: string): Promise<SourceFile | null> {
		// Serve only what git lists: ignored files, such as secrets or builds, stay out.
		if (!this.files.has(file)) return null;
		const actual = await safeFile(this.path, file);
		if (!actual) return null;
		return {
			text: () => Bun.file(actual).text(),
			body: () => Bun.file(actual),
			type: fileType(file),
		};
	}

	close() {
		this.watcher?.close();
		clearTimeout(this.timer);
	}
}

/** A repo's default branch on origin, read from git objects, never from the working tree. */
class Origin implements Source {
	docs: Document[] = [];
	ref = "";
	sha = "";
	private blobs = new Map<string, string>();
	private checked = 0;
	private refreshing?: Promise<boolean>;

	constructor(
		readonly path: string,
		readonly id: string,
	) {}

	get topic() {
		return `repo/${this.id}`;
	}

	/** Reads origin again when older than maxAge. Returns whether the documents changed. */
	refresh(maxAge = 15_000) {
		if (this.refreshing) return this.refreshing;
		if (Date.now() - this.checked < maxAge) return Promise.resolve(false);
		this.refreshing = this.load().finally(() => {
			this.checked = Date.now();
			this.refreshing = undefined;
		});
		return this.refreshing;
	}

	private async load() {
		let ref = "";
		let sha = "";
		for (const candidate of ["origin/main", "origin/master", "origin/HEAD"]) {
			const resolved = await git(
				this.path,
				"rev-parse",
				"--verify",
				"--quiet",
				`${candidate}^{commit}`,
			);
			if (resolved) {
				ref = candidate;
				sha = resolved.trim();
				break;
			}
		}
		if (sha === this.sha) return false;
		const [tree, time] = await Promise.all([
			sha ? git(this.path, "ls-tree", "-r", "-z", sha) : "",
			sha ? git(this.path, "show", "-s", "--format=%ct", sha) : "0",
		]);
		const blobs = new Map<string, string>();
		for (const line of (tree || "").split("\0")) {
			const match = line.match(/^(100644|100755) blob ([0-9a-f]+)\t(.+)$/);
			if (match && allowed(match[3])) blobs.set(match[3], match[2]);
		}
		const files = [...blobs.keys()].filter(isDocument);
		const texts = await this.readBlobs(
			files.map((f) => blobs.get(f) as string),
		);
		const modified = Number(time) * 1000;
		this.docs = await catalog(
			files.map((file, i) => ({
				file,
				modified,
				text: async () => texts[i] ?? "",
			})),
		);
		this.blobs = blobs;
		this.ref = ref;
		this.sha = sha;
		return true;
	}

	/** Reads many blobs with one git process. */
	private async readBlobs(oids: string[]) {
		if (!oids.length) return [];
		const { bytes } = await run(
			["git", "-C", this.path, "cat-file", "--batch"],
			new TextEncoder().encode(`${oids.join("\n")}\n`),
		);
		const texts: string[] = [];
		let at = 0;
		for (const _ of oids) {
			const end = bytes.indexOf(10, at);
			if (end < 0) break;
			const header = decoder.decode(bytes.subarray(at, end)).split(" ");
			at = end + 1;
			if (header[1] !== "blob") {
				texts.push("");
				continue;
			}
			const size = Number(header[2]);
			texts.push(decoder.decode(bytes.subarray(at, at + size)));
			at += size + 1;
		}
		return texts;
	}

	async open(file: string): Promise<SourceFile | null> {
		const oid = this.blobs.get(file);
		if (!oid) return null;
		const blob = async () =>
			(await run(["git", "-C", this.path, "cat-file", "blob", oid])).bytes;
		return {
			text: async () => decoder.decode(await blob()),
			body: blob,
			type: fileType(file),
		};
	}
}

type Location = { toplevel: string; common: string; branch: string };

/** Asks Herdr which folders its workspaces and panes have open right now. */
async function herdrFolders() {
	const folders = new Set<string>();
	for (const kind of ["workspace", "pane"]) {
		const { bytes, code } = await run(["herdr", kind, "list"]);
		if (code !== 0) return null;
		try {
			const { result } = JSON.parse(decoder.decode(bytes));
			for (const workspace of result.workspaces ?? [])
				if (workspace.worktree?.checkout_path)
					folders.add(workspace.worktree.checkout_path);
			for (const pane of result.panes ?? [])
				if (pane.cwd) folders.add(pane.cwd);
		} catch {
			return null;
		}
	}
	return folders;
}

async function locate(folder: string): Promise<Location | null> {
	const output = await run([
		"git",
		"-C",
		folder,
		"rev-parse",
		"--path-format=absolute",
		"--show-toplevel",
		"--git-common-dir",
		"--abbrev-ref",
		"HEAD",
	]);
	const [toplevel, common, branch] = decoder.decode(output.bytes).split("\n");
	if (!toplevel || !common) return null;
	return {
		toplevel,
		common,
		branch: branch && branch !== "HEAD" ? branch : "detached",
	};
}

const repoName = (common: string) =>
	basename(common) === ".git"
		? basename(dirname(common))
		: basename(common).replace(/\.git$/, "");

function section(
	title: string,
	summary: string,
	rows: string,
	count: number,
	extra = "",
) {
	return `<details data-group><summary><span class="group-title">${escapeHTML(title)}</span> <span class="group-meta">${escapeHTML(summary)} · ${count} ${count === 1 ? "document" : "documents"}</span>${extra}</summary><ul class="documents">${rows}</ul></details>`;
}

const siteCSS = `${indexCSS}.sr-only{position:absolute;width:1px;height:1px;overflow:hidden;clip-path:inset(50%)}
.views{display:flex;gap:1.25rem;margin:0.5rem 0 0}.views a{color:var(--muted);text-decoration:none}.views a[aria-current]{color:var(--fg);font-weight:600;border-bottom:2px solid var(--accent)}
.repo{margin:1.75rem 0}.repo h2{font-size:1.25rem;margin:0 0 0.25rem}
details[data-group]{border-top:1px solid var(--line)}details[data-group] summary{cursor:pointer;padding:0.7rem 0}
.group-title{font-weight:600}.group-meta,.group-path{color:var(--muted);font-size:0.85rem}.group-path{display:block;overflow-wrap:anywhere}
details[data-group] .documents{padding-left:1rem}`;

function library(
	view: "open" | "all",
	note: string,
	groups: string,
	count: number,
) {
	const tab = (href: string, label: string, current: boolean) =>
		`<a href="${href}"${current ? ' aria-current="page"' : ""}>${label}</a>`;
	return page(
		view === "open" ? "Docs: open in Herdr" : "Docs: all repos",
		`<div class="library"><header class="meta"><h1>Docs</h1><nav class="views">${tab("/", "Open in Herdr", view === "open")}${tab("/all/", "All repos", view === "all")}</nav><p class="root">${escapeHTML(note)}</p></header>
<div class="search"><label for="search" class="sr-only">Find a document</label><input id="search" type="search" placeholder="Find a document…" autofocus><output id="count">${count} ${count === 1 ? "document" : "documents"}</output></div>
${groups}<p class="empty" id="empty" ${count ? "hidden" : ""}>${count ? "No matching documents." : view === "open" ? "No checkout open in Herdr has Markdown or HTML documents." : "No repo has documents on origin."}</p></div>`,
		siteCSS,
		searchScript,
	);
}

/**
 * Serves the docs of the checkouts open in Herdr, and of every repo under
 * codeDir as origin's default branch has them.
 */
export function reposSite(codeDir: string): Site {
	const listeners: ((topic: string) => void)[] = [];
	const notify = (...topics: string[]) => {
		for (const topic of topics)
			for (const listener of listeners) listener(topic);
	};
	const repoIds = new Map<string, string>();
	const checkoutIds = new Map<string, string>();
	const checkouts = new Map<string, Checkout>();
	const origins = new Map<string, Origin>();
	let herdrMissing = false;
	let polling: Promise<void> = Promise.resolve();
	let reposListed: Promise<void> | undefined;

	async function poll() {
		const folders = await herdrFolders();
		if (!folders) {
			if (!herdrMissing)
				console.error("blueprint-serve: herdr workspace or pane list failed");
			herdrMissing = true;
			return;
		}
		herdrMissing = false;
		const located = await Promise.all([...folders].map(locate));
		const open = new Map<string, Location>();
		for (const location of located)
			if (location) open.set(location.toplevel, location);
		let indexChanged = false;
		for (const [toplevel, checkout] of checkouts) {
			if (open.has(toplevel)) continue;
			checkout.close();
			checkouts.delete(toplevel);
			indexChanged = true;
			notify(checkout.topic);
		}
		const started: Promise<void>[] = [];
		for (const [toplevel, location] of open) {
			const existing = checkouts.get(toplevel);
			if (existing) {
				if (existing.branch !== location.branch) {
					existing.branch = location.branch;
					indexChanged = true;
				}
				continue;
			}
			const repo = unique(
				repoIds,
				location.common,
				slug(repoName(location.common)),
			);
			const id = unique(
				checkoutIds,
				toplevel,
				`${repo}/${slug(basename(toplevel))}`,
			).slice(repo.length + 1);
			const checkout: Checkout = new Checkout(
				toplevel,
				repo,
				id,
				location.branch,
				() => notify(checkout.topic, "index:open"),
			);
			checkouts.set(toplevel, checkout);
			started.push(checkout.start().then(() => notify(checkout.topic)));
			indexChanged = true;
		}
		await Promise.all(started);
		if (indexChanged) notify("index:open");
	}

	function schedule() {
		polling = polling
			.then(poll)
			.catch((error) => console.error(`blueprint-serve: ${error.message}`));
	}
	schedule();
	const firstPoll = polling;
	const poller = setInterval(schedule, pollInterval);

	/** Finds every git repo directly under codeDir, then reads origin for each. */
	async function listRepos(maxAge?: number) {
		let names: string[] = [];
		try {
			names = (await readdir(codeDir, { withFileTypes: true }))
				.filter((entry) => entry.isDirectory() && !entry.name.startsWith("."))
				.map((entry) => entry.name);
		} catch (error) {
			console.error(`blueprint-serve: ${codeDir}: ${(error as Error).message}`);
		}
		const present = new Set<string>();
		for (const name of names) {
			const path = join(codeDir, name);
			try {
				await stat(join(path, ".git"));
			} catch {
				continue;
			}
			present.add(path);
			if (!origins.has(path))
				origins.set(
					path,
					new Origin(path, unique(repoIds, join(path, ".git"), slug(name))),
				);
		}
		let changed = false;
		for (const path of origins.keys())
			if (!present.has(path)) {
				origins.delete(path);
				changed = true;
			}
		const queue = [...origins.values()];
		await Promise.all(
			Array.from({ length: 8 }, async () => {
				for (let origin = queue.shift(); origin; origin = queue.shift())
					if (await origin.refresh(maxAge)) {
						changed = true;
						notify(origin.topic);
					}
			}),
		);
		if (changed) notify("index:all");
	}
	function refreshRepos(maxAge?: number) {
		reposListed ??= listRepos(maxAge).finally(() => {
			reposListed = undefined;
		});
		return reposListed;
	}
	const originPoller = setInterval(
		() => refreshRepos(originInterval).catch(() => {}),
		originInterval,
	);
	// Warm the all-repos view, so its first visit does not wait for every repo.
	const warm = refreshRepos();

	const findOrigin = (id: string) =>
		[...origins.values()].find((origin) => origin.id === id);
	const sortedCheckouts = () =>
		[...checkouts.values()].sort(
			(a, b) =>
				a.repo.localeCompare(b.repo) ||
				a.branch.localeCompare(b.branch) ||
				a.path.localeCompare(b.path),
		);

	return {
		async ready() {
			await firstPoll;
			await Promise.all([...checkouts.values()].map((c) => c.ready()));
		},
		async index(path) {
			if (path === "/") {
				const repos = new Map<string, Checkout[]>();
				for (const checkout of sortedCheckouts())
					repos.set(checkout.repo, [
						...(repos.get(checkout.repo) ?? []),
						checkout,
					]);
				let count = 0;
				const groups = [...repos]
					.map(([repo, list]) => {
						const sections = list
							.map((checkout) => {
								count += checkout.docs.length;
								return section(
									checkout.branch,
									checkout.id,
									documentRows(checkout.docs, `/open/${repo}/${checkout.id}`),
									checkout.docs.length,
									`<span class="group-path">${escapeHTML(checkout.path)}</span>`,
								);
							})
							.join("");
						return `<section class="repo" data-group><h2>${escapeHTML(repo)}</h2>${sections}</section>`;
					})
					.join("");
				const note = herdrMissing
					? "Herdr did not answer, so this list may be out of date."
					: `${checkouts.size} ${checkouts.size === 1 ? "checkout" : "checkouts"} open in Herdr, read from the working tree.`;
				return library("open", note, groups, count);
			}
			if (path === "/all/" || path === "/all") {
				await (origins.size ? refreshRepos() : warm);
				const list = [...origins.values()]
					.filter((origin) => origin.sha)
					.sort((a, b) => a.id.localeCompare(b.id));
				let count = 0;
				const groups = list
					.map((origin) => {
						count += origin.docs.length;
						return section(
							origin.id,
							origin.ref,
							documentRows(origin.docs, `/repo/${origin.id}`),
							origin.docs.length,
						);
					})
					.join("");
				return library(
					"all",
					`${list.length} repos under ${codeDir}, read from origin's default branch.`,
					groups,
					count,
				);
			}
			return undefined;
		},
		async mount(path) {
			const parts = path.split("/");
			if (parts[1] === "open" && parts.length > 3) {
				const checkout = [...checkouts.values()].find(
					(c) => c.repo === parts[2] && c.id === parts[3],
				);
				if (!checkout) return undefined;
				await checkout.ready();
				return {
					prefix: `/open/${checkout.repo}/${checkout.id}`,
					source: checkout,
				};
			}
			if (parts[1] === "repo" && parts.length > 2) {
				if (!origins.size) await warm;
				const origin = findOrigin(parts[2]);
				if (!origin) return undefined;
				if (await origin.refresh()) notify(origin.topic, "index:all");
				return { prefix: `/repo/${origin.id}`, source: origin };
			}
			return undefined;
		},
		topic(path) {
			const parts = path.split("/");
			if (parts[1] === "open" && parts.length > 3)
				return `open/${parts[2]}/${parts[3]}`;
			if (parts[1] === "repo" && parts.length > 2) return `repo/${parts[2]}`;
			return path.startsWith("/all") ? "index:all" : "index:open";
		},
		subscribe: (listener) => listeners.push(listener),
		describe: () =>
			`Serving ${checkouts.size} checkouts open in Herdr, and the repos under ${codeDir}`,
		close() {
			clearInterval(poller);
			clearInterval(originPoller);
			for (const checkout of checkouts.values()) checkout.close();
		},
	};
}
