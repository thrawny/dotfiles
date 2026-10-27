import { readFileSync, watch } from "node:fs";
import { dirname, join } from "node:path";
import {
	allowed,
	type Document,
	discover,
	safeFile,
	urlPath,
} from "./catalog.ts";
import { escapeHTML, icon, page, render } from "./render.ts";

const liveScript = readFileSync(join(import.meta.dir, "live.js"), "utf8");
const indexCSS = readFileSync(join(import.meta.dir, "index.css"), "utf8");
const htmlHeaders = {
	"Content-Type": "text/html; charset=utf-8",
	"Cache-Control": "no-store",
};

function indexPage(root: string, docs: Document[]) {
	const rows = docs
		.map(
			(
				doc,
			) => `<li data-search="${escapeHTML(`${doc.title} ${doc.file} ${doc.description}`.toLowerCase())}"><a href="${urlPath(doc.route)}">
<div class="doc-title">${escapeHTML(doc.title)}</div>${doc.description ? `<p class="doc-description">${escapeHTML(doc.description)}</p>` : ""}
<div class="doc-meta"><span class="doc-path">${escapeHTML(doc.file)}</span><span>${doc.kind}</span><time datetime="${new Date(doc.modified).toISOString()}">${escapeHTML(new Date(doc.modified).toLocaleString())}</time></div></a></li>`,
		)
		.join("");
	return page(
		"Blueprint library",
		`<div class="library"><header class="meta"><h1>Blueprint library</h1><p class="root">${escapeHTML(root)}</p></header>
<div class="search"><label for="search" class="sr-only">Find a document</label><input id="search" type="search" placeholder="Find a document…" autofocus><output id="count">${docs.length} ${docs.length === 1 ? "document" : "documents"}</output></div>
<ul class="documents">${rows}</ul><p class="empty" id="empty" ${docs.length ? "hidden" : ""}>${docs.length ? "No matching documents." : "Add a Markdown or HTML file to this directory to see it here."}</p></div>`,
		`${indexCSS}.sr-only{position:absolute;width:1px;height:1px;overflow:hidden;clip-path:inset(50%)}`,
		`<script>
const input=document.getElementById('search');
input.value=new URL(location.href).searchParams.get('q')||'';
function filter(){let count=0;for(const row of document.querySelectorAll('[data-search]')){row.hidden=!row.dataset.search.includes(input.value.toLowerCase());if(!row.hidden)count++;}
document.getElementById('count').textContent=count+(count===1?' document':' documents');document.getElementById('empty').hidden=count>0;}
input.oninput=()=>{const url=new URL(location.href);if(input.value)url.searchParams.set('q',input.value);else url.searchParams.delete('q');history.replaceState(null,'',url);filter();};filter();
</script>`,
	);
}

async function inject(
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

export async function serve(root: string, port: number, linkBase?: string) {
	let revision = crypto.randomUUID();
	let catalog = await discover(root);
	const cache = new Map<string, Promise<string>>();
	let timer: ReturnType<typeof setTimeout> | undefined;
	let refreshing: Promise<void> = Promise.resolve();
	const watcher = watch(root, { recursive: true }, (_event, filename) => {
		if (filename && !allowed(String(filename))) return;
		clearTimeout(timer);
		timer = setTimeout(() => {
			// Serialize scans so a slow scan cannot publish an older catalog last.
			refreshing = refreshing
				.then(async () => {
					catalog = await discover(root);
					cache.clear();
					revision = crypto.randomUUID();
					server.publish("blueprint", revision);
				})
				.catch((error) => console.error(`blueprint-serve: ${error.message}`));
		}, 180);
	});
	watcher.on("error", (error) => {
		console.error(`blueprint-serve: watcher failed: ${error.message}`);
		shutdown();
	});
	const server = Bun.serve({
		hostname: "127.0.0.1",
		port,
		async fetch(request, server) {
			if (!["GET", "HEAD"].includes(request.method))
				return new Response("Method not allowed", { status: 405 });
			let path: string;
			try {
				path = decodeURIComponent(new URL(request.url).pathname);
			} catch {
				return new Response("Invalid URL", { status: 400 });
			}
			if (path === "/_blueprint/events") {
				if (server.upgrade(request)) return;
				return new Response("WebSocket upgrade required", { status: 426 });
			}
			// D2 compilation can outlast Bun's default HTTP idle timeout.
			server.timeout(request, 0);
			await refreshing;
			const version = revision;
			const html = async (text: string, base?: string) =>
				new Response(
					request.method === "HEAD"
						? null
						: await inject(
								text,
								version,
								base,
								new URL(request.url).pathname + new URL(request.url).search,
							),
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
			if (path === "/") return html(indexPage(root, catalog));
			let doc = catalog.find((item) => item.route === path);
			if (
				!doc &&
				!path.endsWith("/") &&
				catalog.some((item) => item.route === `${path}/`)
			)
				return Response.redirect(
					new URL(
						`${urlPath(path)}/${new URL(request.url).search}`,
						request.url,
					),
					302,
				);
			if (path.startsWith("/files/") || path.startsWith("/source/")) {
				const file = path.slice(path.indexOf("/", 1) + 1);
				const actual = await safeFile(root, file);
				if (!actual) return notFound();
				if (/\.(md|html?)$/i.test(file)) {
					doc = catalog.find((item) => item.file === file);
					if (doc && path !== doc.route)
						return Response.redirect(
							new URL(urlPath(doc.route), request.url),
							302,
						);
				}
				if (!doc) {
					if (/\.html?$/i.test(file))
						return html(await Bun.file(actual).text());
					return new Response(
						request.method === "HEAD" ? null : Bun.file(actual),
						{
							headers: {
								"Cache-Control": "no-store",
								"Content-Type":
									Bun.file(actual).type || "application/octet-stream",
							},
						},
					);
				}
			}
			if (!doc) return notFound();
			const actual = await safeFile(root, doc.file);
			if (!actual) return notFound();
			if (!cache.has(doc.file)) {
				const file = doc.file;
				const pending = (async () => {
					const text = await Bun.file(actual).text();
					if (doc.kind === "HTML") return text;
					const result = await render(text, file, linkBase);
					for (const warning of result.warnings)
						console.error(`blueprint-serve: ${file}: ${warning}`);
					return result.html;
				})();
				cache.set(file, pending);
				pending.catch(() => {
					if (cache.get(file) === pending) cache.delete(file);
				});
			}
			const directory = dirname(doc.file);
			return html(
				(await cache.get(doc.file)) || "",
				`/files/${directory === "." ? "" : `${urlPath(directory)}/`}`,
			);
		},
		websocket: {
			open(socket) {
				socket.subscribe("blueprint");
				socket.send(revision);
			},
			message() {},
		},
		async error(error) {
			console.error(error);
			return new Response(
				await inject(
					page(
						"Render failed",
						`<h1>Render failed</h1><pre>${escapeHTML(error.message)}</pre><p>Fix the source file to refresh this page.</p>`,
					),
					revision,
				),
				{ status: 500, headers: htmlHeaders },
			);
		},
	});
	function shutdown() {
		watcher.close();
		clearTimeout(timer);
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
		`Blueprint library: http://127.0.0.1:${server.port}\nServing ${root} (${catalog.length} documents)`,
	);
	return { server, shutdown };
}
