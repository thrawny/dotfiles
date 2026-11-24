// The review page for one pull request: an overview strip, the description
// and the diff, with a file list to jump between files.
import {
	CodeView,
	type CodeViewDiffItem,
	type CodeViewOptions,
	type FileDiffMetadata,
	processFile,
} from "@pierre/diffs";
import { useEffect, useMemo, useRef, useState } from "preact/hooks";
import { fileTotals, type PR, type PRFile } from "./model.ts";
import {
	ago,
	CI_TEXT,
	isDark,
	jiraHref,
	lines,
	REVIEW_MARK,
	ThemeButton,
} from "./ui.tsx";

type Detail = {
	pr: PR;
	body: string;
	headSha: string;
	files: PRFile[];
	jiraBase: string;
};

// GitHub sends each file's hunks without the git header, so the header is
// rebuilt here for the parser to learn the names and the kind of change.
function toFileDiff(file: PRFile): FileDiffMetadata {
	const before = file.prevPath ?? file.path;
	const header = [`diff --git a/${before} b/${file.path}`];
	if (file.status === "added") header.push("new file mode 100644");
	if (file.status === "removed") header.push("deleted file mode 100644");
	header.push(
		`--- ${file.status === "added" ? "/dev/null" : `a/${before}`}`,
		`+++ ${file.status === "removed" ? "/dev/null" : `b/${file.path}`}`,
	);
	const parsed = processFile(`${header.join("\n")}\n${file.patch ?? ""}\n`, {
		isGitDiff: true,
	});
	if (!parsed) throw new Error(`Cannot read the diff of ${file.path}`);
	parsed.name = file.path;
	if (file.prevPath) {
		parsed.prevName = file.prevPath;
		parsed.type = file.patch ? "rename-changed" : "rename-pure";
	}
	return parsed;
}

