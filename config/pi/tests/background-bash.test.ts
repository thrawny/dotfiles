import { expect, it } from "vitest";
import { backgroundSessionName } from "../extensions/background-bash.ts";

it("generates a fresh zmx session name even when call IDs repeat", () => {
	const first = backgroundSessionName("call-reused", "just check");
	const second = backgroundSessionName("call-reused", "just check");

	expect(first).not.toBe(second);
});
