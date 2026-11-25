// Serves the mission control page and the team's open pull requests as JSON.
// The wrapper bin/mission-control runs it behind portless, which sets PORT.
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ApiView } from "./api/languages.ts";
import { apiView, buildGoHelper, CACHE_DIR } from "./api/view.ts";
import {
	type Client,
	caseless,
	client,
	gitattributes,
	mergeBase,
	mergedPRs,
	openPRs,
	postReview,
	prFiles,
	pullRequest,
	teamMembers,
	viewerLogin,
} from "./github.ts";
import index from "./index.html";
import {
	botName,
	checkReviewWrite,
	isGenerated,
	type PR,
	type PRFile,
	parseGitattributes,
	toPR,
} from "./model.ts";

const CACHE_MS = 2 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;
const MEMBERS_MS = DAY_MS;
// Without a window of days, the merged list goes back this many days.
const MERGED_MAX_DAYS = 30;
// Changed files of the pull requests opened lately, by head commit.
const FILES_KEPT = 30;

function workConfig(key: string): string[] {
	const out = Bun.spawnSync(["work-config", key], { stderr: "ignore" });
	if (out.exitCode !== 0) return [];
	return out.stdout.toString().split("\n").filter(Boolean);
}

const [teamSetting] = workConfig("github.review_team");
if (!teamSetting?.includes("/"))
	throw new Error(
		"Set github.review_team (org/team) in the work config; see work-config --path.",
	);
const [org, team] = teamSetting.split("/");
const readyLabel = workConfig("github.review_label")[0] ?? "ready-for-review";
const jiraBase = workConfig("jira.browse_url")[0] ?? "";
const jiraProjects = workConfig("jira.projects");
// The HTML comment a review bot writes into its PR comments, such as
// `bot:review`. Without it, the page shows no review bot.
const reviewMarker = workConfig("mission_control.review_marker")[0] ?? "";
const reviewBot = botName(reviewMarker);
// Team members who do not open pull requests, such as a manager.
const skipMembers = new Set(
	workConfig("mission_control.skip_members").map((m) => m.toLowerCase()),
);

// A dedicated token wins. Otherwise reuse gh's login. The token stays in
// this process's memory and is never written or logged.
function token(): string {
	const own = Bun.env.MISSION_CONTROL_GITHUB_TOKEN;
	if (own) return own;
	const out = Bun.spawnSync(["gh", "auth", "token"], { stderr: "ignore" });
	const value = out.stdout.toString().trim();
	if (out.exitCode !== 0 || !value)
		throw new Error("gh is not logged in; run gh auth login");
	return value;
}

// The page sends this back on every write. Only a page this server served
// can read it, because the server never answers cross-origin requests.
const csrfToken = Buffer.from(
	crypto.getRandomValues(new Uint8Array(32)),
).toString("hex");

let viewer: string | null = null;

async function whoAmI(): Promise<string> {
	viewer ??= await viewerLogin(client(token()));
	return viewer;
}

type Snapshot = {
	fetchedAt: string;
	members: string[];
	prs: PR[];
};

let members: { list: string[]; at: number } | null = null;

// The list asks for one kind of pull request over one window of days, and
// the server fetches only that. Open pull requests are counted from when
// they were opened, merged ones from when they were merged. Without days,
// all open pull requests load, and merged ones from the last
// MERGED_MAX_DAYS. Each kind and window has its own cache.
type Kind = "open" | "merged";
type List = {
	last: Snapshot | null;
	error: string | null;
	inflight: Promise<void> | null;
};
const lists = new Map<string, List>();

async function teamList(gh: Client): Promise<string[]> {
	if (!members || Date.now() - members.at > MEMBERS_MS)
		members = {
			list: (await teamMembers(gh, org, team)).filter(
				(m) => !skipMembers.has(m.toLowerCase()),
			),
			at: Date.now(),
		};
	return members.list;
}

