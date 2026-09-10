import { visibleWidth } from "@earendil-works/pi-tui";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import {
	isCodexFastEnabled,
	layoutStatusLine,
	modelDisplayName,
	normalizeExtensionStatuses,
	partitionExtensionStatuses,
	resolveGitInfo,
} from "../extensions/status-line.ts";

describe("status line model names", () => {
	it.each([
		["gpt-6-astra", "Astra 6"],
		["gpt-5.6-sol", "Sol 5.6"],
		["gpt-5.6-terra", "Terra 5.6"],
		["gpt-5.6-luna", "Luna 5.6"],
		["unknown-model", "unknown-model"],
	])("displays %s as %s", (id, name) => {
		expect(modelDisplayName(id)).toBe(name);
	});
});

describe("status line extension statuses", () => {
	it("shows pi-openai-fast fast status once", () => {
		expect(normalizeExtensionStatuses(["fast"])).toEqual(["fast"]);
	});

	it("extracts fast from pi-codex-conversion status", () => {
		expect(
			normalizeExtensionStatuses(["Codex adapter V: low • PATH mode • fast"]),
		).toEqual(["fast", "Codex adapter V: low • PATH mode"]);
	});

	it("deduplicates fast across extensions", () => {
		expect(
			normalizeExtensionStatuses([
				"fast",
				"Codex adapter V: low • PATH mode • fast",
			]),
		).toEqual(["fast", "Codex adapter V: low • PATH mode"]);
	});

	it("promotes the background task count out of trailing statuses", () => {
		expect(
			partitionExtensionStatuses(["fast", "\x1b[32m 2\x1b[0m", "voice…"]),
		).toEqual({
			backgroundStatus: " 2",
			remaining: ["fast", "voice…"],
		});
	});

	it("refreshes branch and dirty state directly from git", async () => {
		const dir = mkdtempSync(join(tmpdir(), "pi-statusline-git-"));
		try {
			execFileSync("git", ["init", "--quiet", "--initial-branch", "first"], {
				cwd: dir,
			});
			expect((await resolveGitInfo(dir))?.branch).toBe("first");
			expect((await resolveGitInfo(dir))?.symbols).toBe("");

			execFileSync("git", ["symbolic-ref", "HEAD", "refs/heads/second"], {
				cwd: dir,
			});
			expect((await resolveGitInfo(dir))?.branch).toBe("second");

			writeFileSync(join(dir, "untracked.txt"), "hi");
			expect((await resolveGitInfo(dir))?.symbols).toBe("?");
		} finally {
			rmSync(dir, { recursive: true, force: true });
		}
	});

	it("returns null outside a git repository", async () => {
		const dir = mkdtempSync(join(tmpdir(), "pi-statusline-nogit-"));
		try {
			expect(await resolveGitInfo(dir)).toBeNull();
		} finally {
			rmSync(dir, { recursive: true, force: true });
		}
	});

	it("reads fast from pi-codex-conversion config", () => {
		const dir = mkdtempSync(join(tmpdir(), "pi-statusline-"));
		const configPath = join(dir, "pi-codex-conversion.json");
		try {
			writeFileSync(configPath, JSON.stringify({ openai: { fast: true } }));
			expect(isCodexFastEnabled(configPath)).toBe(true);

			writeFileSync(configPath, JSON.stringify({ openai: { fast: false } }));
			expect(isCodexFastEnabled(configPath)).toBe(false);
		} finally {
			rmSync(dir, { recursive: true, force: true });
		}
	});
});

describe("adaptive footer layout", () => {
	const primary = ["Astra 6", "24.3k 9%"];
	const branch = " retire/t-2482-aggregation-service ✘!?";
	const project = ["kanel-backend-3", branch, "🫧"];
	const statuses = "high • MCP: 1 server enabled";

	it("keeps a roomy terminal on one line", () => {
		const lines = layoutStatusLine(
			180,
			primary,
			project,
			statuses,
			"Implementing",
		);
		expect(lines).toHaveLength(1);
		expect(lines[0]).toContain(branch);
		expect(lines[0]).toContain("Implementing");
		expect(lines[0]).toContain(statuses);
	});

	it("splits crowded content by purpose without shortening the branch", () => {
		const lines = layoutStatusLine(
			100,
			primary,
			project,
			statuses,
			"Implementing",
		);
		expect(lines).toHaveLength(2);
		expect(lines[0]).toContain("Astra 6");
		expect(lines[0]).toContain(statuses);
		expect(lines[0]).not.toContain("kanel");
		expect(lines[1]).toContain(branch);
		expect(lines[1]).toContain("Implementing");
	});

	it("handles missing optional content", () => {
		expect(layoutStatusLine(80, primary, ["dotfiles"], "")).toHaveLength(1);
	});

	it("bounds both rows at every width, including ANSI and wide characters", () => {
		for (let width = 0; width <= 180; width++) {
			const lines = layoutStatusLine(
				width,
				["\x1b[36mAstra 6\x1b[0m", "24.3k 9%", " 2"],
				project,
				statuses,
				"作業 🫧 ".repeat(20),
			);
			expect(lines.length).toBeLessThanOrEqual(2);
			for (const line of lines)
				expect(visibleWidth(line)).toBeLessThanOrEqual(width);
		}
	});
});
