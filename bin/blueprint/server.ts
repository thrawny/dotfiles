import { readFileSync, watch } from "node:fs";
import { dirname, join } from "node:path";
import {
	allowed,
	type Document,
	discover,
	safeFile,
	urlPath,
} from "./catalog.ts";
import {
	escapeHTML,
	icon,
	page,
	type RenderOptions,
	render,
} from "./render.ts";

const liveScript = readFileSync(join(import.meta.dir, "live.js"), "utf8");
export const indexCSS = readFileSync(
	join(import.meta.dir, "index.css"),
	"utf8",
);
const htmlHeaders = {
	"Content-Type": "text/html; charset=utf-8",
	"Cache-Control": "no-store",
};

/** One file a source agreed to serve. */
export type SourceFile = {
	text(): Promise<string>;
	body(): BodyInit | Promise<BodyInit>;
	type: string;
};

/** A set of documents and the files beside them, such as a folder or a git commit. */
export interface Source {
	docs: Document[];
	/** Returns the file, or null when the source does not list it. */
	open(file: string): Promise<SourceFile | null>;
}

/** Maps URLs to index pages and to the sources mounted under them. */
export interface Site {
	/** Waits for scans in flight, so a request never sees an older catalog. */
	ready(): Promise<void>;
	/** The index page for path, or undefined when path is not an index. */
	index(path: string, query: URLSearchParams): Promise<string | undefined>;
	/** The source whose URL prefix starts path. The prefix has no trailing slash. */
	mount(path: string): Promise<{ prefix: string; source: Source } | undefined>;
	/** The live-reload topic of a page: pages reload only when their topic changes. */
	topic(path: string): string;
	/** Calls listener with a topic whenever that topic's content changes. */
	subscribe(listener: (topic: string) => void): void;
	describe(): string;
	close(): void;
}

export function documentRows(docs: Document[], prefix = "") {
	return docs
		.map(
			(
				doc,
			) => `<li data-search="${escapeHTML(`${doc.title} ${doc.file} ${doc.description}`.toLowerCase())}"><a href="${urlPath(prefix + doc.route)}">
<div class="doc-title">${escapeHTML(doc.title)}</div>${doc.description ? `<p class="doc-description">${escapeHTML(doc.description)}</p>` : ""}
<div class="doc-meta"><span class="doc-path">${escapeHTML(doc.file)}</span><span>${doc.kind}</span><time datetime="${new Date(doc.modified).toISOString()}">${escapeHTML(new Date(doc.modified).toLocaleString())}</time></div></a></li>`,
		)
		.join("");
}

/** Search box script: hides rows, and groups whose rows are all hidden. */
export const searchScript = `<script>
const input=document.getElementById('search');
input.value=new URL(location.href).searchParams.get('q')||'';
function filter(){let count=0;const query=input.value.toLowerCase();for(const row of document.querySelectorAll('[data-search]')){row.hidden=!row.dataset.search.includes(query);if(!row.hidden)count++;}
for(const group of document.querySelectorAll('[data-group]')){const rows=group.querySelectorAll('[data-search]');const shown=[...rows].some((row)=>!row.hidden);group.hidden=rows.length>0&&!shown;if(group.tagName==='DETAILS'&&query)group.open=shown;}
document.getElementById('count').textContent=count+(count===1?' document':' documents');document.getElementById('empty').hidden=count>0;}
input.oninput=()=>{const url=new URL(location.href);if(input.value)url.searchParams.set('q',input.value);else url.searchParams.delete('q');history.replaceState(null,'',url);filter();};filter();
</script>`;

function indexPage(root: string, docs: Document[]) {
	return page(
		"Blueprint library",
		`<div class="library"><header class="meta"><h1>Blueprint library</h1><p class="root">${escapeHTML(root)}</p></header>
<div class="search"><label for="search" class="sr-only">Find a document</label><input id="search" type="search" placeholder="Find a document…" autofocus><output id="count">${docs.length} ${docs.length === 1 ? "document" : "documents"}</output></div>
<ul class="documents">${documentRows(docs)}</ul><p class="empty" id="empty" ${docs.length ? "hidden" : ""}>${docs.length ? "No matching documents." : "Add a Markdown or HTML file to this directory to see it here."}</p></div>`,
		indexCSS,
		searchScript,
	);
}

/** Bun rejects an empty topic, so a directory's one topic needs a name. */
const directoryTopic = "directory";

const validTopic = (topic: unknown): topic is string =>
	typeof topic === "string" && topic !== "";