async function refresh(list: List, kind: Kind, days: number | null) {
	const gh = client(token());
	const team = await teamList(gh);
	const now = Date.now();
	const window = kind === "merged" ? (days ?? MERGED_MAX_DAYS) : days;
	const since =
		window === null
			? null
			: new Date(now - window * DAY_MS).toISOString().slice(0, 10);
	const raw = (
		await Promise.all(
			team.map((login) =>
				kind === "merged"
					? mergedPRs(gh, org, login, since as string)
					: openPRs(gh, org, login, since),
			),
		)
	).flat();
	list.last = {
		fetchedAt: new Date(now).toISOString(),
		members: team,
		prs: raw
			.map((pr) => toPR(pr, { readyLabel, jiraProjects, reviewMarker, now }))
			.sort(
				(a, b) =>
					caseless(a.author, b.author) ||
					Date.parse(a.createdAt) - Date.parse(b.createdAt),
			),
	};
	list.error = null;
}

async function snapshot(fresh: boolean, kind: Kind, days: number | null) {
	const key = `${kind}:${days ?? "all"}`;
	let list = lists.get(key);
	if (!list) {
		list = { last: null, error: null, inflight: null };
		lists.set(key, list);
	}
	const age = list.last
		? Date.now() - Date.parse(list.last.fetchedAt)
		: Infinity;
	if (fresh || age > CACHE_MS) {
		const target = list;
		target.inflight ??= refresh(target, kind, days)
			.catch((error: Error) => {
				target.error = error.message;
				console.error(`mission-control: ${error.message}`);
			})
			.finally(() => {
				target.inflight = null;
			});
		// Old data answers at once while the refresh runs. The page polls,
		// so it gets the new data on its next load. Refresh waits.
		if (fresh || !list.last) await target.inflight;
	}
	return {
		...(list.last ?? { fetchedAt: null, members: [], prs: [] }),
		error: list.error,
		readyLabel,
		jiraBase,
		reviewBot,
		csrfToken,
	};
}

// The window of days the page asks for: a whole number from 1 to 365, or
// null for no window.
function daysParam(value: string | null): number | null {
	const days = Number(value);
	return value && Number.isInteger(days) && days >= 1 && days <= 365
		? days
		: null;
}

// The review page asks for the files and for the API view at once, so a
// list in the making is here too.
const filesCache = new Map<string, Promise<PRFile[]>>();

function changedFiles(
	secret: string,
	repo: string,
	number: number,
	sha: string,
): Promise<PRFile[]> {
	const key = `${repo}#${number}@${sha}`;
	const hit = filesCache.get(key);
	if (hit) return hit;
	const files = (async () => {
		const [raw, attributes] = await Promise.all([
			prFiles(secret, org, repo, number),
			gitattributes(secret, org, repo, sha),
		]);
		const rules = parseGitattributes(attributes);
		return raw.map((f) => {
			const file = {
				path: f.filename,
				prevPath: f.previous_filename ?? null,
				status: f.status,
				additions: f.additions,
				deletions: f.deletions,
				patch: f.patch ?? null,
			};
			return { ...file, generated: isGenerated(file, rules) };
		});
	})();
	filesCache.set(key, files);
	files.catch(() => filesCache.delete(key));
	if (filesCache.size > FILES_KEPT)
		filesCache.delete(filesCache.keys().next().value as string);
	return files;
}

const REPO_NAME = /^[\w.-]+$/;

function prNumber(repo: string, numberText: string): number | null {
	const number = Number(numberText);
	return REPO_NAME.test(repo) && Number.isSafeInteger(number) && number > 0
		? number
		: null;
}

// The review page asks for a pull request and for its API view at once.
// Both read the pull request, and the second waits for the first's answer.
const prLookups = new Map<string, ReturnType<typeof pullRequest>>();

function lookUp(secret: string, repo: string, number: number) {
	const key = `${repo}#${number}`;
	let lookup = prLookups.get(key);
	if (!lookup) {
		lookup = pullRequest(client(secret), org, repo, number).finally(() =>
			prLookups.delete(key),
		);
		prLookups.set(key, lookup);
	}
	return lookup;
}

async function prDetail(repo: string, numberText: string) {
	const number = prNumber(repo, numberText);
	if (!number)
		return Response.json({ error: "Bad pull request" }, { status: 400 });
	const secret = token();
	const raw = await lookUp(secret, repo, number);
	if (!raw)
		return Response.json({ error: "Pull request not found" }, { status: 404 });
	const files = await changedFiles(secret, repo, number, raw.headRefOid);
	return Response.json({
		pr: toPR(raw, {
			readyLabel,
			jiraProjects,
			reviewMarker,
			now: Date.now(),
		}),
		// GitHub renders and sanitizes the Markdown, as on its own page.
		bodyHTML: raw.bodyHTML,
		headSha: raw.headRefOid,
		files,
		jiraBase,
		reviewBot,
		viewer: await whoAmI(),
		csrfToken,
	});
}

