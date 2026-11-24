// The review page for one pull request: an overview strip, the description
// and the diff, with a file list to jump between files.
import {
	CodeView,
	type CodeViewItem,
	type CodeViewOptions,
	type FileDiffMetadata,
	parseDiffFromFile,
	processFile,
} from "@pierre/diffs";
import {
	FileTree,
	type FileTreeSortComparator,
	type GitStatus,
} from "@pierre/trees";
import type { ComponentChildren } from "preact";
import { createPortal } from "preact/compat";
import { useEffect, useMemo, useRef, useState } from "preact/hooks";
import type { ApiModule, ApiSide, ApiView } from "./api/languages.ts";
import { fileTotals, type PR, type PRFile, type ReviewEvent } from "./model.ts";
import {
	ago,
	botClass,
	botTitle,
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
	// The review bot's name, or "" when none is configured.
	reviewBot: string;
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

// One item of the review: a changed file with its line diff, or a module
// with the diff of what it exports.
type Entry = {
	// The path in the file tree, and the item's id in the viewer.
	id: string;
	// GitHub's status of the file. A module has added, removed, modified, or
	// unchanged when its API is the same at both commits.
	status: string;
	generated: boolean;
	file?: PRFile;
	module?: ApiModule;
};

// Where to scroll once the diff shows: an item, or a line in it.
type Focus = { id: string; line?: number; side?: "deletions" | "additions" };

const apiText = (side: ApiSide | null) => (side ? side.lines.join("\n") : "");

function moduleStatus(module: ApiModule) {
	if (!module.base) return "added";
	if (!module.head) return "removed";
	return apiText(module.base) === apiText(module.head)
		? "unchanged"
		: "modified";
}

// The review's items. With an API view, each module stands in for the
// changed files it covers, and the other files keep their line diffs.
function reviewEntries(files: PRFile[], view: ApiView | null): Entry[] {
	const byPath = new Map(files.map((f) => [f.path, f]));
	const covered = new Set(view?.modules.flatMap((m) => m.files));
	return [
		...(view?.modules ?? []).map((module) => ({
			id: module.id,
			status: moduleStatus(module),
			generated: module.files.every((path) => byPath.get(path)?.generated),
			module,
		})),
		...files
			.filter((f) => !covered.has(f.path))
			.map((f) => ({
				id: f.path,
				status: f.status,
				generated: f.generated,
				file: f,
			})),
	];
}

// The text of an entry that reads as a file, without diff markup: a new
// file, a new module, or a module whose API did not change.
function plainText(entry: Entry): string | null {
	if (entry.file) return newFileText(entry.file);
	const head = entry.module?.head;
	return head && entry.status !== "modified" ? apiText(head) : null;
}

function entryDiff(entry: Entry): FileDiffMetadata {
	if (entry.file) return toFileDiff(entry.file);
	const { id, language, base, head } = entry.module as ApiModule;
	const side = (lines: ApiSide | null) =>
		lines && { name: id, lang: language, contents: apiText(lines) };
	return parseDiffFromFile(side(base), side(head));
}

// An entry with nothing to expand: a deleted file or module, or a file
// GitHub sent no patch for.
function staysShut(entry: Entry) {
	return entry.status === "removed" || (!!entry.file && !entry.file.patch);
}

// Whether a file's line diff shows a line. GitHub's patch holds the changed
// lines and three lines around them.
function showsLine(file: PRFile, side: "base" | "head", line: number) {
	if (file.status === "removed" || !file.patch) return false;
	if (newFileText(file) !== null) return side === "head";
	return toFileDiff(file).hunks.some((hunk) =>
		side === "head"
			? line >= hunk.additionStart &&
				line < hunk.additionStart + hunk.additionCount
			: line >= hunk.deletionStart &&
				line < hunk.deletionStart + hunk.deletionCount,
	);
}

function saved(key: string) {
	try {
		return localStorage.getItem(key);
	} catch {
		return null;
	}
}

function save(key: string, value: string) {
	try {
		localStorage.setItem(key, value);
	} catch {}
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

type Mode = "diff" | "api";

type ApiState = {
	// The newest view that arrived, and the settings it was made with.
	view: ApiView | null;
	settings: string;
	loading: boolean;
	error: string | null;
};

export function Review({ repo, number }: { repo: string; number: number }) {
	const [data, setData] = useState<Detail | null>(null);
	const [error, setError] = useState<string | null>(null);
	const [now, setNow] = useState(Date.now());
	// The reviewer's choices hold for every pull request.
	const [mode, setMode] = useState<Mode>(() =>
		saved("mc-view") === "api" ? "api" : "diff",
	);
	const [comments, setComments] = useState(
		() => saved("mc-api-comments") === "1",
	);
	// Whether the API view shows unexported declarations.
	const [unexported, setUnexported] = useState(
		() => saved("mc-api-private") === "1",
	);
	const [api, setApi] = useState<ApiState>({
		view: null,
		settings: "",
		loading: true,
		error: null,
	});
	const [focus, setFocus] = useState<Focus | null>(null);
	// The item at the top of the diff, or null above the first one.
	const currentId = useRef<string | null>(null);

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

	// The API view loads beside the pull request, so the switch finds it
	// ready. It loads again when a setting changes, and when the pull request
	// got new commits.
	const settings = [comments && "comments", unexported && "private"]
		.filter(Boolean)
		.join("&");
	const apiKey = `${repo}#${number}:${settings}`;
	const loadedKey = useRef("");
	const behind = !!data && !!api.view && api.view.headSha !== data.headSha;
	useEffect(() => {
		if (loadedKey.current === apiKey && !behind) return;
		loadedKey.current = apiKey;
		let stale = false;
		setApi((old) => ({ ...old, loading: true, error: null }));
		fetch(`/api/pr/${repo}/${number}/api?${settings}`)
			.then(async (res) => {
				const json = (await res.json()) as ApiView & { error?: string };
				if (!res.ok) throw new Error(json.error ?? `HTTP ${res.status}`);
				if (stale) return;
				// The new view replaces the items, so the place is kept.
				setFocus(currentId.current ? { id: currentId.current } : null);
				setApi({ view: json, settings, loading: false, error: null });
			})
			.catch((e: Error) => {
				if (!stale)
					setApi((old) => ({ ...old, loading: false, error: e.message }));
			});
		return () => {
			stale = true;
		};
	}, [apiKey, behind]);

	useEffect(() => {
		document.title = data
			? `${data.pr.title} · ${repo}#${number}`
			: `${repo}#${number}`;
	}, [data]);

	const view = api.view;
	const modules = view?.modules ?? [];
	// Without a module there is nothing the API view could show.
	const shown: Mode | "wait" =
		mode === "diff" || (!api.loading && modules.length === 0)
			? "diff"
			: modules.length > 0
				? "api"
				: "wait";
	const entries = useMemo(
		() => reviewEntries(data?.files ?? [], shown === "api" ? view : null),
		[data?.files, view, shown],
	);

	// The other view opens at the item that was being read.
	const show = (next: Mode) => {
		const id = currentId.current;
		const module =
			next === "api"
				? modules.find((m) => id && m.files.includes(id))
				: modules.find((m) => m.id === id);
		const target = next === "api" ? module?.id : module?.files[0];
		setFocus(id ? { id: target ?? id } : null);
		setMode(next);
		save("mc-view", next);
	};
	const toggleComments = () => {
		save("mc-api-comments", comments ? "0" : "1");
		setComments(!comments);
	};
	const toggleUnexported = () => {
		save("mc-api-private", unexported ? "0" : "1");
		setUnexported(!unexported);
	};

	// From a line of API text to its source: in the line diff when the diff
	// shows that line, else on GitHub.
	const openSource = (module: ApiModule, at: "base" | "head", line: number) => {
		const side = module[at];
		const target = side?.targets[line - 1];
		if (!data || !view || !side || !target || target[0] < 0) return;
		const path = side.sources[target[0]];
		const file = data.files.find(
			(f) => (at === "head" ? f.path : (f.prevPath ?? f.path)) === path,
		);
		if (file && showsLine(file, at, target[1])) {
			setFocus({
				id: file.path,
				line: target[1],
				side: at === "head" ? "additions" : "deletions",
			});
			// The saved choice stays: this is a visit to the line diff.
			setMode("diff");
			return;
		}
		const sha = at === "head" ? view.headSha : view.baseSha;
		const repoUrl = data.pr.url.replace(/\/pull\/\d+$/, "");
		window.open(
			`${repoUrl}/blob/${sha}/${path.split("/").map(encodeURIComponent).join("/")}#L${target[1]}`,
			"_blank",
			"noopener",
		);
	};

	// The keys are codediff.nvim's: a and s switch the view, C shows comments
	// and P shows unexported declarations.
	useEffect(() => {
		const onKey = (event: KeyboardEvent) => {
			if (event.metaKey || event.ctrlKey || event.altKey || isTyping(event))
				return;
			if ((event.key === "a" || event.key === "s") && modules.length > 0)
				show(mode === "api" ? "diff" : "api");
			else if (event.key === "C" && shown === "api") toggleComments();
			else if (event.key === "P" && shown === "api") toggleUnexported();
			else return;
			event.preventDefault();
		};
		window.addEventListener("keydown", onKey);
		return () => window.removeEventListener("keydown", onKey);
	});

	const changed = modules.filter((m) => moduleStatus(m) !== "unchanged").length;
	const switcher = (
		<span class="view-switch">
			{api.error && (
				<span class="refused" title={api.error}>
					No API view
				</span>
			)}
			{view?.errors.map((message) => (
				<span class="refused" title={message}>
					{message.split(":")[0]} API failed
				</span>
			))}
			{shown === "api" && (
				<label title="Show comments in the API view (C)">
					<input type="checkbox" checked={comments} onChange={toggleComments} />
					Comments
				</label>
			)}
			{shown === "api" && (
				<label title="Show unexported declarations in the API view (P)">
					<input
						type="checkbox"
						checked={unexported}
						onChange={toggleUnexported}
					/>
					Unexported
				</label>
			)}
			<span class="segments">
				<button
					type="button"
					class={shown === "diff" ? "on" : ""}
					aria-pressed={shown === "diff"}
					onClick={() => show("diff")}
					title="The line diff (a)"
				>
					Diff
				</button>
				<button
					type="button"
					class={shown === "diff" ? "" : "on"}
					aria-pressed={shown !== "diff"}
					disabled={!api.loading && modules.length === 0}
					onClick={() => show("api")}
					title={
						api.loading || modules.length > 0
							? "What each changed module exports, without bodies (a)"
							: "No changed module has an API view"
					}
				>
					API
					{api.loading ? (
						<i class="spinner" />
					) : (
						modules.length > 0 && <span class="count">{changed}</span>
					)}
				</button>
			</span>
		</span>
	);

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
					<Strip data={data} now={now} reload={load} tools={switcher} />
					{shown === "wait" ? (
						<p class="muted">Reading the API of the changed modules…</p>
					) : (
						<Diff
							// A view of its own for each set of items.
							key={shown === "api" ? `api:${api.settings}` : "diff"}
							entries={entries}
							prUrl={data.pr.url}
							header={<Description html={data.bodyHTML} />}
							focus={focus}
							onCurrent={(id) => {
								currentId.current = id;
							}}
							openSource={openSource}
						/>
					)}
				</>
			)}
		</div>
	);
}

