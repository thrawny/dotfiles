import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import {
	findGitRoot,
	findLocalInstructionPaths,
	loadLocalInstructions,
} from "../extensions/agents-local.ts";

describe("AGENTS.local.md discovery", () => {
	it("loads local instruction files from git root to cwd", () => {
		const root = mkdtempSync(path.join(tmpdir(), "pi-agents-local-test-"));
		mkdirSync(path.join(root, ".git"));
		mkdirSync(path.join(root, "packages", "app"), { recursive: true });
		writeFileSync(path.join(root, "AGENTS.local.md"), "root guidance");
		writeFileSync(
			path.join(root, "packages", "app", "AGENTS.local.md"),
			"app guidance",
		);

		const cwd = path.join(root, "packages", "app");

		expect(findGitRoot(cwd)).toBe(root);
		expect(findLocalInstructionPaths(cwd)).toEqual([
			path.join(root, "AGENTS.local.md"),
			path.join(root, "packages", "app", "AGENTS.local.md"),
		]);
		expect(loadLocalInstructions(cwd).map((file) => file.content)).toEqual([
			"root guidance",
			"app guidance",
		]);
	});

	it("falls back to CLAUDE.local.md when AGENTS.local.md is absent", () => {
		const root = mkdtempSync(path.join(tmpdir(), "pi-agents-local-test-"));
		mkdirSync(path.join(root, ".git"));
		mkdirSync(path.join(root, "packages", "app"), { recursive: true });
		writeFileSync(path.join(root, "CLAUDE.local.md"), "root fallback");
		writeFileSync(
			path.join(root, "packages", "app", "CLAUDE.local.md"),
			"app fallback",
		);

		const cwd = path.join(root, "packages", "app");

		expect(findLocalInstructionPaths(cwd)).toEqual([
			path.join(root, "CLAUDE.local.md"),
			path.join(root, "packages", "app", "CLAUDE.local.md"),
		]);
		expect(loadLocalInstructions(cwd).map((file) => file.content)).toEqual([
			"root fallback",
			"app fallback",
		]);
	});

	it("prefers AGENTS.local.md over CLAUDE.local.md in the same directory", () => {
		const root = mkdtempSync(path.join(tmpdir(), "pi-agents-local-test-"));
		mkdirSync(path.join(root, ".git"));
		writeFileSync(path.join(root, "AGENTS.local.md"), "agent guidance");
		writeFileSync(path.join(root, "CLAUDE.local.md"), "claude guidance");

		expect(findLocalInstructionPaths(root)).toEqual([
			path.join(root, "AGENTS.local.md"),
		]);
		expect(loadLocalInstructions(root).map((file) => file.content)).toEqual([
			"agent guidance",
		]);
	});

	it("falls back to cwd when outside a git repository", () => {
		const parent = mkdtempSync(path.join(tmpdir(), "pi-agents-local-test-"));
		const cwd = path.join(parent, "project");
		mkdirSync(cwd);
		writeFileSync(path.join(parent, "AGENTS.local.md"), "parent guidance");
		writeFileSync(path.join(cwd, "AGENTS.local.md"), "cwd guidance");

		expect(findGitRoot(cwd)).toBeUndefined();
		expect(findLocalInstructionPaths(cwd)).toEqual([
			path.join(cwd, "AGENTS.local.md"),
		]);
	});
});
