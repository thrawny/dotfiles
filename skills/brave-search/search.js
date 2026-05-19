#!/usr/bin/env bun
// @ts-nocheck

import { Readability } from "@mozilla/readability";
import { mkdir, open, readFile, unlink, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import { DOMParser } from "linkedom";
import TurndownService from "turndown";
import { gfm } from "turndown-plugin-gfm";

const args = process.argv.slice(2);

const contentIndex = args.indexOf("--content");
const fetchContent = contentIndex !== -1;
if (fetchContent) args.splice(contentIndex, 1);

let numResults = 5;
const nIndex = args.indexOf("-n");
if (nIndex !== -1 && args[nIndex + 1]) {
	numResults = parseInt(args[nIndex + 1], 10);
	args.splice(nIndex, 2);
}

// Parse country option
let country = "US";
const countryIndex = args.indexOf("--country");
if (countryIndex !== -1 && args[countryIndex + 1]) {
	country = args[countryIndex + 1].toUpperCase();
	args.splice(countryIndex, 2);
}

// Parse freshness option
let freshness = null;
const freshnessIndex = args.indexOf("--freshness");
if (freshnessIndex !== -1 && args[freshnessIndex + 1]) {
	freshness = args[freshnessIndex + 1];
	args.splice(freshnessIndex, 2);
}

const query = args.join(" ");

if (!query) {
	console.log("Usage: search.js <query> [-n <num>] [--content] [--country <code>] [--freshness <period>]");
	console.log("\nOptions:");
	console.log("  -n <num>              Number of results (default: 5, max: 20)");
	console.log("  --content             Fetch readable content as markdown");
	console.log("  --country <code>      Country code for results (default: US)");
	console.log("  --freshness <period>  Filter by time: pd (day), pw (week), pm (month), py (year)");
	console.log("\nEnvironment:");
	console.log("  BRAVE_API_KEY         Required. Your Brave Search API key.");
	console.log("\nExamples:");
	console.log('  search.js "javascript async await"');
	console.log('  search.js "rust programming" -n 10');
	console.log('  search.js "climate change" --content');
	console.log('  search.js "news today" --freshness pd');
	process.exit(1);
}

const apiKey = process.env.BRAVE_API_KEY;
if (!apiKey) {
	console.error("Error: BRAVE_API_KEY environment variable is required.");
	console.error("Get your API key at: https://api-dashboard.search.brave.com/app/keys");
	process.exit(1);
}

const RATE_LIMIT_STATE = `${process.env.XDG_CACHE_HOME || `${process.env.HOME}/.cache`}/brave-search/rate-limit.json`;
const RATE_LIMIT_LOCK = `${RATE_LIMIT_STATE}.lock`;
const MIN_INTERVAL_MS = parseInt(process.env.BRAVE_SEARCH_MIN_INTERVAL_MS || "1100", 10);

function sleep(ms) {
	return new Promise(resolve => setTimeout(resolve, ms));
}

async function acquireRateLimitLock() {
	await mkdir(dirname(RATE_LIMIT_STATE), { recursive: true });
	while (true) {
		try {
			return await open(RATE_LIMIT_LOCK, "wx");
		} catch (error) {
			if (error.code !== "EEXIST") throw error;
			await sleep(50);
		}
	}
}

async function waitForBraveRateLimit() {
	const lock = await acquireRateLimitLock();
	try {
		let lastRequestAt = 0;
		try {
			const state = JSON.parse(await readFile(RATE_LIMIT_STATE, "utf8"));
			lastRequestAt = Number(state.lastRequestAt) || 0;
		} catch {}

		const now = Date.now();
		const waitMs = Math.max(0, lastRequestAt + MIN_INTERVAL_MS - now);
		if (waitMs > 0) await sleep(waitMs);

		await writeFile(RATE_LIMIT_STATE, JSON.stringify({ lastRequestAt: Date.now() }), "utf8");
	} finally {
		await lock.close();
		await unlink(RATE_LIMIT_LOCK).catch(() => {});
	}
}

function isRateLimited(response, errorText) {
	return response.status === 429 || errorText.includes("RATE_LIMITED") || errorText.includes('"rate_limited"');
}

async function fetchBraveResults(query, numResults, country, freshness) {
	const params = new URLSearchParams({
		q: query,
		count: Math.min(numResults, 20).toString(),
		country: country,
	});

	if (freshness) {
		params.append("freshness", freshness);
	}

	const url = `https://api.search.brave.com/res/v1/web/search?${params.toString()}`;

	let response;
	let errorText = "";
	for (let attempt = 1; attempt <= 3; attempt++) {
		await waitForBraveRateLimit();
		response = await fetch(url, {
			headers: {
				"Accept": "application/json",
				"Accept-Encoding": "gzip",
				"X-Subscription-Token": apiKey,
			}
		});

		if (response.ok) break;

		errorText = await response.text();
		if (!isRateLimited(response, errorText) || attempt === 3) {
			throw new Error(`HTTP ${response.status}: ${response.statusText}\n${errorText}`);
		}
		await sleep(MIN_INTERVAL_MS * attempt);
	}

	const data = await response.json();

	const results = [];

	// Extract web results
	if (data.web && data.web.results) {
		for (const result of data.web.results) {
			if (results.length >= numResults) break;

			results.push({
				title: result.title || "",
				link: result.url || "",
				snippet: result.description || "",
				age: result.age || result.page_age || "",
			});
		}
	}

	return results;
}

function htmlToMarkdown(html) {
	const turndown = new TurndownService({ headingStyle: "atx", codeBlockStyle: "fenced" });
	turndown.use(gfm);
	turndown.addRule("removeEmptyLinks", {
		filter: (node) => node.nodeName === "A" && !node.textContent?.trim(),
		replacement: () => "",
	});
	return turndown
		.turndown(html)
		.replace(/\[\\?\[\s*\\?\]\]\([^)]*\)/g, "")
		.replace(/ +/g, " ")
		.replace(/\s+,/g, ",")
		.replace(/\s+\./g, ".")
		.replace(/\n{3,}/g, "\n\n")
		.trim();
}