/** Serves one directory, as blueprint-serve always has. */
function directorySite(root: string): Site {
	const listeners: ((topic: string) => void)[] = [];
	const source: Source = {
		docs: [],
		async open(file) {
			const actual = await safeFile(root, file);
			if (!actual) return null;
			return {
				text: () => Bun.file(actual).text(),
				body: () => Bun.file(actual),
				type: Bun.file(actual).type || "application/octet-stream",
			};
		},
	};
	let refreshing: Promise<void> = discover(root).then((docs) => {
		source.docs = docs;
	});
	let timer: ReturnType<typeof setTimeout> | undefined;
	const watcher = watch(root, { recursive: true }, (_event, filename) => {
		if (filename && !allowed(String(filename))) return;
		clearTimeout(timer);
		timer = setTimeout(() => {
			// Serialize scans so a slow scan cannot publish an older catalog last.
			refreshing = refreshing
				.then(async () => {
					source.docs = await discover(root);
					for (const listener of listeners) listener(directoryTopic);
				})
				.catch((error) => console.error(`blueprint-serve: ${error.message}`));
		}, 180);
	});
	watcher.on("error", (error) => {
		console.error(`blueprint-serve: watcher failed: ${error.message}`);
		process.kill(process.pid, "SIGTERM");
	});
	return {
		ready: () => refreshing,
		async index(path) {
			return path === "/" ? indexPage(root, source.docs) : undefined;
		},
		async mount() {
			return { prefix: "", source };
		},
		topic: () => directoryTopic,
		subscribe: (listener) => listeners.push(listener),
		describe: () => `Serving ${root} (${source.docs.length} documents)`,
		close() {
			watcher.close();
			clearTimeout(timer);
		},
	};
}

export async function inject(
	html: string,
	revision: string,
	base?: string,
	route = "/",
) {
	// Rewriting the response leaves standalone HTML and source files untouched.
	const script = `<script data-blueprint-revision="${revision}">${liveScript}</script>`;
	let hasBase = false;
	let hasHead = false;
	let hasIcon = false;
	// Base must precede stylesheets/scripts: adding it at the end of head is
	// too late for the browser's resource requests. Inspect existing bases first.
	await new HTMLRewriter()
		.on("base[href]", {
			element() {
				hasBase = true;
			},
		})
		.on('link[rel~="icon" i]', {
			element() {
				hasIcon = true;
			},
		})
		.transform(new Response(html))
		.arrayBuffer();
	const iconLink = hasIcon
		? ""
		: `<link rel="icon" href="${escapeHTML(icon)}">`;
	const response = await new HTMLRewriter()
		.on("head", {
			element(element) {
				hasHead = true;
				if (base && !hasBase)
					element.prepend(`<base href="${escapeHTML(base)}">`, { html: true });
				element.append(iconLink, { html: true });
			},
		})
		.on('a[href^="#"]', {
			element(element) {
				if (base && !hasBase)
					element.setAttribute("href", route + element.getAttribute("href"));
			},
		})
		.onDocument({
			end(end) {
				end.append(script, { html: true });
			},
		})
		.transform(new Response(html))
		.text();
	if (hasHead) return response;
	return `${base && !hasBase ? `<base href="${escapeHTML(base)}">` : ""}${iconLink}${response}`;
}

export async function serve(
	root: string,
	port: number,
	options: RenderOptions = {},
) {
	return serveSite(directorySite(root), port, options);
}

