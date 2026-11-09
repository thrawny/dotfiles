// Serves the mission control page and the team's open pull requests as JSON.
// The wrapper bin/mission-control runs it behind portless, which sets PORT.
import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { caseless, client, openPRs, teamMembers } from "./github.ts";
import index from "./index.html";
import { type PR, toPR } from "./model.ts";

const CACHE_MS = 2 * 60 * 1000;
const MEMBERS_MS = 24 * 60 * 60 * 1000;

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

// The page takes its colours from blueprint's palette in the dotfiles theme,
// so it follows the same light and dark scheme as the explainers.
function themeCSS(): string {
	for (const file of [
		join(import.meta.dir, "../../nix/themes/monokai.json"),
		join(
			Bun.env.XDG_CONFIG_HOME || join(homedir(), ".config"),
			"dotfiles/theme.json",
		),
	]) {
		try {
			const palette = JSON.parse(readFileSync(file, "utf8")).applications
				?.blueprint as Record<string, Record<string, string>> | undefined;
			if (!palette) continue;
			const vars = (mode: string) =>
				Object.entries(palette[mode])
					.map(([key, value]) => `--${key}:${value};`)
					.join("");
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
		"/theme.css": () =>
			new Response(theme, { headers: { "content-type": "text/css" } }),
		"/api/prs": async (req) => {
			const fresh = new URL(req.url).searchParams.has("fresh");
			return Response.json(await snapshot(fresh));
		},
	},
});

console.log(`mission-control: ${org}/${team} on ${server.url}`);
