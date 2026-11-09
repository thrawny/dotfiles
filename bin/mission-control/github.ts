// Reads the team's members and their open pull requests from GitHub.
import { graphql } from "@octokit/graphql";
import type { RawPR } from "./model.ts";

// Pages of 100 with check and comment fields time out at GitHub (HTTP 502),
// so each author's search pages through 30 at a time.
const PAGE = 30;

const PR_QUERY = `
query($q: String!, $after: String) {
  search(type: ISSUE, query: $q, first: ${PAGE}, after: $after) {
    pageInfo { hasNextPage endCursor }
    nodes { ... on PullRequest {
      number title url isDraft createdAt updatedAt headRefName headRefOid
      additions deletions changedFiles
      reviewDecision
      author { login }
      repository { name }
      labels(first: 20) { nodes { name color } }
      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
      latestReviews(first: 20) { nodes { author { login } state submittedAt } }
      comments(last: 30) { nodes { body } }
      reviews(last: 20) { nodes { body } }
    } }
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

export function caseless(a: string, b: string) {
	return a.localeCompare(b, undefined, { sensitivity: "base" });
}
