import { execFileSync } from "node:child_process";
import path from "node:path";
import { complete, type Message } from "@mariozechner/pi-ai";
import {
	BorderedLoader,
	type ExtensionAPI,
	type ExtensionContext,
	type SessionEntry,
} from "@mariozechner/pi-coding-agent";

interface ChangedFile {
	path: string;
	status: string;
	sessionTouched: boolean;
}

interface CommitPlan {
	includePaths: string[];
	commitMessage: string;
}

function git(cwd: string, args: string[]): string {
	return execFileSync("git", args, {
		cwd,
		encoding: "utf8",
		stdio: ["ignore", "pipe", "pipe"],
	}).trim();
}

function tryGit(cwd: string, args: string[]): string | null {
	try {
		return git(cwd, args);
	} catch {
		return null;
	}
}

function getRepoRoot(cwd: string): string | null {
	return tryGit(cwd, ["rev-parse", "--show-toplevel"]);
}

function parseStatus(repoRoot: string): ChangedFile[] {
	const out = git(repoRoot, ["status", "--porcelain=v1"]);
	if (!out) return [];

	return out
		.split("\n")
		.filter(Boolean)
		.map((line) => {
			const status = line.slice(0, 2);
			const rawPath = line.slice(3).trim();
			const renameParts = rawPath.split(" -> ");
			const filePath = renameParts[renameParts.length - 1] ?? rawPath;
			return {
				path: filePath,
				status,
				sessionTouched: false,
			};
		});
}

function normalizeRepoPath(repoRoot: string, filePath: string): string {
	const resolved = path.isAbsolute(filePath)
		? filePath
		: path.resolve(repoRoot, filePath);
	const relative = path.relative(repoRoot, resolved);
	return relative.split(path.sep).join("/");
}

function getSessionTouchedFiles(
	repoRoot: string,
	branch: SessionEntry[],
): Set<string> {
	const files = new Set<string>();

	for (const entry of branch) {
		if (entry.type !== "message") continue;
		const message = entry.message;
		if (message.role !== "assistant") continue;
		for (const block of message.content) {
			if (block.type !== "toolCall") continue;
			if (block.name !== "edit" && block.name !== "write") continue;
			const maybePath = block.arguments?.path;
			if (typeof maybePath === "string" && maybePath.trim()) {
				files.add(normalizeRepoPath(repoRoot, maybePath.trim()));
			}
		}
	}

	return files;
}

function markSessionTouched(
	changedFiles: ChangedFile[],
	sessionTouched: Set<string>,
): ChangedFile[] {
	return changedFiles.map((file) => ({
		...file,
		sessionTouched: sessionTouched.has(file.path),
	}));
}

function defaultPaths(changedFiles: ChangedFile[]): string[] {
	return changedFiles
		.filter((file) => file.sessionTouched)
		.map((file) => file.path);
}

function heuristicPaths(
	changedFiles: ChangedFile[],
	instructions: string,
): string[] {
	const text = instructions.trim().toLowerCase();
	if (!text) return [];

	const exact = changedFiles
		.filter((file) => text.includes(file.path.toLowerCase()))
		.map((file) => file.path);
	if (exact.length > 0) return exact;

	const basenameMatches = changedFiles
		.filter((file) => text.includes(path.basename(file.path).toLowerCase()))
		.map((file) => file.path);
	if (basenameMatches.length > 0) return basenameMatches;

	return [];
}

function heuristicMessage(paths: string[], instructions: string): string {
	const trimmed = instructions.trim();
	if (trimmed && trimmed.toLowerCase() !== "all") {
		const cleaned = trimmed
			.replace(/^only\s+/i, "")
			.replace(/^file\s+/i, "")
			.trim();
		if (cleaned) {
			const sentence = cleaned.charAt(0).toUpperCase() + cleaned.slice(1);
			return sentence.length > 72 ? sentence.slice(0, 72).trimEnd() : sentence;
		}
	}

	if (paths.length === 1) {
		const base = path.basename(paths[0] ?? "change");
		const stem = base.replace(/\.[^.]+$/, "");
		return `Update ${stem}`;
	}
	if (paths.length > 1) return `Update ${paths.length} files`;
	return "Update changes";
}

function sanitizeJson(text: string): string {
	const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/i);
	return (fenced?.[1] ?? text).trim();
}

async function withLoader<T>(
	ctx: ExtensionContext,
	label: string,
	task: (signal: AbortSignal) => Promise<T>,
): Promise<T | null> {
	if (!ctx.hasUI) {
		return task(new AbortController().signal);
	}

	return ctx.ui.custom<T | null>((tui, theme, _kb, done) => {
		const loader = new BorderedLoader(tui, theme, label);
		loader.onAbort = () => done(null);

		task(loader.signal)
			.then(done)
			.catch((error) => {
				console.error(label, error);
				done(null);
			});

		return loader;
	});
}

