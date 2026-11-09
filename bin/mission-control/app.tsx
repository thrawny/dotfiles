import { render } from "preact";
import { useEffect, useMemo, useState } from "preact/hooks";
import { BUCKETS, type Bucket, OLD_DAYS, type PR, WARN_DAYS } from "./model.ts";

type Data = {
	fetchedAt: string | null;
	members: string[];
	prs: PR[];
	error: string | null;
	readyLabel: string;
	jiraBase: string;
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
	tono: string;
	q: string;
	drafts: boolean;
	side: boolean;
};

// A visit with no query gets the default view: two columns, PRs with the
// review label, opened in the last 30 days, that nobody has reviewed yet.
// The label name comes with the data, so it is set once the first load
// arrives.
let wantReadyLabel = false;

function readFilters(): Filters {
	const p = new URLSearchParams(location.search);
	if (!location.search) {
		wantReadyLabel = true;
		p.set("review", "none");
		p.set("age", "-30");
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
		tono: p.get("tono") ?? "",
		q: p.get("q") ?? "",
		drafts: p.get("drafts") === "1",
		side: p.get("layout") === "side",
	};
}

function writeFilters(f: Filters) {
	const p = new URLSearchParams();
	if (f.author.length) p.set("author", f.author.join(","));
	if (f.label.length) p.set("label", f.label.join(","));
	for (const key of ["repo", "ci", "review", "age", "tono", "q"] as const)
		if (f[key]) p.set(key, f[key]);
	if (f.drafts) p.set("drafts", "1");
	// Layout is always written, so a view without filters keeps a query and
	// is not replaced by the default view on reload.
	p.set("layout", f.side ? "side" : "stack");
	history.replaceState(null, "", `?${p}`);
}

function matches(pr: PR, f: Filters): boolean {
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
	if (f.tono === "none" && pr.tono) return false;
	if (f.tono === "todo" && pr.tono && !pr.tono.stale) return false;
	if (f.tono === "lgtm" && !(pr.tono?.verdict === "lgtm" && !pr.tono.stale))
		return false;
	if (f.q) {
		const text =
			`${pr.title} ${pr.jiraKey ?? ""} ${pr.repo}#${pr.number}`.toLowerCase();
		if (!text.includes(f.q.toLowerCase())) return false;
	}
	return true;
}

function lines(n: number) {
	return n >= 1000 ? `${(n / 1000).toFixed(n >= 10000 ? 0 : 1)}k` : String(n);
}

function ago(iso: string, now: number) {
	const mins = Math.round((now - Date.parse(iso)) / 60000);
	if (mins < 60) return `${mins}m`;
	const hours = Math.round(mins / 60);
	if (hours < 48) return `${hours}h`;
	return `${Math.round(hours / 24)}d`;
}

function App() {
	const [data, setData] = useState<Data | null>(null);
	const [loading, setLoading] = useState(false);
	const [filters, setFilters] = useState(readFilters);
	const [now, setNow] = useState(Date.now());

	const load = async (fresh = false) => {
		setLoading(true);
		try {
			const res = await fetch(fresh ? "/api/prs?fresh=1" : "/api/prs");
			setData(await res.json());
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
		if (!data || !wantReadyLabel) return;
		wantReadyLabel = false;
		setFilters((f) => ({ ...f, label: [data.readyLabel] }));
	}, [data]);
	const set = (patch: Partial<Filters>) =>
		setFilters((f) => ({ ...f, ...patch }));

	const prs = data?.prs ?? [];
	const visible = useMemo(
		() => prs.filter((pr) => matches(pr, filters)),
		[prs, filters],
	);
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
	const open = prs.filter((p) => !p.draft);
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
			{data?.error && (
				<p class="error">
					GitHub fetch failed: {data.error}
					{data.fetchedAt ? " Showing the last good data." : ""}
				</p>
			)}
			<FilterBar
				filters={filters}
				set={set}
				members={data?.members ?? []}
				repos={repos}
				labels={labels}
			/>
			{!data && <p class="muted">Loading pull requests…</p>}
			<main class={filters.side ? "cards side" : "cards"}>
				{members.map((m) => (
					<MemberCard
						key={m}
						login={m}
						prs={visible.filter((p) => p.author === m)}
						all={prs.filter((p) => p.author === m)}
						jiraBase={data?.jiraBase ?? ""}
						now={now}
					/>
				))}
			</main>
		</>
	);
}

