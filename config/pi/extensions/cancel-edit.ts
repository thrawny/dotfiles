import {
	CustomEditor,
	type ExtensionAPI,
	type ExtensionContext,
	type SessionEntry,
} from "@earendil-works/pi-coding-agent";
import type { EditorComponent } from "@earendil-works/pi-tui";

// Escape before the first tool restores a text-only prompt for editing.
// Rewind leaves the abandoned attempt in saved history, not in active context.
const COMMAND = "cancel-edit";

type EditorFactory = NonNullable<
	ReturnType<ExtensionContext["ui"]["getEditorComponent"]>
>;

type Attempt = {
	text: string;
	sessionId: string;
	parentId: string | null;
	valid: boolean;
	turns: number;
	starts: number;
};

type InterruptEditor = EditorComponent & { onEscape?: () => void };

function supportsInterrupt(editor: EditorComponent): editor is InterruptEditor {
	return (
		"onEscape" in editor &&
		(editor.onEscape === undefined || typeof editor.onEscape === "function")
	);
}

// Wrap the native interrupt callback only while the editor handles a key.
// Autocomplete, modal editors, and dialogs retain ownership of their Escape.
export function wrapInterrupt(
	editor: InterruptEditor,
	interrupt: () => boolean,
): void {
	const handleInput = editor.handleInput.bind(editor);
	editor.handleInput = (data) => {
		const fallback = editor.onEscape;
		editor.onEscape = () => {
			if (!interrupt()) fallback?.();
		};
		try {
			handleInput(data);
		} finally {
			editor.onEscape = fallback;
		}
	};
}

function promptEntry(
	ctx: ExtensionContext,
	attempt: Attempt,
): SessionEntry | undefined {
	const branch = ctx.sessionManager.getBranch();
	const parentIndex =
		attempt.parentId === null
			? -1
			: branch.findIndex((entry) => entry.id === attempt.parentId);
	if (attempt.parentId !== null && parentIndex === -1) return;
	const entries = branch.slice(parentIndex + 1);
	const users = entries.filter(
		(entry) => entry.type === "message" && entry.message.role === "user",
	);
	if (users.length !== 1) return;
	// Do not rewind tools, retries, or additional work appended during abort.
	const assistants = entries.filter(
		(entry) => entry.type === "message" && entry.message.role === "assistant",
	);
	if (assistants.length > 1) return;
	if (
		entries.some(
			(entry) =>
				entry.type === "message" && entry.message.role === "toolResult",
		)
	)
		return;
	if (
		assistants.some(
			(entry) =>
				entry.type === "message" &&
				entry.message.role === "assistant" &&
				entry.message.stopReason !== "aborted",
		)
	)
		return;
	return users[0];
}

