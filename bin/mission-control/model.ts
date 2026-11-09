// Pure functions that turn GitHub's pull request data into what the page
// shows. Shared by the server and the browser, so no Bun or DOM APIs here.

export type RawPR = {
	number: number;
	title: string;
	url: string;
	isDraft: boolean;
	createdAt: string;
	updatedAt: string;
	headRefName: string;
	headRefOid: string;
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
	| "draft";
export type AgeLevel = "ok" | "warn" | "old";

export type Tono = {
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
	jiraKey: string | null;
	ci: CI;
	reviewed: Reviewed;
	reviewers: { login: string; state: string }[];
	labels: { name: string; color: string }[];
	ready: boolean;
	tono: Tono | null;
	bucket: Bucket;
	ageDays: number;
	ageLevel: AgeLevel;
	approvedIdle: boolean;
};

export const BUCKETS: { id: Bucket; title: string }[] = [
	{ id: "changes", title: "Changes requested" },
	{ id: "failing", title: "CI failing" },
	{ id: "waiting", title: "Waiting for review" },
	{ id: "approved", title: "Approved, not merged" },
	{ id: "open", title: "Open, not marked ready" },
	{ id: "draft", title: "Draft" },
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

// The newest tono review marker in the PR's comments and reviews. tono
// numbers its reviews, so the highest number is the newest. The review is
// stale when its commit is no longer the PR's head.
export function tonoState(bodies: string[], headOid: string): Tono | null {
	let best: Tono | null = null;
	const marker = /<!--\s*tono:review\b([^>]*?)-->/g;
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
	opts: { readyLabel: string; jiraProjects: string[]; now: number },
): PR {
	const author = raw.author?.login ?? "ghost";
	const reviews = raw.latestReviews.nodes.filter(
		(r) => r.author && r.author.login !== author && r.state !== "DISMISSED",
	);
	const reviewed = reviewedState(reviews.map((r) => r.state));
	const ci = ciState(raw.commits.nodes[0]?.commit.statusCheckRollup?.state);
	const labels = raw.labels.nodes;
	const ready = labels.some((l) => l.name === opts.readyLabel);
	const changes =
		raw.reviewDecision === "CHANGES_REQUESTED" ||
		(raw.reviewDecision === null && reviewed === "changes");
	const approved =
		raw.reviewDecision === "APPROVED" ||
		(raw.reviewDecision === null && reviewed === "approved");
	const ageDays = (opts.now - Date.parse(raw.createdAt)) / DAY;
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
		jiraKey: jiraKey(raw.title, raw.headRefName, opts.jiraProjects),
		ci,
		reviewed,
		reviewers: reviews.map((r) => ({
			login: r.author?.login ?? "",
			state: r.state,
		})),
		labels,
		ready,
		tono: tonoState(
			[...raw.comments.nodes, ...raw.reviews.nodes].map((c) => c.body),
			raw.headRefOid,
		),
		bucket: raw.isDraft
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
		ageLevel: ageLevel(ageDays),
		approvedIdle:
			approved &&
			approvedAt > 0 &&
			opts.now - approvedAt > APPROVED_IDLE_DAYS * DAY,
	};
}
