// The review page for one pull request: an overview strip, the description
// and the diff, with a file list to jump between files.
import {
	CodeView,
	type CodeViewItem,
	type CodeViewOptions,
	type FileDiffMetadata,
	processFile,
} from "@pierre/diffs";
import { FileTree, type GitStatus } from "@pierre/trees";
import type { ComponentChildren } from "preact";
import { createPortal } from "preact/compat";
import { useEffect, useMemo, useRef, useState } from "preact/hooks";
import { fileTotals, type PR, type PRFile, type ReviewEvent } from "./model.ts";
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
	bodyHTML: string;
	headSha: string;
	files: PRFile[];
	jiraBase: string;
	viewer: string;
	csrfToken: string;
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

// The content of an added file, from its patch, which holds every line.
function newFileText(file: PRFile): string | null {
	if (file.status !== "added" || !file.patch) return null;
	return file.patch
		.split("\n")
		.filter((line) => line.startsWith("+"))
		.map((line) => line.slice(1))
		.join("\n");
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

	// A reload after a review keeps the diff when the head is the same.
	const load = () =>
		fetch(`/api/pr/${repo}/${number}`)
			.then(async (res) => {
				const json = (await res.json()) as Detail & { error?: string };
				if (!res.ok) throw new Error(json.error ?? `HTTP ${res.status}`);
				setData((old) =>
					old && old.headSha === json.headSha
						? { ...json, files: old.files }
						: json,
				);
				setNow(Date.now());
			})
			.catch((e: Error) => setError(e.message));

	useEffect(() => {
		document.body.classList.add("review-mode");
		load();
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
					<Strip data={data} now={now} reload={load} />
					<Diff
						files={data.files}
						prUrl={data.pr.url}
						header={<Description html={data.bodyHTML} />}
					/>
				</>
			)}
		</div>
	);
}

function Strip({
	data,
	now,
	reload,
}: {
	data: Detail;
	now: number;
	reload: () => Promise<void>;
}) {
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
					{data.viewer.toLowerCase() !== pr.author.toLowerCase() && (
						<Verdict data={data} reload={reload} />
					)}
					<ThemeButton />
				</span>
			</div>
		</header>
	);
}

const ARM_MS = 5000;

const EVENT_TEXT: Record<ReviewEvent, [string, string]> = {
	APPROVE: ["Approve", "Confirm approve"],
	COMMENT: ["Comment", "Confirm comment"],
	REQUEST_CHANGES: ["Request changes", "Confirm request changes"],
};

// Posting a review takes two clicks: the first arms the button for 5
// seconds, the second posts. a arms the approve, Enter confirms what is
// armed and Esc disarms it.
function Verdict({
	data,
	reload,
}: {
	data: Detail;
	reload: () => Promise<void>;
}) {
	const [armed, setArmed] = useState<ReviewEvent | null>(null);
	const [boxOpen, setBoxOpen] = useState(false);
	const [body, setBody] = useState("");
	const [posting, setPosting] = useState(false);
	const textarea = useRef<HTMLTextAreaElement>(null);
	// The box opens on a click, so the cursor goes straight into it.
	useEffect(() => {
		if (boxOpen) textarea.current?.focus();
	}, [boxOpen]);
	const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(
		null,
	);

	useEffect(() => {
		if (!armed) return;
		const timer = setTimeout(() => setArmed(null), ARM_MS);
		return () => clearTimeout(timer);
	}, [armed]);

	const post = async (event: ReviewEvent) => {
		setArmed(null);
		setPosting(true);
		setMessage(null);
		try {
			const res = await fetch(
				`/api/pr/${data.pr.repo}/${data.pr.number}/review`,
				{
					method: "POST",
					headers: {
						"content-type": "application/json",
						"x-mission-control-token": data.csrfToken,
					},
					body: JSON.stringify({
						event,
						body: event === "APPROVE" ? "" : body,
						commitId: data.headSha,
					}),
				},
			);
			const json = await res.json().catch(() => ({}));
			if (!res.ok) throw new Error(json.error ?? `HTTP ${res.status}`);
			setMessage({ ok: true, text: `${EVENT_TEXT[event][0]} posted` });
			setBody("");
			setBoxOpen(false);
			await reload();
		} catch (error) {
			setMessage({ ok: false, text: (error as Error).message });
		} finally {
			setPosting(false);
		}
	};

	const press = (event: ReviewEvent) => {
		if (posting) return;
		if (event !== "APPROVE" && !body.trim()) {
			setMessage({ ok: false, text: "Write a comment first" });
			return;
		}
		if (armed === event) post(event);
		else {
			setMessage(null);
			setArmed(event);
		}
	};

	// Escape works in the comment box too; the other keys do not.
	useEffect(() => {
		const onKey = (event: KeyboardEvent) => {
			if (event.key === "Escape") {
				if (armed) setArmed(null);
				else if (boxOpen) setBoxOpen(false);
				else return;
			} else if (
				event.metaKey ||
				event.ctrlKey ||
				event.altKey ||
				isTyping(event)
			)
				return;
			else if (event.key === "a") press("APPROVE");
			else if (event.key === "Enter" && armed) press(armed);
			else return;
			event.preventDefault();
		};
		window.addEventListener("keydown", onKey);
		return () => window.removeEventListener("keydown", onKey);
	});

	const button = (event: ReviewEvent, cls: string) => (
		<button
			type="button"
			class={armed === event ? `${cls} armed` : cls}
			disabled={posting}
			onClick={() => press(event)}
		>
			{armed === event
				? `${EVENT_TEXT[event][1]} as ${data.viewer}`
				: EVENT_TEXT[event][0]}
		</button>
	);

	return (
		<span class="verdict">
			{message && (
				<span class={message.ok ? "posted" : "refused"}>{message.text}</span>
			)}
			<button
				type="button"
				class="link"
				onClick={() => setBoxOpen(!boxOpen)}
				disabled={posting}
			>
				Comment…
			</button>
			{button("APPROVE", "approve")}
			{boxOpen && (
				<div class="comment-box">
					<textarea
						rows={5}
						placeholder="Write a comment"
						value={body}
						ref={textarea}
						onInput={(e) => setBody((e.target as HTMLTextAreaElement).value)}
					/>
					<div class="row">
						{button("REQUEST_CHANGES", "changes")}
						{button("COMMENT", "comment")}
					</div>
				</div>
			)}
		</span>
	);
}