async function suggestPlan(
	ctx: ExtensionContext,
	repoRoot: string,
	changedFiles: ChangedFile[],
	preferredPaths: string[],
	instructions: string,
): Promise<CommitPlan> {
	const fallback: CommitPlan = {
		includePaths: preferredPaths,
		commitMessage: heuristicMessage(preferredPaths, instructions),
	};

	if (!ctx.model) return fallback;

	const auth = await (
		ctx.modelRegistry as unknown as {
			getApiKeyAndHeaders: (
				model: NonNullable<ExtensionContext["model"]>,
			) => Promise<{
				ok: boolean;
				apiKey?: string;
				headers?: Record<string, string>;
				error?: string;
			}>;
		}
	).getApiKeyAndHeaders(ctx.model);
	if (!auth.ok || !auth.apiKey) return fallback;

	const diffStat = tryGit(repoRoot, [
		"diff",
		"--stat",
		"--",
		...preferredPaths,
	]);
	const diffText = tryGit(repoRoot, [
		"diff",
		"--unified=0",
		"--no-color",
		"--",
		...preferredPaths,
	]);
	const truncatedDiff = (diffText ?? "").slice(0, 12000);

	const systemPrompt = `You generate git commit plans. Return only valid JSON with shape {"includePaths": string[], "commitMessage": string}.
Rules:
- includePaths must be a subset of the provided changed files.
- Prefer session-touched files unless the instructions clearly ask for a broader selection.
- Keep commitMessage concise, imperative, and specific.
- Do not include markdown fences or commentary.`;

	const userMessage: Message = {
		role: "user",
		content: [
			{
				type: "text",
				text: JSON.stringify(
					{
						instructions,
						changedFiles,
						preferredPaths,
						diffStat,
						diff: truncatedDiff,
					},
					null,
					2,
				),
			},
		],
		timestamp: Date.now(),
	};

	const response = await withLoader(ctx, "Planning commit...", async (signal) =>
		complete(
			ctx.model!,
			{ systemPrompt, messages: [userMessage] },
			{ apiKey: auth.apiKey!, headers: auth.headers, signal },
		),
	);
	if (!response || response.stopReason === "aborted") return fallback;

	const text = response.content
		.filter(
			(block): block is { type: "text"; text: string } => block.type === "text",
		)
		.map((block) => block.text)
		.join("\n");

	try {
		const parsed = JSON.parse(sanitizeJson(text)) as Partial<CommitPlan>;
		const allowed = new Set(changedFiles.map((file) => file.path));
		const includePaths = (parsed.includePaths ?? []).filter(
			(file): file is string => typeof file === "string" && allowed.has(file),
		);
		const commitMessage =
			typeof parsed.commitMessage === "string" && parsed.commitMessage.trim()
				? parsed.commitMessage.trim()
				: fallback.commitMessage;
		if (includePaths.length === 0) return fallback;
		return { includePaths, commitMessage };
	} catch {
		return fallback;
	}
}

function stagePaths(repoRoot: string, paths: string[]) {
	if (paths.length === 0) return;
	execFileSync("git", ["add", "-A", "--", ...paths], {
		cwd: repoRoot,
		stdio: ["ignore", "pipe", "pipe"],
	});
}

function stageAll(repoRoot: string) {
	execFileSync("git", ["add", "-A"], {
		cwd: repoRoot,
		stdio: ["ignore", "pipe", "pipe"],
	});
}

function hasStagedChanges(repoRoot: string): boolean {
	try {
		execFileSync("git", ["diff", "--cached", "--quiet", "--exit-code"], {
			cwd: repoRoot,
			stdio: ["ignore", "ignore", "ignore"],
		});
		return false;
	} catch {
		return true;
	}
}

function commit(repoRoot: string, message: string) {
	execFileSync("git", ["commit", "-m", message], {
		cwd: repoRoot,
		stdio: ["ignore", "pipe", "pipe"],
	});
}

export default function (pi: ExtensionAPI) {
	pi.registerCommand("gc", {
		description: "Create a git commit quietly",
		handler: async (args, ctx) => {
			const repoRoot = getRepoRoot(ctx.cwd);
			if (!repoRoot) {
				ctx.ui.notify("Not in a git repository", "error");
				return;
			}

			const changedFiles = markSessionTouched(
				parseStatus(repoRoot),
				getSessionTouchedFiles(repoRoot, ctx.sessionManager.getBranch()),
			);
			if (changedFiles.length === 0) {
				ctx.ui.notify("No changes to commit", "info");
				return;
			}

			const trimmedArgs = args.trim();
			const isAll = trimmedArgs === "all";

			let selectedPaths: string[];
			let suggestedMessage: string;

			if (isAll) {
				selectedPaths = changedFiles.map((file) => file.path);
				suggestedMessage = heuristicMessage(selectedPaths, trimmedArgs);
			} else {
				const preferred =
					trimmedArgs.length > 0
						? heuristicPaths(changedFiles, trimmedArgs)
						: defaultPaths(changedFiles);
				const fallbackPreferred =
					preferred.length > 0 ? preferred : defaultPaths(changedFiles);
				if (fallbackPreferred.length === 0) {
					ctx.ui.notify(
						"No changed files from this session to commit",
						"warning",
					);
					return;
				}

				const plan = await suggestPlan(
					ctx,
					repoRoot,
					changedFiles,
					fallbackPreferred,
					trimmedArgs,
				);
				selectedPaths = plan.includePaths;
				suggestedMessage = plan.commitMessage;
			}

			if (selectedPaths.length === 0) {
				ctx.ui.notify("Nothing selected to commit", "warning");
				return;
			}

			const commitMessage = suggestedMessage.trim();
			if (!commitMessage) {
				ctx.ui.notify("Could not determine a commit message", "error");
				return;
			}

			try {
				if (isAll) stageAll(repoRoot);
				else stagePaths(repoRoot, selectedPaths);
				if (!hasStagedChanges(repoRoot)) {
					ctx.ui.notify("No staged changes to commit", "warning");
					return;
				}
				commit(repoRoot, commitMessage);
				ctx.ui.notify(`Committed: ${commitMessage}`, "info");
			} catch (error) {
				const message = error instanceof Error ? error.message : String(error);
				ctx.ui.notify(`Commit failed: ${message}`, "error");
			}
		},
	});
}
