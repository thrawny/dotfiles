#!/usr/bin/env bun
// The mission-control command: runs the server, opens the page and shows a
// pull request in the open page. To put it on PATH, run `bun link`, then
// `bun add -g link:dotfiles-mission-control`, in this folder.
//
//   mission-control serve        run the server in this terminal
//   mission-control stop         stop the server that serve started
//   mission-control open [PR]    open the page, or show a pull request in
//                                the open page, in place: a GitHub URL,
//                                repo#123 or repo 123
//
// Where the server runs, such as a terminal tab, is up to the caller.
import { spawn } from "node:child_process";
import {
	existsSync,
	mkdirSync,
	readFileSync,
	realpathSync,
	rmSync,
	writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { $ } from "bun";

const NAME = "mission-control";
const APP = realpathSync(import.meta.dir);
const PORT = Bun.env.PORTLESS_PORT || "1355";
const URL_BASE = `https://${NAME}.localhost:${PORT}`;
const HELIUM = "/Applications/Helium.app/Contents/MacOS/Helium";
const STOP_SECONDS = 30;
const PID_FILE = join(
	Bun.env.XDG_CACHE_HOME || join(homedir(), ".cache"),
	NAME,
	"server.pid",
);

const USAGE = `usage: mission-control serve | stop | open [PR]
  PR is a GitHub URL, repo#123 or repo 123`;

function fail(message: string): never {
	console.error(message);
	process.exit(1);
}

// portless signs with its own CA, which the system does not trust.
async function get(path: string, init: RequestInit = {}) {
	return fetch(`${URL_BASE}${path}`, {
		...init,
		signal: AbortSignal.timeout(3000),
		tls: { rejectUnauthorized: false },
	});
}

async function up() {
	try {
		return (await get("/theme.css")).ok;
	} catch {
		return false;
	}
}

async function needServer() {
	if (!(await up()))
		fail(
			`${NAME} is not running at ${URL_BASE}. Start it: mission-control serve`,
		);
}

// Runs the server behind portless, in a process group of its own, so stop
// ends portless and the bun server under it. The packages the lockfile
// names install first, so the server never runs on stale ones. Offline,
// bun's fallback install covers what it can.
async function serve() {
	if (await up()) fail(`${NAME} already runs at ${URL_BASE}`);
	const child = spawn(
		"sh",
		[
			"-c",
			'bun install --cwd "$1" --frozen-lockfile --ignore-scripts --silent; exec portless "$2" bun run --install=fallback "$1/server.ts"',
			"sh",
			APP,
			NAME,
		],
		{ stdio: "inherit", detached: true },
	);
	mkdirSync(join(PID_FILE, ".."), { recursive: true });
	writeFileSync(PID_FILE, String(child.pid));
	// Ctrl-C reaches this process only, since the server has its own group.
	for (const signal of ["SIGINT", "SIGTERM"] as const)
		process.on(signal, () => {
			try {
				process.kill(-(child.pid as number), "SIGTERM");
			} catch {}
		});
	const code = await new Promise<number>((done) =>
		child.on("exit", (exitCode) => done(exitCode ?? 0)),
	);
	rmSync(PID_FILE, { force: true });
	process.exit(code);
}

async function stop() {
	let group: number;
	try {
		group = Number(readFileSync(PID_FILE, "utf8"));
		process.kill(-group, "SIGTERM");
	} catch {
		if (await up()) fail(`${NAME} runs, but serve did not start it`);
		return;
	}
	for (let i = 0; i < STOP_SECONDS; i++) {
		if (!(await up())) {
			rmSync(PID_FILE, { force: true });
			return;
		}
		await Bun.sleep(1000);
	}
	fail(`${NAME} did not stop within ${STOP_SECONDS}s`);
}

// The page as an app window, without tabs or an address bar, in Helium.
// Without Helium, in the default browser.
async function openWindow(path = "/") {
	const url = `${URL_BASE}${path}`;
	if (existsSync(HELIUM)) {
		spawn(HELIUM, [`--app=${url}`], {
			stdio: "ignore",
			detached: true,
		}).unref();
		return;
	}
	const opener = process.platform === "darwin" ? "open" : "xdg-open";
	await $`${opener} ${url}`.quiet();
}

// A pull request from a GitHub URL, repo#123 or repo 123.
function parsePR(words: string[]) {
	const text = words.join(" ").trim();
	const match =
		text.match(/github\.com\/[^/]+\/([^/]+)\/pull\/(\d+)/) ??
		text.match(/^([\w.-]+)[#\s]+(\d+)$/);
	return match ? { repo: match[1], number: Number(match[2]) } : null;
}

// Shows a pull request in every open page. Without an open page, it opens
// one at the pull request.
async function open(words: string[]) {
	await needServer();
	if (words.length === 0) {
		await openWindow();
		return;
	}
	const pr = parsePR(words);
	if (!pr) fail(USAGE);
	const res = await get("/api/open", {
		method: "POST",
		headers: { "content-type": "application/json" },
		body: JSON.stringify(pr),
	});
	const answer = (await res.json()) as { pages?: number; error?: string };
	if (!res.ok) fail(answer.error ?? `HTTP ${res.status}`);
	if (!answer.pages) {
		await openWindow(`/pr/${pr.repo}/${pr.number}`);
		console.log(`opened ${pr.repo}#${pr.number} in a new window`);
		return;
	}
	console.log(
		`showing ${pr.repo}#${pr.number} in ${answer.pages} open page(s)`,
	);
}

const [command, ...rest] = process.argv.slice(2);
if (command === "serve") await serve();
else if (command === "stop") await stop();
else if (command === "open") await open(rest);
else fail(USAGE);
