// Pure functions that turn GitHub's pull request data into what the page
// shows. Shared by the server and the browser, so no Bun or DOM APIs here.

export type RawPR = {
	number: number;
	title: string;
	url: string;
	isDraft: boolean;
	createdAt: string;
	updatedAt: string;
	// When the pull request was merged, or null while it is open.
	mergedAt: string | null;
	headRefName: string;
	headRefOid: string;
	additions: number;
	deletions: number;
	changedFiles: number;
	reviewDecision: "APPROVED" | "CHANGES_REQUESTED" | "REVIEW_REQUIRED" | null;
	author: { login: string } | null;
	repository: { name: string };
	labels: { nodes: { name: string; color: string }[] };
	commits: {
		nodes: { commit: { statusCheckRollup: { state: string } | null } }[];
	};
	latestReviews: {
		nodes: {
			author: { login: string } | null;
			state: string;
			submittedAt: string | null;
		}[];
	};
	comments: { nodes: { body: string }[] };
	reviews: { nodes: { body: string }[] };
};

export type CI = "success" | "failure" | "pending" | "none";
export type Reviewed = "approved" | "changes" | "commented" | "none";
export type Bucket =
	| "changes"
	| "failing"
	| "waiting"
	| "approved"
	| "open"
	| "draft"
	| "merged";
export type AgeLevel = "ok" | "warn" | "old";

// The newest review a review bot left on a pull request, read from the
// marker it writes into its comments.
export type BotReview = {
	n: number;
	verdict: string;
	stale: boolean;
};

export type PR = {
	id: string;
	repo: string;
	number: number;
	title: string;
	url: string;
	author: string;
	draft: boolean;
	createdAt: string;
	updatedAt: string;
	mergedAt: string | null;
	jiraKey: string | null;
	ci: CI;
	reviewed: Reviewed;
	reviewers: { login: string; state: string }[];
	labels: { name: string; color: string }[];
	ready: boolean;
	botReview: BotReview | null;
	bucket: Bucket;
	ageDays: number;
	ageLevel: AgeLevel;
	approvedIdle: boolean;
	additions: number;
	deletions: number;
	files: number;
};

export const BUCKETS: { id: Bucket; title: string }[] = [
	{ id: "changes", title: "Changes requested" },
	{ id: "failing", title: "CI failing" },
	{ id: "waiting", title: "Waiting for review" },
	{ id: "approved", title: "Approved, not merged" },
	{ id: "open", title: "Open, not marked ready" },
	{ id: "draft", title: "Draft" },
	{ id: "merged", title: "Merged" },
];

const DAY = 24 * 60 * 60 * 1000;
export const WARN_DAYS = 7;
export const OLD_DAYS = 14;
export const APPROVED_IDLE_DAYS = 2;

// The first Jira key in the title, else in the branch. Any upper-case key
// counts. Keys of the configured projects also count in lower case, since
// branches often are, without reading a branch such as `update-2` as a key.
export function jiraKey(
	title: string,
	branch: string,
	projects: string[],
): string | null {
	const patterns = [
		...(projects.length
			? [
					new RegExp(
						`\\b(${projects.map(escapeRegExp).join("|")})-(\\d+)\\b`,
						"i",
					),
				]
			: []),
		/\b([A-Z][A-Z0-9]+)-(\d+)\b/,
	];
	for (const text of [title, branch]) {
		for (const pattern of patterns) {
			const match = text.match(pattern);
			if (match) return `${match[1].toUpperCase()}-${match[2]}`;
		}
	}
	return null;
}

