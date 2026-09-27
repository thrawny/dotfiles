import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
	fauxAssistantMessage,
	fauxProvider,
	InMemoryCredentialStore,
} from "@earendil-works/pi-ai";
import {
	createAgentSession,
	DefaultResourceLoader,
	ModelRuntime,
	SessionManager,
	SettingsManager,
	type CustomEditor,
	type ExtensionUIContext,
} from "@earendil-works/pi-coding-agent";
import { matchesKey } from "@earendil-works/pi-tui";
import { expect, it, vi } from "vitest";
import cancelEditExtension from "../extensions/cancel-edit.ts";

type EditorFactory = NonNullable<
	ReturnType<ExtensionUIContext["getEditorComponent"]>
>;

it.each(["\x1b", "\x11"])(
	"rewinds a real Pi session through the native interrupt callback (%j)",
	async (interruptKey) => {
		const directory = mkdtempSync(join(tmpdir(), "pi-cancel-edit-"));
		const settings = SettingsManager.inMemory({
			compaction: { enabled: false },
			retry: { enabled: false },
			cacheWarming: "off",
		});
		const faux = fauxProvider();
		let signalReady!: () => void;
		const ready = new Promise<void>((resolve) => {
			signalReady = resolve;
		});
		faux.setResponses([
			async (_context, options) => {
				const aborted = new Promise<void>((resolve) => {
					if (options?.signal?.aborted) resolve();
					else
						options?.signal?.addEventListener("abort", () => resolve(), {
							once: true,
						});
				});
				signalReady();
				await aborted;
				return fauxAssistantMessage("", { stopReason: "aborted" });
			},
		]);
		const runtime = await ModelRuntime.create({
			credentials: new InMemoryCredentialStore(),
			modelsPath: null,
			modelsStorePath: join(directory, "model-cache"),
			refreshOnCreate: false,
		});
		runtime.registerNativeProvider(faux.provider);
		const loader = new DefaultResourceLoader({
			cwd: directory,
			agentDir: directory,
			settingsManager: settings,
			noExtensions: true,
			noSkills: true,
			noPromptTemplates: true,
			noThemes: true,
			extensionFactories: [cancelEditExtension],
			agentsFilesOverride: () => ({ agentsFiles: [] }),
			systemPrompt: "Test only. No network calls.",
		});
		await loader.reload();
		const manager = SessionManager.create(
			directory,
			join(directory, "sessions"),
		);
		const { session } = await createAgentSession({
			cwd: directory,
			agentDir: directory,
			modelRuntime: runtime,
			model: faux.getModel(),
			resourceLoader: loader,
			sessionManager: manager,
			settingsManager: settings,
			tools: [],
			thinkingLevel: "off",
		});
		let factory: EditorFactory | undefined;
		let editor: CustomEditor;
		const fallback = vi.fn(() => {
			void session.abort();
		});
		const errors = vi.fn();
		const navigate = vi.fn(
			async (id: string, options: { summarize?: boolean }) => {
				const result = await session.navigateTree(id, options);
				// Match interactive-mode.ts's command-context navigation wiring.
				if (!result.cancelled && result.editorText && !editor.getText().trim())
					editor.setText(result.editorText);
				return result;
			},
		);
		const ui = {
			getEditorComponent: () => factory,
			setEditorComponent: (next: EditorFactory | undefined) => {
				factory = next;
				if (!next) return;
				editor = next(
					{ requestRender() {} } as never,
					{ borderColor: (text: string) => text } as never,
					{
						matches: (data: string, action: string) =>
							action === "app.interrupt" &&
							matchesKey(data, interruptKey === "\x1b" ? "escape" : "ctrl+q"),
					} as never,
				) as CustomEditor;
				// Pi wires native handlers after invoking an editor factory.
				editor.onEscape = fallback;
			},
			getEditorText: () => editor?.getText() ?? "",
			setEditorText: (text: string) => editor.setText(text),
			notify: errors,
		} as unknown as ExtensionUIContext;
		try {
			await session.bindExtensions({
				mode: "tui",
				uiContext: ui,
				abortHandler: () => {
					void session.abort();
				},
				commandContextActions: {
					waitForIdle: () => session.waitForIdle(),
					navigateTree: navigate,
				} as never,
				onError: errors,
			});
			const run = session.prompt("Fix the typo", { source: "interactive" });
			await ready;
			const userId = manager
				.getBranch()
				.find(
					(entry) => entry.type === "message" && entry.message.role === "user",
				)!.id;
			editor!.handleInput(interruptKey);
			await run;
			await vi.waitFor(() => expect(ui.getEditorText()).toBe("Fix the typo"));
			expect(fallback).not.toHaveBeenCalled();
			expect(navigate).toHaveBeenCalledWith(userId, { summarize: false });
			expect(
				session.messages.some(
					(message) => message.role === "user" || message.role === "assistant",
				),
			).toBe(false);
			expect(manager.getEntry(userId)).toBeDefined();
			expect(readFileSync(manager.getSessionFile()!, "utf8")).toContain(userId);
			expect(faux.state.callCount).toBe(1);
			expect(errors).not.toHaveBeenCalled();
			// Editing and resubmitting creates a clean branch, with no old prompt
			// or canceled assistant response in the next model context.
			faux.setResponses([fauxAssistantMessage("Done")]);
			editor!.setText("");
			await session.prompt("Fix the other typo", { source: "interactive" });
			expect(
				session.messages.filter((message) => message.role === "user"),
			).toHaveLength(1);
			expect(session.getLastAssistantText()).toBe("Done");
		} finally {
			await session.abort();
			await session.extensionRunner.emit({
				type: "session_shutdown",
				reason: "quit",
			});
			session.dispose();
			rmSync(directory, { recursive: true, force: true });
		}
	},
);
