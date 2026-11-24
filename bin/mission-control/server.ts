// Serves the mission control page and the team's open pull requests as JSON.
// The wrapper bin/mission-control runs it behind portless, which sets PORT.
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import {
	caseless,
	client,
	gitattributes,
	openPRs,
	prFiles,
	pullRequest,
	teamMembers,
} from "./github.ts";
import index from "./index.html";
import {
	isGenerated,
	type PR,
	type PRFile,
	parseGitattributes,
	toPR,
} from "./model.ts";

const CACHE_MS = 2 * 60 * 1000;
const MEMBERS_MS = 24 * 60 * 60 * 1000;
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

type Snapshot = {
	fetchedAt: string;
	members: string[];
	prs: PR[];
};

let members: { list: string[]; at: number } | null = null;
let last: Snapshot | null = null;
let lastError: string | null = null;
let inflight: Promise<void> | null = null;

async function refresh() {
	const gh = client(token());
	if (!members || Date.now() - members.at > MEMBERS_MS)
		members = {
			list: (await teamMembers(gh, org, team)).filter(
				(m) => !skipMembers.has(m.toLowerCase()),
			),
			at: Date.now(),
		};
	const now = Date.now();
	const raw = (
		await Promise.all(members.list.map((login) => openPRs(gh, org, login)))
	).flat();
	last = {
		fetchedAt: new Date(now).toISOString(),
		members: members.list,
		prs: raw
			.map((pr) => toPR(pr, { readyLabel, jiraProjects, now }))
			.sort(
				(a, b) =>
					caseless(a.author, b.author) ||
					Date.parse(a.createdAt) - Date.parse(b.createdAt),
			),
	};
	lastError = null;
}

async function snapshot(fresh: boolean) {
	const age = last ? Date.now() - Date.parse(last.fetchedAt) : Infinity;
	if (fresh || age > CACHE_MS) {
		inflight ??= refresh()
			.catch((error: Error) => {
				lastError = error.message;
				console.error(`mission-control: ${error.message}`);
			})
			.finally(() => {
				inflight = null;
			});
		await inflight;
	}
	return {
		...(last ?? { fetchedAt: null, members: [], prs: [] }),
		error: lastError,
		readyLabel,
		jiraBase,
	};
}

const filesCache = new Map<string, PRFile[]>();

async function changedFiles(
	secret: string,
	repo: string,
	number: number,
	sha: string,
): Promise<PRFile[]> {
	const key = `${repo}#${number}@${sha}`;
	const hit = filesCache.get(key);
	if (hit) return hit;
	const [raw, attributes] = await Promise.all([
		prFiles(secret, org, repo, number),
		gitattributes(secret, org, repo, sha),
	]);
	const rules = parseGitattributes(attributes);
	const files = raw.map((f) => {
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
	filesCache.set(key, files);
	if (filesCache.size > FILES_KEPT)
		filesCache.delete(filesCache.keys().next().value as string);
	return files;
}

const REPO_NAME = /^[\w.-]+$/;

async function prDetail(repo: string, numberText: string) {
	const number = Number(numberText);
	if (!REPO_NAME.test(repo) || !Number.isSafeInteger(number) || number < 1)
		return Response.json({ error: "Bad pull request" }, { status: 400 });
	const secret = token();
	const raw = await pullRequest(client(secret), org, repo, number);
	if (!raw)
		return Response.json({ error: "Pull request not found" }, { status: 404 });
	const files = await changedFiles(secret, repo, number, raw.headRefOid);
	return Response.json({
		pr: toPR(raw, { readyLabel, jiraProjects, now: Date.now() }),
		body: raw.body,
		headSha: raw.headRefOid,
		files,
		jiraBase,
	});
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
			const fresh = new URL(req.url).searchParams.has("fresh");
			return Response.json(await snapshot(fresh));
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
