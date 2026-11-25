import { render } from "preact";
import { useEffect, useMemo, useRef, useState } from "preact/hooks";
import { BUCKETS, type Bucket, OLD_DAYS, type PR, WARN_DAYS } from "./model.ts";
import { Review } from "./review.tsx";
import {
	ago,
	botClass,
	botTitle,
	CI_TEXT,
	jiraHref,
	lines,
	REVIEW_MARK,
	ThemeButton,
} from "./ui.tsx";

type Data = {
	fetchedAt: string | null;
	members: string[];
	prs: PR[];
	error: string | null;
	readyLabel: string;
	jiraBase: string;
	// The review bot's name, or "" when none is configured.
	reviewBot: string;
};

const POLL_MS = 2 * 60 * 1000;

// Filters live in the URL, so a filtered view can be bookmarked.
type Filters = {
	author: string[];
	label: string[];
	repo: string;
	ci: string;
	review: string;
	age: string;
	bot: string;
	// "" shows open pull requests, "merged" the recently merged ones.
	state: string;
	q: string;
	drafts: boolean;
	side: boolean;
};

// A visit with no query gets the default view: two columns, PRs with the
// review label, opened in the last 7 days, that nobody has reviewed yet.
// The label name comes with the data, so it is set once the first load
// arrives.
let wantReadyLabel = false;

function readFilters(): Filters {
	const p = new URLSearchParams(location.search);
	if (!location.search) {
		wantReadyLabel = true;
		p.set("review", "none");
		p.set("age", "-7");
		p.set("layout", "side");
	}
	const list = (key: string) => (p.get(key) ?? "").split(",").filter(Boolean);
	return {
		author: list("author"),
		label: list("label"),
		repo: p.get("repo") ?? "",
		ci: p.get("ci") ?? "",
		review: p.get("review") ?? "",
		age: p.get("age") ?? "",
		bot: p.get("bot") ?? "",
		state: p.get("state") ?? "",
		q: p.get("q") ?? "",
		drafts: p.get("drafts") === "1",
		side: p.get("layout") === "side",
	};
}

function writeFilters(f: Filters) {
	const p = new URLSearchParams();
	if (f.author.length) p.set("author", f.author.join(","));
	if (f.label.length) p.set("label", f.label.join(","));
	for (const key of [
		"repo",
		"ci",
		"review",
		"age",
		"bot",
		"state",
		"q",
	] as const)
		if (f[key]) p.set(key, f[key]);
	if (f.drafts) p.set("drafts", "1");
	// Layout is always written, so a view without filters keeps a query and
	// is not replaced by the default view on reload.
	p.set("layout", f.side ? "side" : "stack");
	history.replaceState(null, "", `?${p}`);
}

function matches(pr: PR, f: Filters): boolean {
	if ((f.state === "merged") !== (pr.mergedAt !== null)) return false;
	if (!f.drafts && pr.draft) return false;
	if (f.author.length && !f.author.includes(pr.author)) return false;
	if (
		f.label.length &&
		!f.label.every((l) => pr.labels.some((x) => x.name === l))
	)
		return false;
	if (f.repo && pr.repo !== f.repo) return false;
	if (f.ci && pr.ci !== f.ci) return false;
	if (f.review && pr.reviewed !== f.review) return false;
	// An age of `-30` keeps PRs up to 30 days old; `14` keeps older ones.
	if (f.age.startsWith("-")) {
		if (pr.ageDays > -Number(f.age)) return false;
	} else if (f.age && pr.ageDays <= Number(f.age)) return false;
	const bot = pr.botReview;
	if (f.bot === "none" && bot) return false;
	if (f.bot === "todo" && bot && !bot.stale) return false;
	if (f.bot === "lgtm" && !(bot?.verdict === "lgtm" && !bot.stale))
		return false;
	if (f.q) {
		const text =
			`${pr.title} ${pr.jiraKey ?? ""} ${pr.repo}#${pr.number}`.toLowerCase();
		if (!text.includes(f.q.toLowerCase())) return false;
	}
	return true;
}

