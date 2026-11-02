import { describe, expect, test } from "bun:test";
import { parseJiraProjects, render } from "./render.ts";

const url = "https://jira.example/browse/";
const link = (key: string) => `href="https://jira.example/browse/${key}"`;

async function html(markdown: string, projects?: string[]) {
	const result = await render(`---\ntitle: T\n---\n${markdown}`, "t.md", {
		jira: { url, projects },
	});
	return result.html;
}

describe("Jira key links", () => {
	test("links keys in prose, headings and lists", async () => {
		const out = await html(
			"## Fix ABC-12\n\nSee ABC-1, and (DEF-22).\n\n- feat(ABC-3): x\n",
		);
		for (const key of ["ABC-12", "ABC-1", "DEF-22", "ABC-3"])
			expect(out).toContain(`${link(key)} class="jira"`);
	});

	test("leaves code, fences, d2, raw HTML and existing links alone", async () => {
		const out = await html(
			[
				"Inline `ABC-1` code.",
				"```\nABC-2\n```",
				"```d2\nABC-3 -> ABC-4\n```",
				"[ABC-5](https://other.example/) and <https://other.example/ABC-6>",
				'<a href="https://other.example/">ABC-7</a> then ABC-8',
				"<div>ABC-9</div>",
				"![ABC-10](img.png)",
				"path/ABC-11 and xABC-12 and ABC-13x",
			].join("\n\n"),
		);
		for (const n of [1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13])
			expect(out).not.toContain(link(`ABC-${n}`));
		expect(out).toContain(link("ABC-8"));
	});

	test("matches only the configured projects", async () => {
		const out = await html("ABC-1, UTF-8 and SHA-256", ["ABC"]);
		expect(out).toContain(link("ABC-1"));
		expect(out).not.toContain(link("UTF-8"));
		expect(out).not.toContain(link("SHA-256"));
	});

	test("is off without the option", async () => {
		const result = await render("ABC-1", "t.md");
		expect(result.html).not.toContain('class="jira"');
	});

	test("rejects a lowercase project key", () => {
		expect(() => parseJiraProjects("ABC,def")).toThrow();
		expect(parseJiraProjects(" ABC , DEF ")).toEqual(["ABC", "DEF"]);
	});
});
