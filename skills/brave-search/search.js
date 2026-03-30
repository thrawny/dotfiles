#!/usr/bin/env bun
// @ts-nocheck

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

let country = "US";
const countryIndex = args.indexOf("--country");
if (countryIndex !== -1 && args[countryIndex + 1]) {
  country = args[countryIndex + 1].toUpperCase();
  args.splice(countryIndex, 2);
}

let freshness = null;
const freshnessIndex = args.indexOf("--freshness");
if (freshnessIndex !== -1 && args[freshnessIndex + 1]) {
  freshness = args[freshnessIndex + 1];
  args.splice(freshnessIndex, 2);
}

const query = args.join(" ");

if (!query) {
  console.log(
    "Usage: search.js <query> [-n <num>] [--content] [--country <code>] [--freshness <period>]",
  );
  console.log("\nOptions:");
  console.log("  -n <num>              Number of results (default: 5, max: 20)");
  console.log("  --content             Fetch readable content as markdown");
  console.log("  --country <code>      Country code for results (default: US)");
  console.log(
    "  --freshness <period>  Filter by time: pd (day), pw (week), pm (month), py (year)",
  );
  console.log("\nEnvironment:");
  console.log("  BRAVE_API_KEY         Required. Your Brave Search API key.");
  process.exit(1);
}

const apiKey = process.env.BRAVE_API_KEY;
if (!apiKey) {
  console.error("Error: BRAVE_API_KEY environment variable is required.");
  console.error("Get your API key at: https://api-dashboard.search.brave.com/app/keys");
  process.exit(1);
}

async function fetchBraveResults(query, numResults, country, freshness) {
  const params = new URLSearchParams({
    q: query,
    count: Math.min(numResults, 20).toString(),
    country,
  });

  if (freshness) params.append("freshness", freshness);

  const response = await fetch(
    `https://api.search.brave.com/res/v1/web/search?${params.toString()}`,
    {
      headers: {
        Accept: "application/json",
        "Accept-Encoding": "gzip",
        "X-Subscription-Token": apiKey,
      },
    },
  );

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`HTTP ${response.status}: ${response.statusText}\n${errorText}`);
  }

  const data = await response.json();
  const results = [];

  if (data.web?.results) {
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

function decodeHtmlEntities(text) {
  return text
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#x([0-9a-f]+);/gi, (_, hex) => String.fromCharCode(parseInt(hex, 16)))
    .replace(/&#(\d+);/g, (_, dec) => String.fromCharCode(parseInt(dec, 10)));
}

function stripTags(html) {
  return html
    .replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, " ")
    .replace(/<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>/gi, " ")
    .replace(/<noscript\b[^<]*(?:(?!<\/noscript>)<[^<]*)*<\/noscript>/gi, " ")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p>/gi, "\n\n")
    .replace(/<\/div>/gi, "\n")
    .replace(/<\/h[1-6]>/gi, "\n\n")
    .replace(/<li[^>]*>/gi, "\n- ")
    .replace(/<\/li>/gi, "")
    .replace(/<[^>]+>/g, " ");
}

function htmlToMarkdown(html) {
  return decodeHtmlEntities(stripTags(html))
    .replace(/[ \t]+/g, " ")
    .replace(/ *\n */g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function extractTitle(html) {
  const titleMatch = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  if (!titleMatch) return "";
  return decodeHtmlEntities(stripTags(titleMatch[1])).trim();
}

function extractMainHtml(html) {
  const cleaned = html
    .replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, " ")
    .replace(/<style\b[^<]*(?:(?!<\/style>)<[^<]*)*<\/style>/gi, " ")
    .replace(/<noscript\b[^<]*(?:(?!<\/noscript>)<[^<]*)*<\/noscript>/gi, " ");

  const candidates = [
    /<main\b[^>]*>([\s\S]*?)<\/main>/i,
    /<article\b[^>]*>([\s\S]*?)<\/article>/i,
    /<div\b[^>]*(?:id|class)=["'][^"']*(?:content|main|article|post|doc-body)[^"']*["'][^>]*>([\s\S]*?)<\/div>/i,
    /<body\b[^>]*>([\s\S]*?)<\/body>/i,
  ];

  for (const pattern of candidates) {
    const match = cleaned.match(pattern);
    if (match?.[1]) return match[1];
  }

  return cleaned;
}

async function fetchPageContent(url) {
  try {
    const response = await fetch(url, {
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
        Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      },
      signal: AbortSignal.timeout(10000),
    });

    if (!response.ok) return `(HTTP ${response.status})`;

    const html = await response.text();
    const title = extractTitle(html);
    const mainHtml = extractMainHtml(html);
    const body = htmlToMarkdown(mainHtml).substring(0, 5000);

    if (!body) return "(Could not extract content)";
    return title ? `# ${title}\n\n${body}` : body;
  } catch (e) {
    return `(Error: ${e.message})`;
  }
}

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
    if (r.age) console.log(`Age: ${r.age}`);
    console.log(`Snippet: ${r.snippet}`);
    if (r.content) console.log(`Content:\n${r.content}`);
    console.log("");
  }
} catch (e) {
  console.error(`Error: ${e.message}`);
  process.exit(1);
}