function App() {
	const [data, setData] = useState<Data | null>(null);
	const [loading, setLoading] = useState(false);
	const [filters, setFilters] = useState(readFilters);
	const [now, setNow] = useState(Date.now());
	// Merged pull requests load only while their filter is on.
	const [merged, setMerged] = useState<Data | null>(null);
	const wantMerged = useRef(false);
	wantMerged.current = filters.state === "merged";

	const loadMerged = async (fresh = false) => {
		const res = await fetch(`/api/prs?state=merged${fresh ? "&fresh=1" : ""}`);
		setMerged(await res.json());
	};

	const load = async (fresh = false) => {
		setLoading(true);
		try {
			const res = await fetch(fresh ? "/api/prs?fresh=1" : "/api/prs");
			setData(await res.json());
			if (wantMerged.current) await loadMerged(fresh);
		} catch (error) {
			setData((d) => (d ? { ...d, error: String(error) } : d));
		} finally {
			setLoading(false);
			setNow(Date.now());
		}
	};

	// Poll only while the tab is visible. On return, fetch at once when the
	// data is older than one poll.
	useEffect(() => {
		load();
		let lastLoad = Date.now();
		const tick = () => {
			setNow(Date.now());
			if (document.visibilityState !== "visible") return;
			if (Date.now() - lastLoad < POLL_MS) return;
			lastLoad = Date.now();
			load();
		};
		const timer = setInterval(tick, 15000);
		document.addEventListener("visibilitychange", tick);
		return () => {
			clearInterval(timer);
			document.removeEventListener("visibilitychange", tick);
		};
	}, []);

	useEffect(() => writeFilters(filters), [filters]);
	useEffect(() => {
		if (filters.state !== "merged" || merged) return;
		setLoading(true);
		loadMerged()
			.catch((error) =>
				setMerged((d) => (d ? { ...d, error: String(error) } : d)),
			)
			.finally(() => setLoading(false));
	}, [filters.state]);
	useEffect(() => {
		if (!data || !wantReadyLabel) return;
		wantReadyLabel = false;
		setFilters((f) => ({ ...f, label: [data.readyLabel] }));
	}, [data]);
	const set = (patch: Partial<Filters>) =>
		setFilters((f) => ({ ...f, ...patch }));

	const shown = filters.state === "merged" ? merged : data;
	const openPrs = data?.prs ?? [];
	const prs = filters.state === "merged" ? (merged?.prs ?? []) : openPrs;
	// Without a review bot, its filter is hidden, so a bookmarked one is
	// ignored.
	const reviewBot = data?.reviewBot ?? "";
	const visible = useMemo(() => {
		const active = reviewBot ? filters : { ...filters, bot: "" };
		return prs.filter((pr) => matches(pr, active));
	}, [prs, filters, reviewBot]);
	const repos = useMemo(
		() => [...new Set(prs.map((p) => p.repo))].sort(),
		[prs],
	);
	const labels = useMemo(() => {
		const seen = new Map<string, string>();
		for (const pr of prs) for (const l of pr.labels) seen.set(l.name, l.color);
		return [...seen].sort(([a], [b]) => a.localeCompare(b));
	}, [prs]);
	const members = (data?.members ?? []).filter(
		(m) => !filters.author.length || filters.author.includes(m),
	);
	const open = openPrs.filter((p) => !p.draft);
	const count = (bucket: Bucket) =>
		open.filter((p) => p.bucket === bucket).length;

	return (
		<>
			<header class="top">
				<h1>Mission control</h1>
				<div class="totals">
					<span>{open.length} open</span>
					<span class="b-waiting">{count("waiting")} waiting for review</span>
					<span>
						{open.filter((p) => p.ready).length} {data?.readyLabel}
					</span>
					<span class="b-failing">{count("failing")} CI failing</span>
					<span class="b-changes">{count("changes")} changes requested</span>
					<span class="b-approved">{count("approved")} approved</span>
				</div>
				<div class="status">
					{data?.fetchedAt && (
						<span>updated {ago(data.fetchedAt, now)} ago</span>
					)}
					<button type="button" onClick={() => load(true)} disabled={loading}>
						{loading ? "Refreshing…" : "Refresh"}
					</button>
					<button type="button" onClick={() => set({ side: !filters.side })}>
						{filters.side ? "Stack cards" : "Side by side"}
					</button>
					<a class="button" href={location.pathname}>
						Default view
					</a>
					<ThemeButton />
				</div>
			</header>
			{shown?.error && (
				<p class="error">
					GitHub fetch failed: {shown.error}
					{shown.fetchedAt ? " Showing the last good data." : ""}
				</p>
			)}
			<FilterBar
				filters={filters}
				set={set}
				members={data?.members ?? []}
				repos={repos}
				labels={labels}
				reviewBot={reviewBot}
			/>
			{!shown && <p class="muted">Loading pull requests…</p>}
			<main class={filters.side ? "cards side" : "cards"}>
				{members.map((m) => (
					<MemberCard
						key={m}
						login={m}
						prs={visible.filter((p) => p.author === m)}
						all={openPrs.filter((p) => p.author === m)}
						jiraBase={data?.jiraBase ?? ""}
						reviewBot={reviewBot}
						now={now}
					/>
				))}
			</main>
		</>
	);
}