function isTyping(event: KeyboardEvent) {
	const target = event.composedPath()[0] as HTMLElement | undefined;
	return (
		!!target &&
		(target.isContentEditable ||
			["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName))
	);
}

// Back to the list with its filters, when the list opened this page.
function goBack() {
	const from = document.referrer.startsWith(`${location.origin}/`)
		? new URL(document.referrer)
		: null;
	if (from && !from.pathname.startsWith("/pr/") && history.length > 1)
		history.back();
	else location.href = "/";
}

export function Review({ repo, number }: { repo: string; number: number }) {
	const [data, setData] = useState<Detail | null>(null);
	const [error, setError] = useState<string | null>(null);
	const [now, setNow] = useState(Date.now());

	useEffect(() => {
		document.body.classList.add("review-mode");
		fetch(`/api/pr/${repo}/${number}`)
			.then(async (res) => {
				const json = await res.json();
				if (!res.ok) throw new Error(json.error ?? `HTTP ${res.status}`);
				setData(json);
				setNow(Date.now());
			})
			.catch((e: Error) => setError(e.message));
	}, [repo, number]);

	useEffect(() => {
		document.title = data
			? `${data.pr.title} · ${repo}#${number}`
			: `${repo}#${number}`;
	}, [data]);

	return (
		<div class="review-page">
			{error && <p class="error">Could not load the pull request: {error}</p>}
			{!data && !error && (
				<p class="muted">
					Loading {repo}#{number}…
				</p>
			)}
			{data && (
				<>
					<Strip data={data} now={now} />
					<Description body={data.body} />
					<Diff data={data} />
				</>
			)}
		</div>
	);
}

function Strip({ data, now }: { data: Detail; now: number }) {
	const { pr } = data;
	const totals = useMemo(() => fileTotals(data.files), [data.files]);
	const [mark, markText] = REVIEW_MARK[pr.reviewed];
	const approvers = pr.reviewers
		.filter((r) => r.state === "APPROVED")
		.map((r) => r.login);
	const others = pr.reviewers.filter((r) => r.state !== "APPROVED");
	return (
		<header class="strip">
			<div class="strip-main">
				<button type="button" class="back" onClick={goBack} title="Back (g)">
					←
				</button>
				<h1>{pr.title}</h1>
				<span class="muted">
					{pr.repo}#{pr.number}
				</span>
			</div>
			<div class="strip-meta">
				<span class="author">
					<img src={`https://github.com/${pr.author}.png?size=40`} alt="" />
					{pr.author}
				</span>
				<span class={`a-${pr.ageLevel}`} title={`opened ${pr.createdAt}`}>
					{ago(pr.createdAt, now)} old
				</span>
				<span class="size">
					<span class="plus">+{lines(totals.additions)}</span>{" "}
					<span class="minus">−{lines(totals.deletions)}</span>{" "}
					<span>
						{totals.files} {totals.files === 1 ? "file" : "files"}
					</span>
				</span>
				{totals.generatedFiles > 0 && (
					<span class="muted">
						{totals.generatedFiles} generated{" "}
						{totals.generatedFiles === 1 ? "file" : "files"}, ±
						{lines(totals.generatedLines)}
					</span>
				)}
				<span class="ci">
					<span class={`dot ci-${pr.ci}`} />
					{CI_TEXT[pr.ci]}
				</span>
				<span class={`r-${pr.reviewed}`}>
					{mark} {markText || "Not reviewed"}
					{approvers.length > 0 && ` by ${approvers.join(", ")}`}
				</span>
				{others.map((r) => (
					<span class="muted">
						{r.login}: {r.state.toLowerCase().replace("_", " ")}
					</span>
				))}
				{pr.labels.map((l) => (
					<span class="label" style={{ "--label": `#${l.color}` }}>
						<i class="swatch" />
						{l.name}
					</span>
				))}
				{pr.tono && (
					<span
						class={`tono ${pr.tono.stale ? "stale" : pr.tono.verdict === "lgtm" ? "lgtm" : "findings"}`}
						title={`tono review #${pr.tono.n}: ${pr.tono.verdict || "no verdict"}${pr.tono.stale ? ", new commits since" : ""}`}
					>
						tono #{pr.tono.n}
					</span>
				)}
				{pr.jiraKey &&
					(data.jiraBase ? (
						<a
							class="jira"
							href={jiraHref(data.jiraBase, pr.jiraKey)}
							target="_blank"
							rel="noopener"
						>
							{pr.jiraKey}
						</a>
					) : (
						<span class="jira">{pr.jiraKey}</span>
					))}
				<a href={pr.url} target="_blank" rel="noopener">
					GitHub ↗
				</a>
				<span class="strip-end">
					<ThemeButton />
				</span>
			</div>
		</header>
	);
}

function Description({ body }: { body: string }) {
	const [open, setOpen] = useState(false);
	// Template comments are for the author, not the reader.
	const text = body
		.replace(/<!--[\s\S]*?-->/g, "")
		.replace(/\n{3,}/g, "\n\n")
		.trim();
	if (!text) return <p class="description muted">No description.</p>;
	return (
		<button
			type="button"
			class={open ? "description open" : "description"}
			onClick={() => setOpen(!open)}
			title={open ? "Collapse" : "Expand"}
		>
			<span class="text">{text}</span>
		</button>
	);
}

function el(tag: string, cls: string, text: string) {
	const node = document.createElement(tag);
	node.className = cls;
	node.textContent = text;
	return node;
}

function Diff({ data }: { data: Detail }) {
	const root = useRef<HTMLDivElement>(null);
	const viewer = useRef<CodeView | null>(null);
	const [collapsed, setCollapsed] = useState(
		() => new Set(data.files.filter((f) => f.generated).map((f) => f.path)),
	);
	const [current, setCurrent] = useState(0);
	// A jump owns the current file until its scroll settles.
	const jumpedAt = useRef(0);
	const list = useRef<HTMLElement>(null);
	const byPath = useMemo(
		() => new Map(data.files.map((f) => [f.path, f])),
		[data.files],
	);
	const toggleRef = useRef((_path: string) => {});

	const toggle = (path: string) =>
		setCollapsed((prev) => {
			const next = new Set(prev);
			if (next.has(path)) next.delete(path);
			else next.add(path);
			return next;
		});
	toggleRef.current = toggle;

	// One viewer for the page. Header pieces read the file by the item's id.
	useEffect(() => {
		if (!root.current) return;
		// Header callbacks get the item as context, file or diff alike.
		type Context = { item: { id: string; collapsed?: boolean } };
		const options = (): CodeViewOptions<undefined, undefined> => ({
			theme: { dark: "monokai", light: "github-light" },
			themeType: isDark() ? "dark" : "light",
			diffStyle: "unified",
			hunkSeparators: "metadata",
			overflow: "scroll",
			stickyHeaders: true,
			layout: { paddingTop: 0, paddingBottom: 64, gap: 12 },
			// The library mixes a little of each diff colour into the code
			// background. A mix of 0% shows the theme's diff colours as they are.
			unsafeCSS:
				"[data-line],[data-no-newline],[data-gutter-buffer],[data-column-number]{--mix-light:0%;--mix-dark:0%}",
			renderHeaderPrefix: (_diff: unknown, context: Context) => {
				const button = el(
					"button",
					"fold",
					context.item.collapsed ? "▸" : "▾",
				) as HTMLButtonElement;
				button.type = "button";
				button.title = "Collapse or expand (x)";
				button.onclick = () => toggleRef.current(context.item.id);
				return button;
			},
			renderHeaderMetadata: (_diff: unknown, context: Context) => {
				const file = byPath.get(context.item.id);
				if (!file) return null;
				const box = el("span", "file-meta", "");
				if (file.generated) box.append(el("span", "gen", "generated"));
				// GitHub sends no patch for a pure rename, a binary file or a
				// diff too large to send. Only the last has lines to count.
				if (!file.patch && file.status === "renamed" && !file.additions)
					box.append(el("span", "muted", "Renamed, no changes"));
				else if (!file.patch && file.additions + file.deletions === 0)
					box.append(el("span", "muted", "Binary file"));
				else if (!file.patch) {
					const link = el("a", "", "Too large to show, open on GitHub");
					(link as HTMLAnchorElement).href = `${data.pr.url}/files`;
					(link as HTMLAnchorElement).target = "_blank";
					box.append(link);
				}
				return box;
			},
		});
		const view = new CodeView(options());
		view.setup(root.current);
		viewer.current = view;

		// Follow the page's light and dark switch.
		const sync = () => view.setOptions(options());
		const media = matchMedia("(prefers-color-scheme: dark)");
		media.addEventListener("change", sync);
		const observer = new MutationObserver(sync);
		observer.observe(document.documentElement, {
			attributes: true,
			attributeFilter: ["data-theme"],
		});

		// The current file is the last one whose top has scrolled past.
		let frame = 0;
		const unsubscribe = view.subscribeToScroll((top) => {
			cancelAnimationFrame(frame);
			frame = requestAnimationFrame(() => {
				if (Date.now() - jumpedAt.current < 400) return;
				let index = 0;
				data.files.forEach((f, i) => {
					const at = view.getTopForItem(f.path);
					if (at !== undefined && at <= top + 4) index = i;
				});
				setCurrent(index);
			});
		});
		return () => {
			cancelAnimationFrame(frame);
			unsubscribe();
			observer.disconnect();
			media.removeEventListener("change", sync);
			view.cleanUp();
			viewer.current = null;
		};
	}, [data]);

	// Items carry the collapsed state; a changed state bumps the version.
	const versions = useRef(new Map<string, number>());
	const diffs = useMemo(
		() => new Map(data.files.map((f) => [f.path, toFileDiff(f)])),
		[data.files],
	);
	useEffect(() => {
		const view = viewer.current;
		if (!view) return;
		const items = data.files.map((f): CodeViewDiffItem => {
			const isCollapsed = collapsed.has(f.path) || !f.patch;
			const known = view.getItem(f.path);
			let version = versions.current.get(f.path) ?? 0;
			if (known && known.collapsed !== isCollapsed) version++;
			versions.current.set(f.path, version);
			return {
				id: f.path,
				type: "diff",
				fileDiff: diffs.get(f.path) as FileDiffMetadata,
				collapsed: isCollapsed,
				version,
			};
		});
		view.setItems(items);
	}, [data, collapsed]);

	const jump = (index: number) => {
		const file = data.files[index];
		if (!file) return;
		setCurrent(index);
		jumpedAt.current = Date.now();
		viewer.current?.scrollTo({
			type: "item",
			id: file.path,
			align: "start",
			behavior: "instant",
		});
	};

	// Keep the current file visible in the file list.
	useEffect(() => {
		list.current
			?.querySelector(`[data-index="${current}"]`)
			?.scrollIntoView({ block: "nearest" });
	}, [current]);

	useEffect(() => {
		const onKey = (event: KeyboardEvent) => {
			if (event.metaKey || event.ctrlKey || event.altKey || isTyping(event))
				return;
			if (event.key === "j") jump(Math.min(current + 1, data.files.length - 1));
			else if (event.key === "k") jump(Math.max(current - 1, 0));
			else if (event.key === "x") {
				const file = data.files[current];
				if (file) toggle(file.path);
			} else if (event.key === "g") goBack();
			else return;
			event.preventDefault();
		};
		window.addEventListener("keydown", onKey);
		return () => window.removeEventListener("keydown", onKey);
	}, [current, data]);

	return (
		<div class="review-body">
			<nav class="file-list" ref={list}>
				{data.files.map((f, i) => (
					<button
						type="button"
						data-index={i}
						class={[
							"file",
							i === current && "current",
							f.generated && "generated",
						]
							.filter(Boolean)
							.join(" ")}
						onClick={() => jump(i)}
						title={f.prevPath ? `${f.prevPath} → ${f.path}` : f.path}
					>
						<span class="name">
							<span class="dir">
								{f.path.slice(0, f.path.lastIndexOf("/") + 1)}
							</span>
							{f.path.slice(f.path.lastIndexOf("/") + 1)}
						</span>
						<span class="counts">
							{f.generated && <span class="gen">gen</span>}
							<span class="plus">+{lines(f.additions)}</span>
							<span class="minus">−{lines(f.deletions)}</span>
						</span>
					</button>
				))}
			</nav>
			<div class="diff-view" ref={root} />
		</div>
	);
}