function escapeRegExp(text: string) {
	return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function ciState(state: string | null | undefined): CI {
	switch (state) {
		case "SUCCESS":
			return "success";
		case "FAILURE":
		case "ERROR":
			return "failure";
		case "PENDING":
		case "EXPECTED":
			return "pending";
		default:
			return "none";
	}
}

// The newest review bot marker in the PR's comments and reviews. A marker is
// an HTML comment such as `<!-- bot:review n=2 sha=abc1234 verdict=lgtm -->`,
// where `bot:review` is the configured marker name. The bot numbers its
// reviews, so the highest number is the newest. The review is stale when its
// commit is no longer the PR's head. Without a marker name, there is no bot.
export function botReviewState(
	bodies: string[],
	headOid: string,
	markerName: string,
): BotReview | null {
	if (!markerName) return null;
	let best: BotReview | null = null;
	const escaped = markerName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
	const marker = new RegExp(`<!--\\s*${escaped}\\b([^>]*?)-->`, "g");
	for (const body of bodies) {
		for (const match of body.matchAll(marker)) {
			const fields = Object.fromEntries(
				[...match[1].matchAll(/(\w+)=(\S+)/g)].map((m) => [m[1], m[2]]),
			);
			const n = Number(fields.n);
			if (!Number.isFinite(n)) continue;
			if (best && n < best.n) continue;
			const sha = fields.sha ?? "";
			best = {
				n,
				verdict: fields.verdict ?? "",
				stale: !sha || !headOid.startsWith(sha),
			};
		}
	}
	return best;
}

// The name the page shows for the review bot: the marker name up to its
// colon, so `bot:review` shows as `bot`.
export function botName(markerName: string): string {
	return markerName.split(":")[0];
}

export function reviewedState(states: string[]): Reviewed {
	if (states.includes("CHANGES_REQUESTED")) return "changes";
	if (states.includes("APPROVED")) return "approved";
	if (states.includes("COMMENTED")) return "commented";
	return "none";
}

export function ageLevel(days: number): AgeLevel {
	if (days > OLD_DAYS) return "old";
	if (days > WARN_DAYS) return "warn";
	return "ok";
}

export function toPR(
	raw: RawPR,
	opts: {
		readyLabel: string;
		jiraProjects: string[];
		reviewMarker: string;
		now: number;
	},
): PR {
	const author = raw.author?.login ?? "ghost";
	const reviews = raw.latestReviews.nodes.filter(
		(r) => r.author && r.author.login !== author && r.state !== "DISMISSED",
	);
	const reviewed = reviewedState(reviews.map((r) => r.state));
	const ci = ciState(raw.commits.nodes[0]?.commit.statusCheckRollup?.state);
	// The line counts replace size labels, such as `size/L`.
	const labels = raw.labels.nodes.filter((l) => !/^size\//i.test(l.name));
	const ready = labels.some((l) => l.name === opts.readyLabel);
	const changes =
		raw.reviewDecision === "CHANGES_REQUESTED" ||
		(raw.reviewDecision === null && reviewed === "changes");
	const approved =
		raw.reviewDecision === "APPROVED" ||
		(raw.reviewDecision === null && reviewed === "approved");
	const merged = raw.mergedAt !== null;
	// A merged pull request's age counts from its merge, so the age filter
	// picks recent merges.
	const ageDays = (opts.now - Date.parse(raw.mergedAt ?? raw.createdAt)) / DAY;
	const approvedAt = Math.max(
		0,
		...reviews
			.filter((r) => r.state === "APPROVED" && r.submittedAt)
			.map((r) => Date.parse(r.submittedAt as string)),
	);
	return {
		id: `${raw.repository.name}#${raw.number}`,
		repo: raw.repository.name,
		number: raw.number,
		title: raw.title,
		url: raw.url,
		author,
		draft: raw.isDraft,
		createdAt: raw.createdAt,
		updatedAt: raw.updatedAt,
		mergedAt: raw.mergedAt,
		jiraKey: jiraKey(raw.title, raw.headRefName, opts.jiraProjects),
		ci,
		reviewed,
		reviewers: reviews.map((r) => ({
			login: r.author?.login ?? "",
			state: r.state,
		})),
		labels,
		ready,
		botReview: botReviewState(
			[...raw.comments.nodes, ...raw.reviews.nodes].map((c) => c.body),
			raw.headRefOid,
			opts.reviewMarker,
		),
		bucket: merged
			? "merged"
			: raw.isDraft
				? "draft"
				: changes
					? "changes"
					: ci === "failure"
						? "failing"
						: approved
							? "approved"
							: ready
								? "waiting"
								: "open",
		ageDays,
		// A merged pull request is done, so its age is no warning.
		ageLevel: merged ? "ok" : ageLevel(ageDays),
		additions: raw.additions,
		deletions: raw.deletions,
		files: raw.changedFiles,
		approvedIdle:
			!merged &&
			approved &&
			approvedAt > 0 &&
			opts.now - approvedAt > APPROVED_IDLE_DAYS * DAY,
	};
}

// A changed file in a pull request, as the review page shows it. `patch` is
// GitHub's unified diff of the file, or null when GitHub leaves it out, as
// for a binary file, a pure rename or a diff too large to send.
export type PRFile = {
	path: string;
	prevPath: string | null;
	status: string;
	additions: number;
	deletions: number;
	patch: string | null;
	generated: boolean;
};

// The content of an added file, from its patch, which holds every line.
export function newFileText(file: PRFile): string | null {
	if (file.status !== "added" || !file.patch) return null;
	return file.patch
		.split("\n")
		.filter((line) => line.startsWith("+"))
		.map((line) => line.slice(1))
		.join("\n");
}

export const isMarkdown = (path: string) => /\.(md|markdown)$/i.test(path);

// Generated files start collapsed. The rules port codediff.nvim's
// (lua/codediff/ui/explorer/filter.lua) so a PR collapses the same files in
// the browser as in Neovim: these globs, the root .gitattributes and Go's
// generated-code header.
export const GENERATED_GLOBS = [
	"**/generated/**",
	"**/gen/**",
	"*.gen.go",
	"*_gen.go",
	"*_generated.go",
	"*.pb.go",
	"*.pb.gw.go",
	"zz_generated.*",
];

// One glob as an anchored pattern. `**/` stands for one or more directories
// here; globPatterns adds the variants with it dropped, for zero.
function globPattern(glob: string): RegExp {
	let out = "";
	for (let i = 0; i < glob.length; i++) {
		const c = glob[i];
		if (glob.startsWith("**/", i)) {
			out += ".*/";
			i += 2;
		} else if (glob.startsWith("**", i)) {
			out += ".*";
			i += 1;
		} else if (c === "*") out += "[^/]*";
		else if (c === "?") out += ".";
		else out += escapeRegExp(c);
	}
	return new RegExp(`^${out}$`, "s");
}

// Every pattern a glob can match: each `**/` once kept and once dropped.
function globPatterns(glob: string): RegExp[] {
	const count = glob.split("**/").length - 1;
	if (count === 0 || count > 8) return [globPattern(glob)];
	let variants = [glob];
	for (let n = 0; n < count; n++)
		variants = variants.flatMap((v) => [
			v.replace("**/", "\u0002"),
			v.replace("**/", ""),
		]);
	return variants.map((v) => globPattern(v.replaceAll("\u0002", "**/")));
}

// gitignore-style matching: a glob without a slash matches the base name
// anywhere, a glob with one matches the whole path, and a leading slash
// anchors it to the root.
export function matchesGlob(path: string, globs: string[]): boolean {
	const base = path.slice(path.lastIndexOf("/") + 1);
	return globs.some((glob) => {
		if (glob.startsWith("/"))
			return globPatterns(glob.slice(1)).some((p) => p.test(path));
		const target = glob.includes("/") ? path : base;
		return globPatterns(glob).some((p) => p.test(target));
	});
}

export type GitattributesRule = { pattern: string; generated: boolean };

// The .gitattributes lines that set or unset linguist-generated. Quoted
// patterns are skipped, and a trailing slash means the whole directory.
export function parseGitattributes(text: string): GitattributesRule[] {
	const rules: GitattributesRule[] = [];
	for (const raw of text.split("\n")) {
		const line = raw.trim();
		if (!line || line.startsWith("#")) continue;
		const [first, ...attrs] = line.split(/\s+/);
		if (first.startsWith('"') || !attrs.length) continue;
		const pattern = first.endsWith("/") ? `${first}**` : first;
		let generated: boolean | null = null;
		for (const attr of attrs) {
			if (attr === "linguist-generated" || attr === "linguist-generated=true")
				generated = true;
			else if (
				attr === "-linguist-generated" ||
				attr === "linguist-generated=false"
			)
				generated = false;
		}
		if (generated !== null) rules.push({ pattern, generated });
	}
	return rules;
}

// As in git, the last matching line wins.
export function gitattributesGenerated(
	path: string,
	rules: GitattributesRule[],
): boolean {
	let generated = false;
	for (const rule of rules)
		if (matchesGlob(path, [rule.pattern])) generated = rule.generated;
	return generated;
}

// Go's marker (https://go.dev/s/generatedcode), anywhere on a line of the
// file's first 4 KB, since other generators put it behind their own comment.
export function hasGeneratedHeader(head: string): boolean {
	return /Code generated [^\n]*? DO NOT EDIT/.test(head.slice(0, 4096));
}

// The start of the new file, if the patch shows its line 1. A patch that
// starts further down cannot show the header, so the check is skipped.
export function patchHead(patch: string): string | null {
	const lines = patch.split("\n");
	const header = lines[0]?.match(/^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/);
	if (header?.[1] !== "1" || header[2] === "0") return null;
	const head: string[] = [];
	for (const line of lines.slice(1)) {
		if (line.startsWith("@@")) break;
		if (line.startsWith("+") || line.startsWith(" ")) head.push(line.slice(1));
	}
	return head.join("\n");
}

export function isGenerated(
	file: { path: string; prevPath: string | null; patch: string | null },
	rules: GitattributesRule[],
): boolean {
	const byPath = (path: string) =>
		matchesGlob(path, GENERATED_GLOBS) || gitattributesGenerated(path, rules);
	if (byPath(file.path) || (file.prevPath && byPath(file.prevPath)))
		return true;
	const head = file.patch ? patchHead(file.patch) : null;
	return head !== null && hasGeneratedHeader(head);
}

// The change a reviewer reads: lines and files outside generated files,
// with the generated ones counted apart.
export function fileTotals(files: PRFile[]) {
	const own = files.filter((f) => !f.generated);
	const gen = files.filter((f) => f.generated);
	const sum = (list: PRFile[], key: "additions" | "deletions") =>
		list.reduce((n, f) => n + f[key], 0);
	return {
		files: own.length,
		additions: sum(own, "additions"),
		deletions: sum(own, "deletions"),
		generatedFiles: gen.length,
		generatedLines: sum(gen, "additions") + sum(gen, "deletions"),
	};
}

export const REVIEW_EVENTS = ["APPROVE", "REQUEST_CHANGES", "COMMENT"] as const;
export type ReviewEvent = (typeof REVIEW_EVENTS)[number];

export type ReviewWrite = {
	// What the page sent.
	contentType: string | null;
	origin: string | null;
	token: string | null;
	request: unknown;
	// What the server knows.
	expectedToken: string;
	allowedOrigins: string[];
	viewer: string;
	members: string[];
	author: string;
	headSha: string;
};

export type ReviewVerdict =
	| { ok: true; event: ReviewEvent; body: string; commitId: string }
	| { ok: false; status: number; reason: string };

// Whether the page may post this review. Only the page itself may write:
// it holds the startup token and runs on an allowed origin. The review goes
// on a team member's PR, never the viewer's own, and only on the commit the
// viewer read.
export function checkReviewWrite(w: ReviewWrite): ReviewVerdict {
	const refuse = (status: number, reason: string): ReviewVerdict => ({
		ok: false,
		status,
		reason,
	});
	if (!w.token || w.token !== w.expectedToken)
		return refuse(403, "bad or missing token");
	if (!w.origin || !w.allowedOrigins.includes(w.origin))
		return refuse(403, "origin not allowed");
	if (!w.contentType?.toLowerCase().startsWith("application/json"))
		return refuse(415, "body must be JSON");
	const request = (w.request ?? {}) as Record<string, unknown>;
	const { event, body, commitId } = request;
	if (!REVIEW_EVENTS.includes(event as ReviewEvent))
		return refuse(400, "unknown review event");
	if (typeof body !== "string") return refuse(400, "body must be a string");
	if (event !== "APPROVE" && !body.trim())
		return refuse(400, "a comment or change request needs a body");
	if (typeof commitId !== "string" || !commitId)
		return refuse(400, "missing commit");
	const same = (a: string, b: string) => a.toLowerCase() === b.toLowerCase();
	if (!w.members.some((m) => same(m, w.author)))
		return refuse(403, "not a team pull request");
	if (same(w.author, w.viewer))
		return refuse(403, "cannot review your own pull request");
	if (commitId !== w.headSha)
		return refuse(409, "the pull request has new commits; reload the page");
	return { ok: true, event: event as ReviewEvent, body, commitId };
}