function Strip({
	data,
	now,
	reload,
	tools,
}: {
	data: Detail;
	now: number;
	reload: () => Promise<void>;
	tools: ComponentChildren;
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
				{pr.botReview && (
					<span
						class={`review-bot ${botClass(pr.botReview)}`}
						title={botTitle(data.reviewBot, pr.botReview)}
					>
						{data.reviewBot} #{pr.botReview.n}
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
					{tools}
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
// seconds, the second posts. Enter confirms what is armed and Esc disarms
// it.
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

// The tree's order with an API view: folders, then modules, then the files
// that keep their line diffs, each by name.
function modulesFirst(modules: Set<string>): FileTreeSortComparator {
	return (left, right) => {
		const shared = Math.min(left.segments.length, right.segments.length);
		for (let i = 0; i < shared; i++) {
			if (left.segments[i] === right.segments[i]) continue;
			const leftFolder = left.isDirectory || i < left.segments.length - 1;
			const rightFolder = right.isDirectory || i < right.segments.length - 1;
			if (leftFolder !== rightFolder) return leftFolder ? -1 : 1;
			if (!leftFolder && modules.has(left.path) !== modules.has(right.path))
				return modules.has(left.path) ? -1 : 1;
			return left.segments[i].localeCompare(right.segments[i]);
		}
		return left.segments.length - right.segments.length;
	};
}

// A module's letter in the tree. One whose API did not change gets none.
const MODULE_STATUS: Record<string, GitStatus> = {
	added: "added",
	removed: "deleted",
	modified: "modified",
};

function Diff({
	entries: all,
	prUrl,
	header,
	focus,
	onCurrent,
	openSource,
}: {
	entries: Entry[];
	prUrl: string;
	header: ComponentChildren;
	// Where to open, read once when the view is made.
	focus: Focus | null;
	onCurrent: (id: string | null) => void;
	openSource: (module: ApiModule, at: "base" | "head", line: number) => void;
}) {
	// The viewer measures this element and scrolls it with the files.
	const headerHost = useMemo(() => document.createElement("div"), []);
	const treeHost = useRef<HTMLElement>(null);
	const pick = useRef((_path: string) => {});

	// The file tree, without generated files: they start collapsed and
	// nobody reads them. A click on a file jumps to it in the diff.
	const handwritten = useMemo(() => all.filter((e) => !e.generated), [all]);
	const tree = useMemo(
		() =>
			new FileTree({
				paths: handwritten.map((e) => e.id),
				flattenEmptyDirectories: true,
				initialExpansion: "open",
				density: "compact",
				sort: handwritten.some((e) => e.module)
					? modulesFirst(
							new Set(handwritten.flatMap((e) => (e.module ? [e.id] : []))),
						)
					: "default",
				// Every file in a PR changed, so only the other statuses get a
				// letter. A module gets one when its API changed.
				gitStatus: handwritten.flatMap((e) => {
					const status = e.module
						? MODULE_STATUS[e.status]
						: TREE_STATUS[e.status];
					return status ? [{ path: e.id, status }] : [];
				}),
				// A folder's dot only repeats what its files show.
				unsafeCSS:
					'[data-item-section="git"] [data-icon-name="file-tree-icon-dot"]{display:none}',
				onSelectionChange: (paths) => {
					const path = paths.at(-1);
					if (path) pick.current(path);
				},
			}),
		[handwritten],
	);

	// The diff lists the files in the tree's order, so j and k follow it.
	// Generated files come last.
	const entries = useMemo(() => {
		const byId = new Map(all.map((e) => [e.id, e]));
		const order = tree
			.getVisibleRows(0, tree.getVisibleCount())
			.filter((row) => row.kind === "file")
			.map((row) => byId.get(row.path))
			.filter((e): e is Entry => !!e);
		const seen = new Set(order.map((e) => e.id));
		return [...order, ...all.filter((e) => !seen.has(e.id))];
	}, [tree]);

	useEffect(() => {
		if (!treeHost.current) return;
		tree.render({ containerWrapper: treeHost.current });
		return () => tree.cleanUp();
	}, [tree]);
	const root = useRef<HTMLDivElement>(null);
	const viewer = useRef<CodeView | null>(null);
	// Generated files start collapsed, and so does a module whose API did not
	// change. The item to open at a line starts open.
	const [collapsed, setCollapsed] = useState(
		() =>
			new Set(
				entries
					.filter((e) => e.generated || e.status === "unchanged")
					.filter((e) => !(focus?.line && focus.id === e.id))
					.map((e) => e.id),
			),
	);
	const [current, setCurrent] = useState(() =>
		Math.max(
			0,
			entries.findIndex((e) => e.id === focus?.id),
		),
	);
	// A jump owns the current file until its scroll settles.
	const jumpedAt = useRef(0);
	const byId = useMemo(() => new Map(entries.map((e) => [e.id, e])), [entries]);
	const toggleRef = useRef((_path: string) => {});
	const openSourceRef = useRef(openSource);
	openSourceRef.current = openSource;
	const onCurrentRef = useRef(onCurrent);
	onCurrentRef.current = onCurrent;
	const hasModules = useMemo(() => entries.some((e) => e.module), [entries]);

	const toggle = (path: string) =>
		setCollapsed((prev) => {
			const next = new Set(prev);
			if (next.has(path)) next.delete(path);
			else next.add(path);
			return next;
		});
	toggleRef.current = toggle;

	// One viewer for the page. Header pieces read the entry by the item's id.
	useEffect(() => {
		if (!root.current) return;
		// Header callbacks get the item as context, file or diff alike.
		type Context = { item: { id: string; collapsed?: boolean } };
		const options = (): CodeViewOptions<undefined, undefined> => ({
			theme: { dark: "monokai", light: "github-light" },
			themeType: isDark() ? "dark" : "light",
			diffStyle: "unified",
			// An API diff holds the whole text, so the lines between its hunks
			// can open. GitHub's patches hold the hunks only.
			hunkSeparators: hasModules ? "line-info" : "metadata",
			overflow: "wrap",
			stickyHeaders: true,
			layout: { paddingTop: 0, paddingBottom: 64, gap: 12 },
			// The library mixes a little of each diff colour into the code
			// background. A mix of 0% shows the theme's diff colours as they are.
			// A line number of API text is a link to its source.
			unsafeCSS: `[data-line],[data-no-newline],[data-gutter-buffer],[data-column-number]{--mix-light:0%;--mix-dark:0%}${hasModules ? "[data-column-number]{cursor:pointer}" : ""}`,
			renderCodeViewHeader: () => headerHost,
			renderHeaderPrefix: (_diff: unknown, context: Context) => {
				const entry = byId.get(context.item.id);
				// A deleted file has nothing to expand.
				if (!entry || staysShut(entry)) return null;
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
				const entry = byId.get(context.item.id);
				if (!entry) return null;
				const box = el("span", "file-meta", "");
				if (entry.module) {
					const lines = entry.module.head?.lines.length ?? 0;
					if (entry.status === "added")
						box.append(el("span", "added", `new module, ${lines} lines`));
					if (entry.status === "removed")
						box.append(el("span", "removed", "deleted module"));
					if (entry.status === "unchanged")
						box.append(el("span", "muted", "No API change"));
					const tag = el("span", "gen", "API");
					tag.title = `What ${entry.module.files.join(", ")} ${entry.module.files.length === 1 ? "is" : "are"} part of. A click on a line number opens the source.`;
					box.append(tag);
					return box;
				}
				const file = entry.file as PRFile;
				if (file.status === "removed")
					box.append(el("span", "removed", `deleted, ${file.deletions} lines`));
				if (newFileText(file) !== null)
					box.append(el("span", "added", `new file, ${file.additions} lines`));
				if (file.generated) box.append(el("span", "gen", "generated"));
				// GitHub sends no patch for a pure rename, a binary file or a
				// diff too large to send. Only the last has lines to count.
				if (file.status === "removed") {
					/* The deleted line count says it all. */
				} else if (!file.patch && file.status === "renamed" && !file.additions)
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
			// A line number of API text opens the line's source.
			onLineNumberClick: (
				line: { lineNumber: number; annotationSide?: string },
				context: Context,
			) => {
				const module = byId.get(context.item.id)?.module;
				if (module)
					openSourceRef.current(
						module,
						line.annotationSide === "deletions" || !module.head
							? "base"
							: "head",
						line.lineNumber,
					);
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
				let above = true;
				entries.forEach((e, i) => {
					const at = view.getTopForItem(e.id);
					if (at === undefined || at > top + 4) return;
					index = i;
					above = false;
				});
				setCurrent(index);
				onCurrentRef.current(above ? null : (entries[index]?.id ?? null));
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
	}, [entries]);

	// Items carry the collapsed state; a changed state bumps the version.
	const versions = useRef(new Map<string, number>());
	const diffs = useMemo(
		() =>
			new Map(
				entries
					.filter((e) => plainText(e) === null)
					.map((e) => [e.id, entryDiff(e)]),
			),
		[entries],
	);
	const focused = useRef(false);
	useEffect(() => {
		const view = viewer.current;
		if (!view) return;
		const items = entries.map((e): CodeViewItem<undefined> => {
			// A deleted file shows as its header line only.
			const isCollapsed = collapsed.has(e.id) || staysShut(e);
			const known = view.getItem(e.id);
			let version = versions.current.get(e.id) ?? 0;
			if (known && known.collapsed !== isCollapsed) version++;
			versions.current.set(e.id, version);
			// A new file reads as a file, as in codediff.nvim, not as a wall
			// of added lines.
			const text = plainText(e);
			if (text !== null)
				return {
					id: e.id,
					type: "file",
					file: { name: e.id, contents: text, lang: e.module?.language },
					collapsed: isCollapsed,
					version,
				};
			return {
				id: e.id,
				type: "diff",
				fileDiff: diffs.get(e.id) as FileDiffMetadata,
				collapsed: isCollapsed,
				version,
			};
		});
		view.setItems(items);
		if (focused.current || !focus || !byId.has(focus.id)) return;
		focused.current = true;
		jumpedAt.current = Date.now();
		onCurrentRef.current(focus.id);
		if (focus.line === undefined)
			view.scrollTo({
				type: "item",
				id: focus.id,
				align: "start",
				behavior: "instant",
			});
		else {
			// A file shown without diff markup has one side only.
			const side =
				items.find((item) => item.id === focus.id)?.type === "diff"
					? focus.side
					: undefined;
			view.scrollTo({
				type: "line",
				id: focus.id,
				lineNumber: focus.line,
				side,
				align: "center",
				behavior: "instant",
			});
			view.setSelectedLines({
				id: focus.id,
				range: { start: focus.line, end: focus.line, side },
			});
		}
	}, [entries, collapsed]);

	const jump = (index: number) => {
		const entry = entries[index];
		if (!entry) return;
		setCurrent(index);
		onCurrentRef.current(entry.id);
		jumpedAt.current = Date.now();
		viewer.current?.scrollTo({
			type: "item",
			id: entry.id,
			align: "start",
			behavior: "instant",
		});
	};

	pick.current = (path: string) => {
		const index = entries.findIndex((e) => e.id === path);
		if (index >= 0 && index !== current) jump(index);
	};

	// The tree selects the current file and keeps it in view.
	useEffect(() => {
		const path = entries[current]?.id;
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
			if (event.key === "j") jump(Math.min(current + 1, entries.length - 1));
			else if (event.key === "k") jump(Math.max(current - 1, 0));
			else if (event.key === "x") {
				const entry = entries[current];
				if (entry) toggle(entry.id);
			} else if (event.key === "g") goBack();
			else return;
			event.preventDefault();
		};
		window.addEventListener("keydown", onKey);
		return () => window.removeEventListener("keydown", onKey);
	}, [current, entries]);

	return (
		<div class={hasModules ? "review-body api-view" : "review-body"}>
			<nav class="file-list" ref={treeHost} />
			<div class="diff-view" ref={root} />
			{createPortal(header, headerHost)}
		</div>
	);
}
