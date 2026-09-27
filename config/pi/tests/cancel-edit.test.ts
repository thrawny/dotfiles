import { SessionManager } from "@earendil-works/pi-coding-agent";
import { describe, expect, it, vi } from "vitest";
import cancelEditExtension, {
	wrapInterrupt,
} from "../extensions/cancel-edit.ts";

type Handler = (event: never, ctx: never) => unknown;
type Command = (args: string, ctx: never) => Promise<void>;

function assistant(stopReason = "aborted") {
	return {
		role: "assistant",
		content: [{ type: "text", text: "Starting..." }],
		api: "openai-responses",
		provider: "openai",
		model: "test",
		usage: {
			input: 0,
			output: 0,
			cacheRead: 0,
			cacheWrite: 0,
			totalTokens: 0,
			cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
		},
		stopReason,
		timestamp: Date.now(),
	};
}

function harness() {
	const events = new Map<string, Handler>();
	const commands = new Map<string, Command>();
	const session = SessionManager.inMemory();
	const savedParent = session.appendCustomEntry("previous-work", {});
	let editorText = "";
	let idle = true;
	let queued = false;
	let dispatch: Promise<void> | undefined;
	let waitHook: (() => Promise<void>) | undefined;
	let navigationHook: (() => Promise<void>) | undefined;
	let appendAssistant = true;
	let editorFactory: ((...args: never[]) => typeof editor) | undefined;
	const nativeInterrupt = vi.fn(() => {
		idle = true;
	});
	const editor = {
		onEscape: nativeInterrupt,
		getText: () => editorText,
		setText: (text: string) => {
			editorText = text;
		},
		render: () => [],
		handleInput(data: string) {
			if (data === "\x1b") this.onEscape();
			else editorText += data;
		},
	};
	const baseFactory = () => editor;
	editorFactory = baseFactory;
	const emit = async (name: string, event: unknown = {}) =>
		events.get(name)?.(event as never, ctx as never);
	const ui = {
		getEditorText: () => editorText,
		setEditorText: vi.fn((text: string) => {
			editorText = text;
		}),
		notify: vi.fn(),
		getEditorComponent: () => editorFactory,
		setEditorComponent: vi.fn((factory: typeof editorFactory) => {
			editorFactory = factory;
			factory?.();
		}),
	};
	const ctx = {
		mode: "tui",
		hasUI: true,
		ui,
		sessionManager: session,
		isIdle: () => idle,
		hasPendingMessages: () => queued,
		abort: vi.fn(),
		waitForIdle: vi.fn(async () => {
			await waitHook?.();
			if (appendAssistant) {
				const message = assistant();
				await emit("message_end", { message });
				session.appendMessage(message as never);
			}
			idle = true;
			await emit("agent_end", { messages: [] });
			await emit("agent_settled");
		}),
		navigateTree: vi.fn(async (id: string, _options: unknown) => {
			await navigationHook?.();
			const entry = session.getEntry(id)!;
			if (entry.parentId === null) session.resetLeaf();
			else session.branch(entry.parentId);
			await emit("session_tree", {});
			if (
				!editorText &&
				entry.type === "message" &&
				entry.message.role === "user"
			) {
				const content = entry.message.content;
				editorText =
					typeof content === "string"
						? content
						: content
								.filter((part) => part.type === "text")
								.map((part) => part.text)
								.join("");
			}
			return { cancelled: false };
		}),
	};
	const pi = {
		on(name: string, handler: Handler) {
			events.set(name, handler);
		},
		registerCommand(name: string, options: { handler: Command }) {
			commands.set(name, options.handler);
		},
		sendUserMessage: vi.fn((text: string, _options: unknown) => {
			dispatch = commands.get(text.slice(1))!("", ctx as never);
		}),
		appendEntry: vi.fn((type: string, data: unknown) =>
			session.appendCustomEntry(type, data),
		),
	};
	cancelEditExtension(pi as never);
	return {
		ctx,
		pi,
		ui,
		session,
		savedParent,
		editor,
		nativeInterrupt,
		emit,
		baseFactory,
		async start(
			text = "Original prompt",
			extra: Record<string, unknown> = {},
			expanded = text,
		) {
			await emit("session_start");
			await emit("input", { text, source: "interactive", ...extra });
			await emit("before_agent_start", { prompt: expanded });
			session.appendMessage({
				role: "user",
				content: expanded,
				timestamp: Date.now(),
			});
			idle = false;
			await emit("agent_start");
			await emit("turn_start", { turnIndex: 0 });
		},
		escape() {
			editor.handleInput("\x1b");
		},
		finish: () => dispatch,
		setQueued(value: boolean) {
			queued = value;
		},
		setIdle(value: boolean) {
			idle = value;
		},
		setWaitHook(hook: () => Promise<void>) {
			waitHook = hook;
		},
		setNavigationHook(hook: () => Promise<void>) {
			navigationHook = hook;
		},
		setAppendAssistant(value: boolean) {
			appendAssistant = value;
		},
	};
}

