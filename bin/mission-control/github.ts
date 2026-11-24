// Reads the team's members and their open pull requests from GitHub.
import { graphql } from "@octokit/graphql";
import type { RawPR, ReviewEvent } from "./model.ts";

const REST = "https://api.github.com";
// GitHub lists at most 3000 files of a pull request, 100 to a page.
const FILE_PAGES = 30;

// Pages of 100 with check and comment fields time out at GitHub (HTTP 502),
// so each author's search pages through 30 at a time.
const PAGE = 30;

const PR_FIELDS = `
  number title url isDraft createdAt updatedAt headRefName headRefOid
  additions deletions changedFiles
  reviewDecision
  author { login }
  repository { name }
  labels(first: 20) { nodes { name color } }
  commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
  latestReviews(first: 20) { nodes { author { login } state submittedAt } }
  comments(last: 30) { nodes { body } }
  reviews(last: 20) { nodes { body } }`;

const PR_QUERY = `
query($q: String!, $after: String) {
  search(type: ISSUE, query: $q, first: ${PAGE}, after: $after) {
    pageInfo { hasNextPage endCursor }
    nodes { ... on PullRequest { ${PR_FIELDS} } }
  }
}`;

const ONE_PR_QUERY = `
query($org: String!, $repo: String!, $number: Int!) {
  repository(owner: $org, name: $repo) {
    pullRequest(number: $number) { ${PR_FIELDS} bodyHTML }
  }
}`;

const MEMBERS_QUERY = `
query($org: String!, $team: String!) {
  organization(login: $org) { team(slug: $team) {
    members(first: 100) { nodes { login } }
  } }
}`;

type SearchResult = {
	search: {
		pageInfo: { hasNextPage: boolean; endCursor: string | null };
		nodes: RawPR[];
	};
};

export function client(token: string) {
	return graphql.defaults({ headers: { authorization: `token ${token}` } });
}

export type Client = ReturnType<typeof client>;

export async function teamMembers(
	gh: Client,
	org: string,
	team: string,
): Promise<string[]> {
	const result = await gh<{
		organization: { team: { members: { nodes: { login: string }[] } } | null };
	}>(MEMBERS_QUERY, { org, team });
	const found = result.organization.team;
	if (!found) throw new Error(`GitHub team ${org}/${team} not found`);
	return found.members.nodes.map((m) => m.login).sort(caseless);
}

export async function openPRs(
	gh: Client,
	org: string,
	author: string,
): Promise<RawPR[]> {
	const prs: RawPR[] = [];
	let after: string | null = null;
	do {
		const result: SearchResult = await gh<SearchResult>(PR_QUERY, {
			q: `is:pr is:open archived:false org:${org} author:${author}`,
			after,
		});
		prs.push(...result.search.nodes);
		after = result.search.pageInfo.hasNextPage
			? result.search.pageInfo.endCursor
			: null;
	} while (after);
	return prs;
}

export async function pullRequest(
	gh: Client,
	org: string,
	repo: string,
	number: number,
): Promise<(RawPR & { bodyHTML: string }) | null> {
	const result = await gh<{
		repository: { pullRequest: (RawPR & { bodyHTML: string }) | null } | null;
	}>(ONE_PR_QUERY, { org, repo, number });
	return result.repository?.pullRequest ?? null;
}

export type RestFile = {
	filename: string;
	previous_filename?: string;
	status: string;
	additions: number;
	deletions: number;
	patch?: string;
};

async function rest(token: string, path: string, accept: string) {
	return fetch(`${REST}${path}`, {
		headers: {
			authorization: `token ${token}`,
			accept,
			"x-github-api-version": "2022-11-28",
		},
	});
}

export async function prFiles(
	token: string,
	org: string,
	repo: string,
	number: number,
): Promise<RestFile[]> {
	const files: RestFile[] = [];
	for (let page = 1; page <= FILE_PAGES; page++) {
		const res = await rest(
			token,
			`/repos/${org}/${repo}/pulls/${number}/files?per_page=100&page=${page}`,
			"application/vnd.github+json",
		);
		if (!res.ok) throw new Error(`GitHub files: HTTP ${res.status}`);
		const batch = (await res.json()) as RestFile[];
		files.push(...batch);
		if (batch.length < 100) break;
	}
	return files;
}

// The repository's root .gitattributes at a commit, or "" without one.
export async function gitattributes(
	token: string,
	org: string,
	repo: string,
	sha: string,
): Promise<string> {
	const res = await rest(
		token,
		`/repos/${org}/${repo}/contents/.gitattributes?ref=${sha}`,
		"application/vnd.github.raw+json",
	);
	if (res.status === 404) return "";
	if (!res.ok) throw new Error(`GitHub .gitattributes: HTTP ${res.status}`);
	return res.text();
}

export async function viewerLogin(gh: Client): Promise<string> {
	const result = await gh<{ viewer: { login: string } }>(
		"query { viewer { login } }",
	);
	return result.viewer.login;
}

// Posts a review on the given commit. GitHub refuses it when the commit is
// not in the pull request.
export async function postReview(
	token: string,
	org: string,
	repo: string,
	number: number,
	review: { event: ReviewEvent; body: string; commitId: string },
): Promise<{ status: number; state: string | null; message: string | null }> {
	const res = await fetch(
		`${REST}/repos/${org}/${repo}/pulls/${number}/reviews`,
		{
			method: "POST",
			headers: {
				authorization: `token ${token}`,
				accept: "application/vnd.github+json",
				"content-type": "application/json",
				"x-github-api-version": "2022-11-28",
			},
			body: JSON.stringify({
				event: review.event,
				body: review.body,
				commit_id: review.commitId,
			}),
		},
	);
	const json = (await res.json().catch(() => ({}))) as {
		state?: string;
		message?: string;
	};
	return {
		status: res.status,
		state: json.state ?? null,
		message: json.message ?? null,
	};
}

export function caseless(a: string, b: string) {
	return a.localeCompare(b, undefined, { sensitivity: "base" });
}