export async function serveSite(
	site: Site,
	port: number,
	options: RenderOptions = {},
) {
	const revisions = new Map<string, string>();
	const revision = (topic: string) => {
		let value = revisions.get(topic);
		if (!value) {
			value = crypto.randomUUID();
			revisions.set(topic, value);
		}
		return value;
	};
	// Rendered pages per topic, dropped when the topic changes.
	const caches = new Map<string, Map<string, Promise<string>>>();
	// Sites may report changes while they start, before the server exists.
	let publish = (_topic: string, _revision: string) => {};
	site.subscribe((topic) => {
		if (!validTopic(topic)) {
			console.error(
				`blueprint-serve: ignored a change with topic ${JSON.stringify(topic)}`,
			);
			return;
		}
		caches.delete(topic);
		revisions.set(topic, crypto.randomUUID());
		publish(topic, revision(topic));
	});
	await site.ready();
	const server = Bun.serve<{ topic: string }>({
		hostname: "127.0.0.1",
		port,
		async fetch(request, server) {
			if (!["GET", "HEAD"].includes(request.method))
				return new Response("Method not allowed", { status: 405 });
			const url = new URL(request.url);
			let path: string;
			try {
				path = decodeURIComponent(url.pathname);
			} catch {
				return new Response("Invalid URL", { status: 400 });
			}
			if (path === "/_blueprint/events") {
				let pagePath = url.searchParams.get("page") || "/";
				try {
					pagePath = decodeURIComponent(pagePath);
				} catch {}
				const pageTopic = site.topic(pagePath);
				if (!validTopic(pageTopic))
					return new Response("No topic", { status: 400 });
				if (server.upgrade(request, { data: { topic: pageTopic } })) return;
				return new Response("WebSocket upgrade required", { status: 426 });
			}
			// D2 compilation can outlast Bun's default HTTP idle timeout.
			server.timeout(request, 0);
			await site.ready();
			const topic = site.topic(path);
			const version = revision(topic);
			const html = async (text: string, base?: string) =>
				new Response(
					request.method === "HEAD"
						? null
						: await inject(text, version, base, url.pathname + url.search),
					{ headers: htmlHeaders },
				);
			const notFound = async () =>
				new Response(
					request.method === "HEAD"
						? null
						: await inject(
								page(
									"Document not found",
									`<h1>Document not found</h1><p>This page will refresh when the file returns.</p><p><a href="/">Browse the library</a></p>`,
								),
								version,
							),
					{ status: 404, headers: htmlHeaders },
				);
			try {
				return await respond();
			} catch (error) {
				console.error(error);
				return new Response(
					await inject(
						page(
							"Render failed",
							`<h1>Render failed</h1><pre>${escapeHTML((error as Error).message)}</pre><p>Fix the source file to refresh this page.</p>`,
						),
						version,
					),
					{ status: 500, headers: htmlHeaders },
				);
			}
			async function respond() {
				const index = await site.index(path, url.searchParams);
				if (index !== undefined) return html(index);
				const mounted = await site.mount(path);
				if (!mounted) return notFound();
				const { prefix, source } = mounted;
				const rest = path.slice(prefix.length) || "/";
				const redirect = (route: string) =>
					Response.redirect(new URL(urlPath(prefix + route), request.url), 302);
				let doc = source.docs.find((item) => item.route === rest);
				if (
					!doc &&
					!rest.endsWith("/") &&
					source.docs.some((item) => item.route === `${rest}/`)
				)
					return Response.redirect(
						new URL(`${urlPath(path)}/${url.search}`, request.url),
						302,
					);
				if (rest.startsWith("/files/") || rest.startsWith("/source/")) {
					const file = rest.slice(rest.indexOf("/", 1) + 1);
					if (!file || !allowed(file)) return notFound();
					const opened = await source.open(file);
					if (!opened) return notFound();
					if (/\.(md|html?)$/i.test(file)) {
						doc = source.docs.find((item) => item.file === file);
						if (doc && rest !== doc.route) return redirect(doc.route);
					}
					if (!doc) {
						if (/\.html?$/i.test(file)) return html(await opened.text());
						return new Response(
							request.method === "HEAD" ? null : await opened.body(),
							{
								headers: {
									"Cache-Control": "no-store",
									"Content-Type": opened.type,
								},
							},
						);
					}
				}
				if (!doc) return notFound();
				let cache = caches.get(topic);
				if (!cache) {
					cache = new Map();
					caches.set(topic, cache);
				}
				const key = `${prefix}\0${doc.file}`;
				if (!cache.has(key)) {
					const { file, kind } = doc;
					const pending = (async () => {
						const opened = await source.open(file);
						if (!opened) throw new Error(`${file} is gone`);
						const text = await opened.text();
						if (kind === "HTML") return text;
						const result = await render(text, file, options);
						for (const warning of result.warnings)
							if (!warning.startsWith("no title"))
								console.error(`blueprint-serve: ${prefix}/${file}: ${warning}`);
						return result.html;
					})();
					const owner = cache;
					owner.set(key, pending);
					pending.catch(() => {
						if (owner.get(key) === pending) owner.delete(key);
					});
				}
				const directory = dirname(doc.file);
				return html(
					(await cache.get(key)) || "",
					`${urlPath(prefix)}/files/${directory === "." ? "" : `${urlPath(directory)}/`}`,
				);
			}
		},
		websocket: {
			open(socket) {
				// One bad client must never stop the server.
				try {
					socket.subscribe(socket.data.topic);
					socket.send(revision(socket.data.topic));
				} catch (error) {
					console.error(`blueprint-serve: ${(error as Error).message}`);
					socket.close(1011, "subscribe failed");
				}
			},
			message() {},
		},
		error(error) {
			console.error(error);
			return new Response(
				page("Server error", `<pre>${escapeHTML(error.message)}</pre>`),
				{ status: 500, headers: htmlHeaders },
			);
		},
	});
	publish = (topic, value) => {
		try {
			server.publish(topic, value);
		} catch (error) {
			console.error(`blueprint-serve: ${(error as Error).message}`);
		}
	};
	function shutdown() {
		site.close();
		server.stop(true);
	}
	process.on("SIGTERM", () => {
		shutdown();
		process.exit(0);
	});
	process.on("SIGINT", () => {
		shutdown();
		process.exit(0);
	});
	console.log(
		`Blueprint library: http://127.0.0.1:${server.port}\n${site.describe()}`,
	);
	return { server, shutdown };
}