function toggled(list: string[], item: string) {
	return list.includes(item) ? list.filter((x) => x !== item) : [...list, item];
}

function FilterBar(props: {
	filters: Filters;
	set: (patch: Partial<Filters>) => void;
	members: string[];
	repos: string[];
	labels: [string, string][];
	reviewBot: string;
}) {
	const { filters: f, set } = props;
	const bot = props.reviewBot;
	const select = (
		key: "repo" | "ci" | "review" | "age" | "bot" | "state",
		options: [string, string][],
	) => (
		<select
			value={f[key]}
			onChange={(e) => set({ [key]: (e.target as HTMLSelectElement).value })}
		>
			{options.map(([value, text]) => (
				<option value={value}>{text}</option>
			))}
		</select>
	);
	return (
		<section class="filters">
			<div class="row">
				<input
					type="search"
					placeholder="Search title, Jira key or repo"
					value={f.q}
					onInput={(e) => set({ q: (e.target as HTMLInputElement).value })}
				/>
				{select("state", [
					["", "Open"],
					["merged", "Merged, last 7 days"],
				])}
				{select("repo", [
					["", "All repos"],
					...props.repos.map((r): [string, string] => [r, r]),
				])}
				{select("ci", [
					["", "Any CI"],
					["failure", "CI failing"],
					["pending", "CI pending"],
					["success", "CI green"],
					["none", "No CI"],
				])}
				{select("review", [
					["", "Any review"],
					["none", "Not reviewed"],
					["commented", "Commented"],
					["changes", "Changes requested"],
					["approved", "Approved"],
				])}
				{select("age", [
					["", "Any age"],
					["-7", "Last 7 days"],
					["-30", "Last 30 days"],
					[String(WARN_DAYS), `Older than ${WARN_DAYS} days`],
					[String(OLD_DAYS), `Older than ${OLD_DAYS} days`],
				])}
				{bot &&
					select("bot", [
						["", `Any ${bot}`],
						["todo", `No ${bot}, or stale`],
						["none", `No ${bot}`],
						["lgtm", `${bot} LGTM on head`],
					])}
				<label class="check">
					<input
						type="checkbox"
						checked={f.drafts}
						onChange={(e) =>
							set({ drafts: (e.target as HTMLInputElement).checked })
						}
					/>
					Drafts
				</label>
			</div>
			<div class="row">
				{props.members.map((m) => (
					<button
						type="button"
						class={f.author.includes(m) ? "chip on" : "chip"}
						onClick={() => set({ author: toggled(f.author, m) })}
					>
						{m}
					</button>
				))}
				<span class="sep" />
				{props.labels.map(([name, color]) => (
					<button
						type="button"
						class={f.label.includes(name) ? "chip on" : "chip"}
						style={{ "--label": `#${color}` }}
						onClick={() => set({ label: toggled(f.label, name) })}
					>
						<i class="swatch" />
						{name}
					</button>
				))}
			</div>
		</section>
	);
}