describe("cancel and edit", () => {
	it("rewinds an early cancel and restores the original, unexpanded input", async () => {
		const h = harness();
		await h.start("/template original", {}, "Expanded prompt");
		const targetId = h.session.getLeafId();
		h.escape();
		await h.finish();
		expect(h.pi.sendUserMessage).toHaveBeenCalledWith("/cancel-edit", {
			expandPromptTemplates: true,
		});
		expect(h.ctx.abort).toHaveBeenCalledOnce();
		expect(h.ctx.navigateTree).toHaveBeenCalledWith(targetId, {
			summarize: false,
		});
		expect(h.ui.getEditorText()).toBe("/template original");
		expect(h.session.getLeafId()).toBe(h.savedParent);
		expect(h.session.getEntry(targetId!)).toBeDefined();
		expect(h.nativeInterrupt).not.toHaveBeenCalled();
	});

	it("makes an unresponded user leaf navigable without deleting history", async () => {
		const h = harness();
		await h.start();
		h.setAppendAssistant(false);
		h.escape();
		await h.finish();
		expect(h.pi.appendEntry).toHaveBeenCalledOnce();
		expect(h.ctx.navigateTree).toHaveBeenCalledOnce();
		expect(h.ui.getEditorText()).toBe("Original prompt");
	});

	it.each([
		"tool_call",
		"tool_execution_start",
		"user_bash",
		"session_compact",
	])("uses normal cancellation after %s", async (event) => {
		const h = harness();
		await h.start();
		await h.emit(event);
		h.escape();
		expect(h.nativeInterrupt).toHaveBeenCalledOnce();
		expect(h.pi.sendUserMessage).not.toHaveBeenCalled();
	});

	it.each(["agent_start", "turn_start"])(
		"does not rewind a later %s",
		async (event) => {
			const h = harness();
			await h.start();
			await h.emit(event);
			h.escape();
			expect(h.nativeInterrupt).toHaveBeenCalledOnce();
		},
	);

	it.each(["stop", "error", "toolUse"])(
		"does not rewind a completed assistant message with reason %s",
		async (reason) => {
			const h = harness();
			await h.start();
			await h.emit("message_end", { message: assistant(reason) });
			h.escape();
			expect(h.nativeInterrupt).toHaveBeenCalledOnce();
		},
	);

	it.each([
		{ images: [{ type: "image", data: "test", mimeType: "image/png" }] },
		{ source: "extension" },
		{ source: "rpc" },
		{ streamingBehavior: "steer" },
		{ streamingBehavior: "followUp" },
	])("leaves unsupported input to normal cancellation: %j", async (extra) => {
		const h = harness();
		await h.start("prompt", extra);
		h.escape();
		expect(h.nativeInterrupt).toHaveBeenCalledOnce();
		expect(h.pi.sendUserMessage).not.toHaveBeenCalled();
	});

	it("does not replace an existing draft or queued messages", async () => {
		for (const setup of [
			(h: ReturnType<typeof harness>) => h.ui.setEditorText("new draft"),
			(h: ReturnType<typeof harness>) => h.setQueued(true),
		]) {
			const h = harness();
			await h.start();
			setup(h);
			h.escape();
			expect(h.nativeInterrupt).toHaveBeenCalledOnce();
			expect(h.pi.sendUserMessage).not.toHaveBeenCalled();
		}
	});

	it("consumes repeated Escape while cancellation is in flight", async () => {
		const h = harness();
		await h.start();
		let release!: () => void;
		const gate = new Promise<void>((resolve) => {
			release = resolve;
		});
		h.setWaitHook(() => gate);
		h.escape();
		h.escape();
		h.escape();
		expect(h.pi.sendUserMessage).toHaveBeenCalledOnce();
		expect(h.nativeInterrupt).not.toHaveBeenCalled();
		release();
		await h.finish();
	});

	it.each(["tool_call", "tool_execution_start", "input", "session_start"])(
		"abandons rewind if %s arrives during abort",
		async (event) => {
			const h = harness();
			await h.start();
			h.setWaitHook(async () => {
				await h.emit(event, { text: "next", source: "interactive" });
			});
			h.escape();
			await h.finish();
			expect(h.ctx.navigateTree).not.toHaveBeenCalled();
		},
	);

	it("preserves typing during abort", async () => {
		const h = harness();
		await h.start();
		h.setWaitHook(async () => {
			h.editor.handleInput("new draft");
		});
		h.escape();
		await h.finish();
		expect(h.ctx.navigateTree).not.toHaveBeenCalled();
		expect(h.ui.getEditorText()).toBe("new draft");
	});

	it("preserves typing during navigation", async () => {
		const h = harness();
		await h.start();
		h.setNavigationHook(async () => {
			h.editor.handleInput("new draft");
		});
		h.escape();
		await h.finish();
		expect(h.ui.getEditorText()).toBe("new draft");
	});

	it("does not rewind past an additional user message", async () => {
		const h = harness();
		await h.start();
		h.setWaitHook(async () => {
			h.session.appendMessage({
				role: "user",
				content: "another",
				timestamp: Date.now(),
			});
		});
		h.escape();
		await h.finish();
		expect(h.ctx.navigateTree).not.toHaveBeenCalled();
	});

	it("reports navigation errors and releases the Escape guard", async () => {
		const h = harness();
		await h.start();
		h.setNavigationHook(async () => {
			throw new Error("navigation failed");
		});
		h.escape();
		await h.finish();
		expect(h.ui.notify).toHaveBeenCalledWith(
			"Could not restore prompt: navigation failed",
			"error",
		);
		h.escape();
		expect(h.nativeInterrupt).toHaveBeenCalledOnce();
	});

	it("restores the previous editor factory on shutdown", async () => {
		const h = harness();
		await h.start();
		await h.emit("session_shutdown");
		expect(h.ui.getEditorComponent()).toBe(h.baseFactory);
	});

	it("does not install an editor outside TUI mode", async () => {
		const h = harness();
		h.ctx.mode = "rpc";
		await h.emit("session_start");
		expect(h.ui.setEditorComponent).not.toHaveBeenCalled();
	});
});

describe("native interrupt wrapper", () => {
	it("lets the editor decide whether Escape means interrupt or dismiss autocomplete", () => {
		const fallback = vi.fn();
		const interrupt = vi.fn(() => true);
		let autocomplete = true;
		const editor = {
			onEscape: fallback,
			handleInput() {
				if (autocomplete) autocomplete = false;
				else this.onEscape();
			},
		};
		wrapInterrupt(editor as never, interrupt);
		editor.handleInput();
		expect(interrupt).not.toHaveBeenCalled();
		editor.handleInput();
		expect(interrupt).toHaveBeenCalledOnce();
		expect(fallback).not.toHaveBeenCalled();
		expect(editor.onEscape).toBe(fallback);
	});

	it("uses the current native handler rather than capturing a stale one", () => {
		const fallback = vi.fn();
		const editor = {
			onEscape: vi.fn(),
			handleInput() {
				this.onEscape();
			},
		};
		wrapInterrupt(editor as never, () => false);
		editor.onEscape = fallback;
		editor.handleInput();
		expect(fallback).toHaveBeenCalledOnce();
	});
});
