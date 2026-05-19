import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";
import {
	effectiveArguments,
	expandArguments,
	expandCommandFile,
	formatExpandedCommandDisplay,
} from "../extensions/commands.ts";

describe("command argument defaults", () => {
	it("uses default arguments when invocation arguments are empty", () => {
		expect(effectiveArguments("", "now")).toBe("now");
		expect(effectiveArguments("   ", "now")).toBe("now");
	});

	it("keeps invocation arguments when provided", () => {
		expect(effectiveArguments("120", "now")).toBe("120");
	});

	it("expands templates with effective default arguments", () => {
		const args = effectiveArguments("", "now");
		expect(expandArguments("wait=$1 all=$ARGUMENTS", args)).toBe(
			"wait=now all=now",
		);
	});

	it("reads a command file and expands default arguments end-to-end", () => {
		const dir = mkdtempSync(path.join(tmpdir(), "pi-command-test-"));
		const filePath = path.join(dir, "mock.md");
		writeFileSync(
			filePath,
			[
				"---",
				"description: Mock default argument command",
				"default-arguments: now",
				"---",
				"arg=$1",
				"all=$ARGUMENTS",
				"conditional={{#if ARGUMENTS}}yes: $ARGUMENTS{{/if}}",
				'shell=!`printf cwd:%s $(basename "$PWD")`',
			].join("\n"),
		);

		const result = expandCommandFile(filePath, "", dir);

		expect(result.command.name).toBe("mock");
		expect(result.command.defaultArguments).toBe("now");
		expect(result.effectiveArgs).toBe("now");
		expect(result.expanded).toBe(
			[
				"arg=now",
				"all=now",
				"conditional=yes: now",
				`shell=cwd:${path.basename(dir)}`,
			].join("\n"),
		);
	});
});

describe("command prompt display formatting", () => {
	it("keeps expanded markdown raw for the custom renderer", () => {
		expect(
			formatExpandedCommandDisplay(
				"/gc",
				["Context", "", "  indented line", "```", "nested fence"].join("\n"),
			),
		).toBe(
			["/gc", "", "Context", "", "  indented line", "```", "nested fence"].join(
				"\n",
			),
		);
	});
});
