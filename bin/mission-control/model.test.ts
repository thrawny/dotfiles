import { describe, expect, test } from "bun:test";
import { jiraKey, type RawPR, tonoState, toPR } from "./model.ts";

const now = Date.parse("2026-11-09T12:00:00Z");
const daysAgo = (d: number) => new Date(now - d * 86400000).toISOString();

function raw(patch: Partial<RawPR> = {}): RawPR {
	return {
		number: 1,
		title: "feat: add foo",
		url: "https://github.com/acme/widgets/pull/1",
		isDraft: false,
		createdAt: daysAgo(1),
		updatedAt: daysAgo(1),
		headRefName: "feat/foo",
		headRefOid: "abc1234def",
		additions: 10,
		deletions: 2,
		changedFiles: 1,
		reviewDecision: "REVIEW_REQUIRED",
		author: { login: "alice" },
		repository: { name: "widgets" },
		labels: { nodes: [] },
		commits: {
			nodes: [{ commit: { statusCheckRollup: { state: "SUCCESS" } } }],
		},
		latestReviews: { nodes: [] },
		comments: { nodes: [] },
		reviews: { nodes: [] },
		...patch,
	};
}

const opts = { readyLabel: "ready-for-review", jiraProjects: [], now };

describe("jiraKey", () => {
	test("prefers the title, then the branch", () => {
		expect(jiraKey("feat(ABC-12): x", "abc-99-y", ["ABC"])).toBe("ABC-12");
		expect(jiraKey("feat: x", "feat/abc-99-y", ["ABC"])).toBe("ABC-99");
	});
	test("without projects, a lower-case branch word is not a key", () => {
		expect(jiraKey("chore: deps", "update-2", [])).toBeNull();
		expect(jiraKey("fix(ABC-7): y", "x", [])).toBe("ABC-7");
	});
	test("other projects' upper-case keys still count", () => {
		expect(jiraKey("fix(XYZ-686): y", "fix/xyz-686", ["ABC"])).toBe("XYZ-686");
		expect(jiraKey("chore: deps", "fix/xyz-686", ["ABC"])).toBeNull();
	});
});

describe("tonoState", () => {
	test("takes the highest review number and checks it against the head", () => {
		const bodies = [
			"<!-- tono:review n=2 sha=abc1234 verdict=lgtm passes=review -->",
			"<!-- tono:review n=1 sha=0000000 verdict=findings -->",
		];
		expect(tonoState(bodies, "abc1234def")).toEqual({
			n: 2,
			verdict: "lgtm",
			stale: false,
		});
		expect(tonoState(bodies, "fff9999")).toEqual({
			n: 2,
			verdict: "lgtm",
			stale: true,
		});
	});
	test("returns null without a marker", () => {
		expect(
			tonoState(["looks good", "<!-- tono:docs-check -->"], "abc"),
		).toBeNull();
	});
});

describe("toPR bucket", () => {
	const ready = { nodes: [{ name: "ready-for-review", color: "0e8a16" }] };
	test("draft wins over everything", () => {
		expect(
			toPR(raw({ isDraft: true, reviewDecision: "CHANGES_REQUESTED" }), opts)
				.bucket,
		).toBe("draft");
	});
	test("changes requested comes before failing CI", () => {
		const pr = raw({
			reviewDecision: "CHANGES_REQUESTED",
			commits: {
				nodes: [{ commit: { statusCheckRollup: { state: "FAILURE" } } }],
			},
		});
		expect(toPR(pr, opts).bucket).toBe("changes");
	});
	test("an approved PR with failing CI is failing", () => {
		const pr = raw({
			reviewDecision: "APPROVED",
			commits: {
				nodes: [{ commit: { statusCheckRollup: { state: "ERROR" } } }],
			},
		});
		expect(toPR(pr, opts).bucket).toBe("failing");
	});
	test("ready and not approved is waiting; not ready is open", () => {
		expect(toPR(raw({ labels: ready }), opts).bucket).toBe("waiting");
		expect(toPR(raw(), opts).bucket).toBe("open");
	});
	test("a repo without required reviews counts an approval", () => {
		const pr = raw({
			reviewDecision: null,
			latestReviews: {
				nodes: [
					{
						author: { login: "bob" },
						state: "APPROVED",
						submittedAt: daysAgo(3),
					},
				],
			},
		});
		const out = toPR(pr, opts);
		expect(out.bucket).toBe("approved");
		expect(out.approvedIdle).toBe(true);
	});
	test("the author's own review does not count", () => {
		const pr = raw({
			reviewDecision: null,
			latestReviews: {
				nodes: [
					{
						author: { login: "alice" },
						state: "APPROVED",
						submittedAt: daysAgo(1),
					},
				],
			},
		});
		expect(toPR(pr, opts).reviewed).toBe("none");
	});
	test("age levels", () => {
		expect(toPR(raw({ createdAt: daysAgo(8) }), opts).ageLevel).toBe("warn");
		expect(toPR(raw({ createdAt: daysAgo(15) }), opts).ageLevel).toBe("old");
	});
});
