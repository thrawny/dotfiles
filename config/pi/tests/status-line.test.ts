import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import {
	isCodexFastEnabled,
	normalizeExtensionStatuses,
	partitionExtensionStatuses,
	resolveGitBranch,
} from "../extensions/status-line.ts";

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

	it("refreshes the branch directly from git metadata", async () => {
		const dir = mkdtempSync(join(tmpdir(), "pi-statusline-git-"));
		try {
			execFileSync("git", ["init", "--quiet", "--initial-branch", "first"], {
				cwd: dir,
			});
			expect(await resolveGitBranch(dir)).toBe("first");

			execFileSync("git", ["symbolic-ref", "HEAD", "refs/heads/second"], {
				cwd: dir,
			});
			expect(await resolveGitBranch(dir)).toBe("second");
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
