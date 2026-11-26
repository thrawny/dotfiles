import { describe, expect, test } from "bun:test";
import {
	botReviewState,
	checkReviewWrite,
	GENERATED_GLOBS,
	isGenerated,
	jiraKey,
	matchesGlob,
	parseGitattributes,
	type RawPR,
	type ReviewWrite,
	toPR,
} from "./model.ts";

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
		mergedAt: null,
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

const opts = {
	readyLabel: "ready-for-review",
	jiraProjects: [],
	reviewMarker: "bot:review",
	now,
};

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

describe("botReviewState", () => {
	test("takes the highest review number and checks it against the head", () => {
		const bodies = [
			"<!-- bot:review n=2 sha=abc1234 verdict=lgtm passes=review -->",
			"<!-- bot:review n=1 sha=0000000 verdict=findings -->",
		];
		expect(botReviewState(bodies, "abc1234def", "bot:review")).toEqual({
			n: 2,
			verdict: "lgtm",
			stale: false,
		});
		expect(botReviewState(bodies, "fff9999", "bot:review")).toEqual({
			n: 2,
			verdict: "lgtm",
			stale: true,
		});
	});
	test("returns null without a marker", () => {
		expect(
			botReviewState(
				["looks good", "<!-- bot:docs-check -->"],
				"abc",
				"bot:review",
			),
		).toBeNull();
	});
});

describe("toPR bucket", () => {
	const ready = { nodes: [{ name: "ready-for-review", color: "0e8a16" }] };
	test("a merged PR is merged, whatever its review and CI say", () => {
		const pr = toPR(
			raw({
				mergedAt: daysAgo(0),
				createdAt: daysAgo(40),
				reviewDecision: "CHANGES_REQUESTED",
			}),
			opts,
		);
		expect(pr.bucket).toBe("merged");
		expect(pr.ageLevel).toBe("ok");
	});
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

describe("generated files", () => {
	const file = (path: string, patch: string | null = null) => ({
		path,
		prevPath: null,
		patch,
	});
	test("globs match as codediff.nvim matches them", () => {
		for (const path of [
			"generated/a.ts",
			"pkg/gen/b.go",
			"api/v1/c.pb.go",
			"d.gen.go",
			"x/zz_generated.deepcopy.go",
		])
			expect(matchesGlob(path, GENERATED_GLOBS)).toBe(true);
		for (const path of ["generator/a.ts", "pkg/agen/b.go", "pb.go.txt"])
			expect(matchesGlob(path, GENERATED_GLOBS)).toBe(false);
		expect(matchesGlob("a/b.lock", ["/*.lock"])).toBe(false);
		expect(matchesGlob("b.lock", ["/*.lock"])).toBe(true);
	});
	test(".gitattributes: the last matching line wins", () => {
		const rules = parseGitattributes(`
# vendored
api/** linguist-generated=true
api/keep.ts -linguist-generated
"quoted dir/" linguist-generated
docs/ linguist-generated text
*.md diff=markdown
`);
		expect(isGenerated(file("api/x.ts"), rules)).toBe(true);
		expect(isGenerated(file("api/keep.ts"), rules)).toBe(false);
		expect(isGenerated(file("docs/a/b.md"), rules)).toBe(true);
		expect(isGenerated(file("README.md"), rules)).toBe(false);
	});
	test("a renamed file counts by its old path too", () => {
		expect(
			isGenerated({ path: "src/a.go", prevPath: "gen/a.go", patch: null }, []),
		).toBe(true);
	});
	test("the header counts only when the patch shows line 1", () => {
		const header = "// Code generated by protoc. DO NOT EDIT.";
		expect(
			isGenerated(file("a.ts", `@@ -0,0 +1,2 @@\n+${header}\n+x`), []),
		).toBe(true);
		expect(
			isGenerated(file("a.ts", `@@ -1,3 +1,3 @@\n ${header}\n-a\n+b`), []),
		).toBe(true);
		expect(
			isGenerated(file("a.ts", `@@ -40,3 +40,3 @@\n ${header}\n-a\n+b`), []),
		).toBe(false);
		expect(
			isGenerated(file("a.ts", `@@ -1,2 +0,0 @@\n-${header}\n-x`), []),
		).toBe(false);
	});
});

describe("checkReviewWrite", () => {
	const write = (patch: Partial<ReviewWrite> = {}): ReviewWrite => ({
		contentType: "application/json",
		origin: "https://mc.localhost:1355",
		token: "secret",
		request: { event: "APPROVE", body: "", commitId: "abc" },
		expectedToken: "secret",
		allowedOrigins: ["https://mc.localhost:1355"],
		viewer: "bob",
		members: ["Alice", "bob"],
		author: "alice",
		headSha: "abc",
		...patch,
	});
	const status = (w: ReviewWrite) => {
		const verdict = checkReviewWrite(w);
		return verdict.ok ? 200 : verdict.status;
	};
	test("an empty approve of a teammate's head commit passes", () => {
		expect(checkReviewWrite(write())).toEqual({
			ok: true,
			event: "APPROVE",
			body: "",
			commitId: "abc",
		});
	});
	test("only the page may write", () => {
		expect(status(write({ token: null }))).toBe(403);
		expect(status(write({ token: "guess" }))).toBe(403);
		expect(status(write({ origin: "https://evil.example" }))).toBe(403);
		expect(status(write({ origin: null }))).toBe(403);
		expect(status(write({ contentType: "text/plain" }))).toBe(415);
	});
	test("only known events, and comments need a body", () => {
		const req = (request: unknown) => status(write({ request }));
		expect(req({ event: "DISMISS", body: "", commitId: "abc" })).toBe(400);
		expect(req({ event: "COMMENT", body: "  ", commitId: "abc" })).toBe(400);
		expect(req({ event: "REQUEST_CHANGES", body: "x", commitId: "abc" })).toBe(
			200,
		);
		expect(req(null)).toBe(400);
	});
	test("never the viewer's own PR or a PR outside the team", () => {
		expect(status(write({ author: "BOB" }))).toBe(403);
		expect(status(write({ author: "mallory" }))).toBe(403);
	});
	test("refuses when the head moved since the page loaded", () => {
		expect(status(write({ headSha: "def" }))).toBe(409);
	});
});
