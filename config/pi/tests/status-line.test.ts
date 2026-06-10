import { describe, expect, it } from "vitest";
import { normalizeExtensionStatuses } from "../extensions/status-line.ts";

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
});