// The description as GitHub renders it, cut to a few lines until opened.
// GitHub sanitizes the HTML, as it does on its own page.
// The description as GitHub renders it, in full. It sits at the top of the
// diff's scroll area, so it scrolls away as on GitHub. GitHub sanitizes the
// HTML, as it does on its own page.
function Description({ html }: { html: string }) {
	const box = useRef<HTMLDivElement>(null);
	useEffect(() => {
		for (const link of box.current?.querySelectorAll("a[href]") ?? []) {
			link.setAttribute("target", "_blank");
			link.setAttribute("rel", "noopener");
		}
	}, [html]);
	if (!html.trim()) return <p class="description muted">No description.</p>;
	return (
		<div
			class="description markdown-body"
			ref={box}
			// GitHub sanitized this HTML when it rendered the PR body.
			dangerouslySetInnerHTML={{ __html: html }}
		/>
	);
}

function el(tag: string, cls: string, text: string) {
	const node = document.createElement(tag);
	node.className = cls;
	node.textContent = text;
	return node;
}

// The tree's statuses for GitHub's file statuses, other than modified.
const TREE_STATUS: Record<string, GitStatus> = {
	added: "added",
	removed: "deleted",
	renamed: "renamed",
	copied: "added",
};

function Diff({
	files: changed,
	prUrl,
	header,
}: {
	files: PRFile[];
	prUrl: string;
	header: ComponentChildren;
}) {
	// The viewer measures this element and scrolls it with the files.
	const headerHost = useMemo(() => document.createElement("div"), []);
	const treeHost = useRef<HTMLElement>(null);
	const pick = useRef((_path: string) => {});

	// The file tree. A click on a file jumps to it in the diff.
	const tree = useMemo(
		() =>
			new FileTree({
				paths: changed.map((f) => f.path),
				flattenEmptyDirectories: true,
				initialExpansion: "open",
				density: "compact",
				// Every file in a PR changed, so only the other statuses get a
				// letter.
				gitStatus: changed.flatMap((f) =>
					TREE_STATUS[f.status]
						? [{ path: f.path, status: TREE_STATUS[f.status] }]
						: [],
				),
				// A folder's dot only repeats what its files show.
				unsafeCSS:
					'[data-item-section="git"] [data-icon-name="file-tree-icon-dot"]{display:none}',
				onSelectionChange: (paths) => {
					const path = paths.at(-1);
					if (path) pick.current(path);
				},
			}),
		[changed],
	);

	// The diff lists the files in the tree's order, so j and k follow it.
	const files = useMemo(() => {
		const byPath = new Map(changed.map((f) => [f.path, f]));
		const order = tree
			.getVisibleRows(0, tree.getVisibleCount())
			.filter((row) => row.kind === "file")
			.map((row) => byPath.get(row.path))
			.filter((f): f is PRFile => !!f);
		const seen = new Set(order.map((f) => f.path));
		return [...order, ...changed.filter((f) => !seen.has(f.path))];
	}, [tree]);

	useEffect(() => {
		if (!treeHost.current) return;
		tree.render({ containerWrapper: treeHost.current });
		return () => tree.cleanUp();
	}, [tree]);
	const root = useRef<HTMLDivElement>(null);
	const viewer = useRef<CodeView | null>(null);
	const [collapsed, setCollapsed] = useState(
		() => new Set(files.filter((f) => f.generated).map((f) => f.path)),
	);
	const [current, setCurrent] = useState(0);
	// A jump owns the current file until its scroll settles.
	const jumpedAt = useRef(0);
	const byPath = useMemo(() => new Map(files.map((f) => [f.path, f])), [files]);
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
			overflow: "wrap",
			stickyHeaders: true,
			layout: { paddingTop: 0, paddingBottom: 64, gap: 12 },
			// The library mixes a little of each diff colour into the code
			// background. A mix of 0% shows the theme's diff colours as they are.
			unsafeCSS:
				"[data-line],[data-no-newline],[data-gutter-buffer],[data-column-number]{--mix-light:0%;--mix-dark:0%}",
			renderCodeViewHeader: () => headerHost,
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
				if (newFileText(file) !== null)
					box.append(el("span", "added", `new file, ${file.additions} lines`));
				if (file.generated) box.append(el("span", "gen", "generated"));
				// GitHub sends no patch for a pure rename, a binary file or a
				// diff too large to send. Only the last has lines to count.
				if (!file.patch && file.status === "renamed" && !file.additions)
					box.append(el("span", "muted", "Renamed, no changes"));
				else if (!file.patch && file.additions + file.deletions === 0)
					box.append(el("span", "muted", "Binary file"));
				else if (!file.patch) {
					const link = el("a", "", "Too large to show, open on GitHub");
					(link as HTMLAnchorElement).href = `${prUrl}/files`;
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
				files.forEach((f, i) => {
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
	}, [files]);

	// Items carry the collapsed state; a changed state bumps the version.
	const versions = useRef(new Map<string, number>());
	const diffs = useMemo(
		() =>
			new Map(
				files
					.filter((f) => !newFileText(f))
					.map((f) => [f.path, toFileDiff(f)]),
			),
		[files],
	);
	useEffect(() => {
		const view = viewer.current;
		if (!view) return;
		const items = files.map((f): CodeViewItem<undefined> => {
			const isCollapsed = collapsed.has(f.path) || !f.patch;
			const known = view.getItem(f.path);
			let version = versions.current.get(f.path) ?? 0;
			if (known && known.collapsed !== isCollapsed) version++;
			versions.current.set(f.path, version);
			// A new file reads as a file, as in codediff.nvim, not as a wall
			// of added lines.
			const text = newFileText(f);
			if (text !== null)
				return {
					id: f.path,
					type: "file",
					file: { name: f.path, contents: text },
					collapsed: isCollapsed,
					version,
				};
			return {
				id: f.path,
				type: "diff",
				fileDiff: diffs.get(f.path) as FileDiffMetadata,
				collapsed: isCollapsed,
				version,
			};
		});
		view.setItems(items);
	}, [files, collapsed]);

	const jump = (index: number) => {
		const file = files[index];
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

	pick.current = (path: string) => {
		const index = files.findIndex((f) => f.path === path);
		if (index >= 0 && index !== current) jump(index);
	};

	// The tree selects the current file and keeps it in view.
	useEffect(() => {
		const path = files[current]?.path;
		if (!path) return;
		for (const other of tree.getSelectedPaths())
			if (other !== path) tree.getItem(other)?.deselect();
		const item = tree.getItem(path);
		if (item && !item.isSelected()) item.select();
		tree.scrollToPath(path, { focus: false, offset: "nearest" });
	}, [current, tree]);

	useEffect(() => {
		const onKey = (event: KeyboardEvent) => {
			if (event.metaKey || event.ctrlKey || event.altKey || isTyping(event))
				return;
			if (event.key === "j") jump(Math.min(current + 1, files.length - 1));
			else if (event.key === "k") jump(Math.max(current - 1, 0));
			else if (event.key === "x") {
				const file = files[current];
				if (file) toggle(file.path);
			} else if (event.key === "g") goBack();
			else return;
			event.preventDefault();
		};
		window.addEventListener("keydown", onKey);
		return () => window.removeEventListener("keydown", onKey);
	}, [current, files]);

	return (
		<div class="review-body">
			<nav class="file-list" ref={treeHost} />
			<div class="diff-view" ref={root} />
			{createPortal(header, headerHost)}
		</div>
	);
}
