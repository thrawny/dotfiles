import { type ComponentChildren, render } from "preact";
import { useEffect, useMemo, useRef, useState } from "preact/hooks";
import { BUCKETS, type Bucket, OLD_DAYS, type PR, WARN_DAYS } from "./model.ts";
import { Review } from "./review.tsx";
import {
	Active,
	ago,
	botClass,
	botTitle,
	CI_TEXT,
	jiraHref,
	lines,
	listHref,
	navigate,
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
	// The list can change in the background while a review page shows.
	if (location.pathname.startsWith("/pr/")) return;
	history.replaceState(null, "", `?${p}`);
}

// What the list asks the server for: the state, and the age filter's
// window of days when it keeps only recent pull requests, such as `-7`.
function serverQuery(f: Filters): string {
	const p = new URLSearchParams();
	if (f.state === "merged") p.set("state", "merged");
	if (f.age.startsWith("-")) p.set("days", f.age.slice(1));
	return p.toString();
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
	// CI, review and review bot filters describe open pull requests, so the
	// merged view hides them and ignores them.
	const open = !pr.mergedAt;
	if (open && f.ci && pr.ci !== f.ci) return false;
	if (open && f.review && pr.reviewed !== f.review) return false;
	// An age of `-30` keeps PRs up to 30 days old; `14` keeps older ones.
	if (f.age.startsWith("-")) {
		if (pr.ageDays > -Number(f.age)) return false;
	} else if (f.age && pr.ageDays <= Number(f.age)) return false;
	const bot = pr.botReview;
	if (open && f.bot === "none" && bot) return false;
	if (open && f.bot === "todo" && bot && !bot.stale) return false;
	if (open && f.bot === "lgtm" && !(bot?.verdict === "lgtm" && !bot.stale))
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
	// The server fetches only what the filters show: open or merged pull
	// requests, over the age filter's last N days when it has one. Another
	// state or window is a new fetch.
	const wanted = serverQuery(filters);
	const want = useRef(wanted);
	want.current = wanted;

	const load = async (fresh = false) => {
		const asked = want.current;
		const params = new URLSearchParams(asked);
		if (fresh) params.set("fresh", "1");
		setLoading(true);
		try {
			const res = await fetch(`/api/prs?${params}`);
			const json = await res.json();
			// An answer for filters that have changed since is dropped.
			if (asked === want.current) setData(json);
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
		load();
	}, [wanted]);
	useEffect(() => {
		if (!data || !wantReadyLabel) return;
		wantReadyLabel = false;
		setFilters((f) => ({ ...f, label: [data.readyLabel] }));
	}, [data]);
	const set = (patch: Partial<Filters>) =>
		setFilters((f) => ({ ...f, ...patch }));

	const shown = data;
	const mergedView = filters.state === "merged";
	const prs = data?.prs ?? [];
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
	const open = prs.filter((p) => !p.draft && !p.mergedAt);
	const count = (bucket: Bucket) =>
		open.filter((p) => p.bucket === bucket).length;

	return (
		<>
			<header class="top">
				<h1>Mission control</h1>
				{mergedView ? (
					<div class="totals">
						<span>{prs.filter((p) => p.mergedAt).length} merged</span>
					</div>
				) : (
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
				)}
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
						all={prs.filter((p) => p.author === m)}
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
	// The merged view hides the filters that describe open pull requests.
	const merged = f.state === "merged";
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
					["merged", "Merged"],
				])}
				{select("repo", [
					["", "All repos"],
					...props.repos.map((r): [string, string] => [r, r]),
				])}
				{!merged &&
					select("ci", [
						["", "Any CI"],
						["failure", "CI failing"],
						["pending", "CI pending"],
						["success", "CI green"],
						["none", "No CI"],
					])}
				{!merged &&
					select("review", [
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
					!merged &&
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
				<span class="muted">
					{open.length || !props.all.length
						? `${open.length} open`
						: `${props.all.length} merged`}
				</span>
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

// Review pages kept open in the background, so going back to one keeps its
// place and needs no reload. The oldest closes past this count.
const REVIEWS_KEPT = 5;

type Opened = { key: string; repo: string; number: number };

// `/pr/<repo>/<number>` is the review page; everything else is the list.
function routeOf(path: string): Opened | null {
	const match = path.match(/^\/pr\/([^/]+)\/(\d+)\/?$/);
	return match
		? {
				key: `${match[1]}#${match[2]}`,
				repo: match[1],
				number: Number(match[2]),
			}
		: null;
}

// A page that stays open while another shows. It keeps its size, so the
// diff viewer keeps its layout and scroll place.
function Page({
	active,
	children,
}: {
	active: boolean;
	children: ComponentChildren;
}) {
	return (
		<Active.Provider value={active}>
			<div class={active ? "page" : "page background"}>{children}</div>
		</Active.Provider>
	);
}

// Shows a review page. From the list, back returns to it.
function show(path: string) {
	const fromList = !routeOf(location.pathname);
	if (fromList) listHref.current = location.pathname + location.search;
	navigate(path, { fromList });
}

// The list and the review pages opened lately stay open. A link to a review
// page switches pages in place.
function Router() {
	const [path, setPath] = useState(location.pathname);
	const route = routeOf(path);
	const [opened, setOpened] = useState<Opened[]>([]);
	const [listOpened, setListOpened] = useState(!route);
	const listScroll = useRef(0);

	useEffect(() => {
		const sync = () => {
			// The list scrolls the window, which the review page does not.
			if (!routeOf(path)) listScroll.current = scrollY;
			setPath(location.pathname);
		};
		addEventListener("popstate", sync);
		addEventListener("mc-navigate", sync);
		return () => {
			removeEventListener("popstate", sync);
			removeEventListener("mc-navigate", sync);
		};
	}, [path]);

	useEffect(() => {
		document.body.classList.toggle("review-mode", !!route);
		if (route) {
			setOpened((old) =>
				[...old.filter((o) => o.key !== route.key), route].slice(-REVIEWS_KEPT),
			);
			return;
		}
		setListOpened(true);
		document.title = "Mission control";
		requestAnimationFrame(() => scrollTo(0, listScroll.current));
	}, [path]);

	// The server tells the page to show a pull request, when asked from the
	// command line. While the server is down, portless answers with an error
	// status, and the browser then gives up on the stream for good. So the
	// page connects again itself, every few seconds, until the server is back.
	useEffect(() => {
		let source: EventSource;
		let retry = 0;
		const connect = () => {
			source = new EventSource("/api/events");
			source.addEventListener("show", (event) => {
				const target = (event as MessageEvent<string>).data;
				if (routeOf(target) && target !== location.pathname) show(target);
			});
			source.onerror = () => {
				if (source.readyState !== EventSource.CLOSED) return;
				retry = window.setTimeout(connect, 3000);
			};
		};
		connect();
		return () => {
			clearTimeout(retry);
			source.close();
		};
	}, []);

	// A plain click on a link to a review page switches in place. A click
	// with a modifier opens a new tab as usual.
	useEffect(() => {
		const onClick = (event: MouseEvent) => {
			if (
				event.button !== 0 ||
				event.metaKey ||
				event.ctrlKey ||
				event.shiftKey ||
				event.altKey
			)
				return;
			const link = (event.target as Element).closest?.("a[href]");
			if (!(link instanceof HTMLAnchorElement) || link.target) return;
			const url = new URL(link.href);
			if (url.origin !== location.origin || !routeOf(url.pathname)) return;
			event.preventDefault();
			show(url.pathname);
		};
		document.addEventListener("click", onClick);
		return () => document.removeEventListener("click", onClick);
	}, []);

	return (
		<>
			{listOpened && (
				<Page active={!route}>
					<App />
				</Page>
			)}
			{opened.map((o) => (
				<Page key={o.key} active={route?.key === o.key}>
					<Review repo={o.repo} number={o.number} />
				</Page>
			))}
		</>
	);
}

// The router puts the list's scroll place back itself.
history.scrollRestoration = "manual";
render(<Router />, document.getElementById("app") as HTMLElement);