// API views of the pull requests opened lately. A view in the making is
// here too, so a second request waits for the first.
const apiCache = new Map<string, Promise<ApiView>>();

async function prApi(
	repo: string,
	numberText: string,
	options: { comments: boolean; private: boolean },
) {
	const number = prNumber(repo, numberText);
	if (!number)
		return Response.json({ error: "Bad pull request" }, { status: 400 });
	const secret = token();
	const raw = await lookUp(secret, repo, number);
	if (!raw)
		return Response.json({ error: "Pull request not found" }, { status: 404 });
	const head = raw.headRefOid;
	const key = `${repo}@${raw.baseRefOid}...${head}:${options.comments}:${options.private}`;
	let view = apiCache.get(key);
	if (!view) {
		view = (async () => {
			const [files, base] = await Promise.all([
				changedFiles(secret, repo, number, head),
				mergeBase(secret, org, repo, raw.baseRefOid, head),
			]);
			return apiView(
				{
					dir: join(CACHE_DIR, "repos", `${repo}.git`),
					url: `https://github.com/${org}/${repo}.git`,
					auth: `Basic ${btoa(`x-access-token:${secret}`)}`,
				},
				base,
				head,
				files,
				options,
			);
		})();
		apiCache.set(key, view);
		// A failed view is built again on the next request.
		view.catch(() => apiCache.delete(key));
		if (apiCache.size > FILES_KEPT)
			apiCache.delete(apiCache.keys().next().value as string);
	}
	return Response.json(await view);
}

// The origins the page runs on: the portless URL and the server's own.
function pageOrigins(): string[] {
	const origins = [server.url.origin];
	if (Bun.env.PORTLESS_URL) origins.push(new URL(Bun.env.PORTLESS_URL).origin);
	return origins;
}

async function postPRReview(req: Request, repo: string, numberText: string) {
	const number = prNumber(repo, numberText);
	if (!number)
		return Response.json({ error: "Bad pull request" }, { status: 400 });
	let request: unknown = null;
	try {
		request = await req.json();
	} catch {
		/* checkReviewWrite refuses a missing request. */
	}
	const secret = token();
	const gh = client(secret);
	const [raw, team, me] = await Promise.all([
		pullRequest(gh, org, repo, number),
		teamList(gh),
		whoAmI(),
	]);
	if (!raw)
		return Response.json({ error: "Pull request not found" }, { status: 404 });
	const verdict = checkReviewWrite({
		contentType: req.headers.get("content-type"),
		origin: req.headers.get("origin"),
		token: req.headers.get("x-mission-control-token"),
		request,
		expectedToken: csrfToken,
		allowedOrigins: pageOrigins(),
		viewer: me,
		members: team,
		author: raw.author?.login ?? "",
		headSha: raw.headRefOid,
	});
	const where = `${repo}#${number}`;
	if (!verdict.ok) {
		console.log(`mission-control: review ${where} refused: ${verdict.reason}`);
		return Response.json({ error: verdict.reason }, { status: verdict.status });
	}
	const result = await postReview(secret, org, repo, number, verdict);
	const ok = result.status >= 200 && result.status < 300;
	console.log(
		`mission-control: review ${where} ${verdict.event}: ${ok ? "posted" : `GitHub HTTP ${result.status}`}`,
	);
	if (!ok)
		return Response.json(
			{ error: result.message ?? `GitHub HTTP ${result.status}` },
			{ status: 502 },
		);
	// The list shows review state, so refresh it for the next visit.
	for (const key of lists.keys()) {
		const [kind, days] = key.split(":");
		if (kind === "open") void snapshot(true, "open", daysParam(days));
	}
	return Response.json({ state: result.state });
}

// The page takes its colours from blueprint's palette in the dotfiles theme,
// so it follows the same light and dark scheme as the explainers. The diff
// view takes the theme's diff colours in dark mode and blueprint's add and
// delete colours in light mode.
type Theme = {
	diff?: Record<string, Record<string, string>>;
	applications?: { blueprint?: Record<string, Record<string, string>> };
};