async function fetchPageContent(url) {
	try {
		const response = await fetch(url, {
			headers: {
				"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
				"Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
			},
			signal: AbortSignal.timeout(10000),
		});

		if (!response.ok) {
			return `(HTTP ${response.status})`;
		}

		const html = await response.text();
		const doc = new DOMParser().parseFromString(html, "text/html");
		doc.URL = url;
		const reader = new Readability(doc);
		const article = reader.parse();

		if (article && article.content) {
			return htmlToMarkdown(article.content).substring(0, 5000);
		}

		// Fallback: try to get main content
		const body = new DOMParser().parseFromString(html, "text/html");
		body.URL = url;
		body.querySelectorAll("script, style, noscript, nav, header, footer, aside").forEach(el => el.remove());
		const main = body.querySelector("main, article, [role='main'], .content, #content") || body.body;
		const text = main?.textContent || "";

		if (text.trim().length > 100) {
			return text.trim().substring(0, 5000);
		}

		return "(Could not extract content)";
	} catch (e) {
		return `(Error: ${e.message})`;
	}
}

// Main
try {
	const results = await fetchBraveResults(query, numResults, country, freshness);

	if (results.length === 0) {
		console.error("No results found.");
		process.exit(0);
	}

	if (fetchContent) {
		for (const result of results) {
			result.content = await fetchPageContent(result.link);
		}
	}

	for (let i = 0; i < results.length; i++) {
		const r = results[i];
		console.log(`--- Result ${i + 1} ---`);
		console.log(`Title: ${r.title}`);
		console.log(`Link: ${r.link}`);
		if (r.age) {
			console.log(`Age: ${r.age}`);
		}
		console.log(`Snippet: ${r.snippet}`);
		if (r.content) {
			console.log(`Content:\n${r.content}`);
		}
		console.log("");
	}
} catch (e) {
	console.error(`Error: ${e.message}`);
	process.exit(1);
}