export default function cancelEditExtension(pi: ExtensionAPI) {
	let draft: string | undefined;
	let attempt: Attempt | undefined;
	let pending: Attempt | undefined;
	let installedFactory: EditorFactory | undefined;
	let previousFactory: EditorFactory | undefined;
	let currentContext: ExtensionContext | undefined;

	function invalidate() {
		draft = undefined;
		if (attempt) attempt.valid = false;
		if (pending) pending.valid = false;
	}

	function canRestore(ctx: ExtensionContext, candidate: Attempt): boolean {
		return (
			candidate.valid &&
			candidate.sessionId === ctx.sessionManager.getSessionId() &&
			!ctx.hasPendingMessages() &&
			ctx.ui.getEditorText() === ""
		);
	}

	function interrupt(ctx: ExtensionContext): boolean {
		if (pending) return true; // Repeated Escape must not open the history picker.
		if (!attempt || ctx.isIdle() || !canRestore(ctx, attempt)) return false;
		pending = attempt;
		// Shortcuts lack navigation methods. Dispatch a command to get a fresh
		// command context; Pi handles this locally, without a model request.
		pi.sendUserMessage(`/${COMMAND}`, { expandPromptTemplates: true });
		return true;
	}

	pi.registerCommand(COMMAND, {
		description: "Cancel an early text-only response and restore its prompt",
		handler: async (_args, ctx) => {
			const candidate = pending ?? attempt;
			if (
				!candidate ||
				ctx.mode !== "tui" ||
				ctx.isIdle() ||
				!canRestore(ctx, candidate)
			) {
				pending = undefined;
				// An Escape-triggered command may race with incoming input or tools.
				if (!ctx.isIdle()) ctx.abort();
				return;
			}
			pending = candidate;
			try {
				ctx.abort();
				await ctx.waitForIdle();
				if (!canRestore(ctx, candidate)) return;
				const target = promptEntry(ctx, candidate);
				if (!target) return;
				// navigateTree treats the current leaf as a no-op. An abort before
				// the assistant starts can leave the user message as that leaf.
				if (ctx.sessionManager.getLeafId() === target.id) {
					pi.appendEntry(COMMAND, { promptId: target.id });
				}
				const result = await ctx.navigateTree(target.id, { summarize: false });
				if (
					result.cancelled ||
					!ctx.isIdle() ||
					candidate.sessionId !== ctx.sessionManager.getSessionId()
				)
					return;
				const restored =
					target.type === "message" && target.message.role === "user"
						? typeof target.message.content === "string"
							? target.message.content
							: target.message.content
									.filter((part) => part.type === "text")
									.map((part) => part.text)
									.join("")
						: "";
				// Prefer the original input over expanded templates, but never
				// overwrite text typed while an async navigation hook was running.
				if (
					ctx.ui.getEditorText() === "" ||
					ctx.ui.getEditorText() === restored
				) {
					ctx.ui.setEditorText(candidate.text);
				}
			} catch (error) {
				ctx.ui.notify(
					`Could not restore prompt: ${error instanceof Error ? error.message : String(error)}`,
					"error",
				);
			} finally {
				candidate.valid = false;
				if (pending === candidate) pending = undefined;
			}
		},
	});

	pi.on("input", (event, ctx) => {
		invalidate();
		if (
			ctx.mode === "tui" &&
			event.source === "interactive" &&
			ctx.isIdle() &&
			!event.streamingBehavior &&
			!event.images?.length
		)
			draft = event.text;
	});
	pi.on("before_agent_start", (event, ctx) => {
		const text = draft;
		invalidate();
		attempt =
			text !== undefined && !event.images?.length
				? {
						text,
						sessionId: ctx.sessionManager.getSessionId(),
						parentId: ctx.sessionManager.getLeafId(),
						valid: true,
						turns: 0,
						starts: 0,
					}
				: undefined;
	});
	pi.on("agent_start", () => {
		if (attempt && ++attempt.starts > 1) invalidate();
	});
	pi.on("turn_start", () => {
		if (attempt && ++attempt.turns > 1) invalidate();
	});
	pi.on("tool_call", () => {
		invalidate();
	});
	pi.on("tool_execution_start", () => {
		invalidate();
	});
	pi.on("user_bash", () => {
		invalidate();
	});
	pi.on("message_end", (event) => {
		if (
			event.message.role === "assistant" &&
			event.message.stopReason !== "aborted"
		)
			invalidate();
	});
	pi.on("session_tree", () => {
		invalidate();
	});
	pi.on("session_compact", () => {
		invalidate();
	});
	pi.on("session_start", (_event, ctx) => {
		invalidate();
		attempt = undefined;
		pending = undefined;
		currentContext = ctx;
		if (ctx.mode !== "tui") return;
		const current = ctx.ui.getEditorComponent();
		if (current === installedFactory && installedFactory) return;
		previousFactory = current;
		const base = current;
		installedFactory = (tui, theme, keys) => {
			const editor =
				base?.(tui, theme, keys) ?? new CustomEditor(tui, theme, keys);
			if (supportsInterrupt(editor))
				wrapInterrupt(editor, () =>
					currentContext ? interrupt(currentContext) : false,
				);
			return editor;
		};
		ctx.ui.setEditorComponent(installedFactory);
	});
	pi.on("session_shutdown", (_event, ctx) => {
		invalidate();
		pending = undefined;
		currentContext = undefined;
		if (installedFactory && ctx.ui.getEditorComponent() === installedFactory) {
			ctx.ui.setEditorComponent(previousFactory);
		}
	});
}