function diffVars(theme: Theme, mode: "light" | "dark"): string {
	const vars: Record<string, string | undefined> = {};
	if (mode === "dark") {
		const { added, removed, changed } = theme.diff ?? {};
		Object.assign(vars, {
			"addition-color-override": added?.foreground,
			"bg-addition-override": added?.lineBackground,
			"bg-addition-emphasis-override": added?.emphasisBackground,
			"bg-addition-number-override": added?.dimBackground,
			"deletion-color-override": removed?.foreground,
			"bg-deletion-override": removed?.lineBackground,
			"bg-deletion-emphasis-override": removed?.emphasisBackground,
			"bg-deletion-number-override": removed?.dimBackground,
			"modified-color-override": changed?.foreground,
		});
	} else {
		const light = theme.applications?.blueprint?.light ?? {};
		Object.assign(vars, {
			"addition-color-override": light.add,
			"bg-addition-override": light["add-bg"],
			"bg-addition-number-override": light["add-bg"],
			"deletion-color-override": light.del,
			"bg-deletion-override": light["del-bg"],
			"bg-deletion-number-override": light["del-bg"],
		});
	}
	return Object.entries(vars)
		.filter(([, value]) => value)
		.map(([key, value]) => `--diffs-${key}:${value};`)
		.join("");
}

function themeCSS(): string {
	for (const file of [
		join(import.meta.dir, "../../nix/themes/monokai.json"),
		join(
			Bun.env.XDG_CONFIG_HOME || join(homedir(), ".config"),
			"dotfiles/theme.json",
		),
	]) {
		try {
			const theme = JSON.parse(readFileSync(file, "utf8")) as Theme;
			const palette = theme.applications?.blueprint;
			if (!palette) continue;
			const vars = (mode: "light" | "dark") =>
				Object.entries(palette[mode])
					.map(([key, value]) => `--${key}:${value};`)
					.join("") + diffVars(theme, mode);
			return `:root{${vars("light")}color-scheme:light}
:root[data-theme="dark"]{${vars("dark")}color-scheme:dark}
@media(prefers-color-scheme:dark){:root:not([data-theme="light"]){${vars("dark")}color-scheme:dark}}`;
		} catch {
			/* Try the next copy of the theme. */
		}
	}
	return "";
}
const theme = themeCSS();

const server = Bun.serve({
	port: Number(Bun.env.PORT) || 4380,
	development: Bun.env.MISSION_CONTROL_DEV === "1",
	routes: {
		"/": index,
		"/pr/*": index,
		"/theme.css": () =>
			new Response(theme, { headers: { "content-type": "text/css" } }),
		"/api/prs": async (req) => {
			const params = new URL(req.url).searchParams;
			const kind = params.get("state") === "merged" ? "merged" : "open";
			const days = daysParam(params.get("days"));
			return Response.json(await snapshot(params.has("fresh"), kind, days));
		},
		// POST only: other methods, a CORS preflight among them, get no route.
		"/api/pr/:repo/:number/review": {
			POST: async (req) => {
				try {
					return await postPRReview(req, req.params.repo, req.params.number);
				} catch (error) {
					console.error(`mission-control: ${(error as Error).message}`);
					return Response.json(
						{ error: (error as Error).message },
						{ status: 502 },
					);
				}
			},
		},
		// Apart from the pull request itself, so the line diff never waits for
		// it.
		"/api/pr/:repo/:number/api": async (req) => {
			try {
				const asked = new URL(req.url).searchParams;
				return await prApi(req.params.repo, req.params.number, {
					comments: asked.has("comments"),
					private: asked.has("private"),
				});
			} catch (error) {
				console.error(`mission-control: ${(error as Error).message}`);
				return Response.json(
					{ error: (error as Error).message },
					{ status: 502 },
				);
			}
		},
		"/api/pr/:repo/:number": async (req) => {
			try {
				return await prDetail(req.params.repo, req.params.number);
			} catch (error) {
				console.error(`mission-control: ${(error as Error).message}`);
				return Response.json(
					{ error: (error as Error).message },
					{ status: 502 },
				);
			}
		},
	},
});

console.log(`mission-control: ${org}/${team} on ${server.url}`);

// Build the Go helper now, so the first API view finds it ready. Without Go,
// the view reports that when it is asked for.
buildGoHelper().catch(() => {});

// Fetch the default view, open pull requests of the last 7 days, now, so
// the first visit finds it ready.
void snapshot(false, "open", 7);