function ThemeButton() {
	const toggle = () => {
		const root = document.documentElement;
		const dark = root.dataset.theme
			? root.dataset.theme === "dark"
			: matchMedia("(prefers-color-scheme: dark)").matches;
		const next = dark ? "light" : "dark";
		root.dataset.theme = next;
		try {
			localStorage.setItem("bp-theme", next);
		} catch {}
	};
	return (
		<button type="button" onClick={toggle} title="Toggle light/dark">
			◐
		</button>
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
}) {
	const { filters: f, set } = props;
	const select = (
		key: "repo" | "ci" | "review" | "age" | "tono",
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
					["-30", "Last 30 days"],
					[String(WARN_DAYS), `Older than ${WARN_DAYS} days`],
					[String(OLD_DAYS), `Older than ${OLD_DAYS} days`],
				])}
				{select("tono", [
					["", "Any tono"],
					["todo", "No tono, or stale"],
					["none", "No tono"],
					["lgtm", "Tono LGTM on head"],
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
	now: number;
}) {
	const { login, prs } = props;
	const open = props.all.filter((p) => !p.draft);
	const summary = BUCKETS.filter((b) => b.id !== "draft")
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
				if (!rows.length) return null;
				return (
					<section class="bucket">
						<h3 class={`b-${b.id}`}>
							{b.title} <span class="muted">{rows.length}</span>
						</h3>
						{rows.map((pr) => (
							<Row pr={pr} jiraBase={props.jiraBase} now={props.now} />
						))}
					</section>
				);
			})}
			{!prs.length && <p class="muted empty">No pull requests match.</p>}
		</details>
	);
}

const CI_TEXT = {
	success: "CI green",
	failure: "CI failing",
	pending: "CI running",
	none: "No CI",
};

const REVIEW_MARK = {
	approved: ["✓", "Approved"],
	changes: ["✗", "Changes requested"],
	commented: ["•", "Commented"],
	none: ["", ""],
};

function Row({ pr, jiraBase, now }: { pr: PR; jiraBase: string; now: number }) {
	const [mark, markText] = REVIEW_MARK[pr.reviewed];
	const who = pr.reviewers
		.map((r) => `${r.login}: ${r.state.toLowerCase().replace("_", " ")}`)
		.join("\n");
	return (
		<div class="pr">
			<span class={`dot ci-${pr.ci}`} title={CI_TEXT[pr.ci]} />
			<span class="repo">{pr.repo}</span>
			<a class="title" href={pr.url} target="_blank" rel="noopener">
				{pr.title}
				<span class="muted"> #{pr.number}</span>
			</a>
			{pr.jiraKey &&
				(jiraBase ? (
					<a
						class="jira"
						href={`${jiraBase.replace(/\/$/, "")}/${pr.jiraKey}`}
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
			<span
				class={
					pr.tono
						? `tono ${pr.tono.stale ? "stale" : pr.tono.verdict === "lgtm" ? "lgtm" : "findings"}`
						: "tono none"
				}
				title={
					pr.tono
						? `tono review #${pr.tono.n}: ${pr.tono.verdict || "no verdict"}${pr.tono.stale ? ", new commits since" : ""}`
						: "No tono review"
				}
			>
				{pr.tono ? `#${pr.tono.n}` : "–"}
			</span>
			<span
				class={`age a-${pr.ageLevel}${pr.approvedIdle ? " idle" : ""}`}
				title={`opened ${ago(pr.createdAt, now)} ago, updated ${ago(pr.updatedAt, now)} ago${pr.approvedIdle ? ", approved but not merged for over 2 days" : ""}`}
			>
				{ago(pr.createdAt, now)}
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

render(<App />, document.getElementById("app") as HTMLElement);