function MemberCard(props: {
	login: string;
	prs: PR[];
	all: PR[];
	jiraBase: string;
	reviewBot: string;
	now: number;
}) {
	const { login, prs } = props;
	const open = props.all.filter((p) => !p.draft && !p.mergedAt);
	const summary = BUCKETS.filter((b) => b.id !== "draft" && b.id !== "merged")
		.map((b) => ({ ...b, n: open.filter((p) => p.bucket === b.id).length }))
		.filter((b) => b.n);
	return (
		<details class="card" open={prs.length > 0}>
			<summary>
				<img src={`https://github.com/${login}.png?size=48`} alt="" />
				<strong>{login}</strong>
				<span class="muted">{open.length} open</span>
				{summary.map((b) => (
					<span class={`pill b-${b.id}`}>
						{b.n} {b.title}
					</span>
				))}
			</summary>
			{BUCKETS.map((b) => {
				const rows = prs.filter((p) => p.bucket === b.id);
				// Merged pull requests list the newest merge first.
				if (b.id === "merged")
					rows.sort((x, y) =>
						(y.mergedAt ?? "").localeCompare(x.mergedAt ?? ""),
					);
				if (!rows.length) return null;
				return (
					<section class="bucket">
						<h3 class={`b-${b.id}`}>
							{b.title} <span class="muted">{rows.length}</span>
						</h3>
						{rows.map((pr) => (
							<Row
								pr={pr}
								jiraBase={props.jiraBase}
								reviewBot={props.reviewBot}
								now={props.now}
							/>
						))}
					</section>
				);
			})}
			{!prs.length && <p class="muted empty">No pull requests match.</p>}
		</details>
	);
}

function Row({
	pr,
	jiraBase,
	reviewBot,
	now,
}: {
	pr: PR;
	jiraBase: string;
	reviewBot: string;
	now: number;
}) {
	const [mark, markText] = REVIEW_MARK[pr.reviewed];
	const who = pr.reviewers
		.map((r) => `${r.login}: ${r.state.toLowerCase().replace("_", " ")}`)
		.join("\n");
	return (
		<div class="pr">
			<span class={`dot ci-${pr.ci}`} title={CI_TEXT[pr.ci]} />
			<span class="repo">{pr.repo}</span>
			<span class="title">
				<a href={`/pr/${pr.repo}/${pr.number}`}>
					{pr.title}
					<span class="muted"> #{pr.number}</span>
				</a>
				<a
					class="gh"
					href={pr.url}
					target="_blank"
					rel="noopener"
					title="Open on GitHub"
				>
					↗
				</a>
			</span>
			{!pr.jiraKey && <span class="jira" />}
			{pr.jiraKey &&
				(jiraBase ? (
					<a
						class="jira"
						href={jiraHref(jiraBase, pr.jiraKey)}
						target="_blank"
						rel="noopener"
					>
						{pr.jiraKey}
					</a>
				) : (
					<span class="jira">{pr.jiraKey}</span>
				))}
			<span class="size" title={`${pr.files} files changed`}>
				<span class="plus">+{lines(pr.additions)}</span>{" "}
				<span class="minus">−{lines(pr.deletions)}</span>
			</span>
			<span class="labels">
				{pr.labels.map((l) => (
					<span class="label" style={{ "--label": `#${l.color}` }}>
						<i class="swatch" />
						{l.name}
					</span>
				))}
			</span>
			<span class={`review r-${pr.reviewed}`} title={who || "No reviews"}>
				{mark || "–"}
				<span class="sr">{markText}</span>
			</span>
			{!reviewBot && <span class="review-bot" />}
			{reviewBot && (
				<span
					class={`review-bot ${botClass(pr.botReview)}`}
					title={botTitle(reviewBot, pr.botReview)}
				>
					{botClass(pr.botReview) === "lgtm"
						? "✓ LGTM"
						: pr.botReview
							? `#${pr.botReview.n}`
							: "–"}
				</span>
			)}
			<span
				class={`age a-${pr.ageLevel}${pr.approvedIdle ? " idle" : ""}`}
				title={
					pr.mergedAt
						? `opened ${ago(pr.createdAt, now)} ago, merged ${ago(pr.mergedAt, now)} ago`
						: `opened ${ago(pr.createdAt, now)} ago, updated ${ago(pr.updatedAt, now)} ago${pr.approvedIdle ? ", approved but not merged for over 2 days" : ""}`
				}
			>
				{/* A merged pull request shows how long ago it was merged. */}
				{ago(pr.mergedAt ?? pr.createdAt, now)}
				{pr.approvedIdle && " ⏸"}
			</span>
		</div>
	);
}

// The palette comes from the server, built from the dotfiles theme.
const theme = document.createElement("link");
theme.rel = "stylesheet";
theme.href = "/theme.css";
document.head.prepend(theme);

// `/pr/<repo>/<number>` is the review page; everything else is the list.
const route = location.pathname.match(/^\/pr\/([^/]+)\/(\d+)\/?$/);
render(
	route ? <Review repo={route[1]} number={Number(route[2])} /> : <App />,
	document.getElementById("app") as HTMLElement,
);
