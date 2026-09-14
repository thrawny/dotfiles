import { EventEmitter } from "node:events";
import { afterEach, expect, it, vi } from "vitest";

const requests = vi.hoisted(
	() => [] as Array<{ params: { state?: string; message?: string } }>,
);
vi.mock("node:net", () => ({
	default: {
		createConnection: () => {
			const socket = new EventEmitter() as EventEmitter & {
				write: (text: string) => void;
				destroy: () => void;
			};
			socket.destroy = () => {};
			socket.write = (text) => {
				requests.push(JSON.parse(text));
				queueMicrotask(() => socket.emit("data", "{}"));
			};
			queueMicrotask(() => socket.emit("connect"));
			return socket;
		},
	},
}));

afterEach(() => {
	vi.unstubAllEnvs();
	vi.resetModules();
	requests.length = 0;
});

it("reports questionnaire blocking and restores other blockers and working state", async () => {
	vi.stubEnv("HERDR_ENV", "1");
	vi.stubEnv("HERDR_SOCKET_PATH", "/unused-test-socket");
	vi.stubEnv("HERDR_PANE_ID", "w1:p1");
	const handlers = new Map<string, (...args: any[]) => unknown>();
	const events = new EventEmitter();
	const { default: extension } =
		await import("../extensions/herdr-agent-state.js");
	extension({
		on: (name: string, handler: (...args: any[]) => unknown) =>
			handlers.set(name, handler),
		events,
	});
	const ctx = { mode: "tui", isIdle: () => false };
	await handlers.get("session_start")!({}, ctx);
	const flush = () => new Promise((resolve) => setTimeout(resolve, 0));
	await flush();
	expect(requests.at(-1)?.params.state).toBe("working");
	events.emit("rpiv:ask-user:blocked", { active: true });
	await flush();
	expect(requests.at(-1)?.params).toMatchObject({
		state: "blocked",
		message: "Waiting for your answer",
	});
	events.emit("herdr:blocked", { active: true, label: "Approval" });
	events.emit("rpiv:ask-user:blocked", { active: false });
	await flush();
	expect(requests.at(-1)?.params).toMatchObject({
		state: "blocked",
		message: "Approval",
	});
	events.emit("herdr:blocked", { active: false });
	await flush();
	expect(requests.at(-1)?.params.state).toBe("working");
	await handlers.get("agent_settled")!({}, { isIdle: () => true });
	await flush();
	expect(requests.at(-1)?.params.state).toBe("idle");
});
