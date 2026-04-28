import { execFileSync } from "node:child_process";
import path from "node:path";
import { Type } from "@mariozechner/pi-ai";
import type { ExtensionAPI, SessionEntry } from "@mariozechner/pi-coding-agent";

interface ChangedFile {
	path: string;
	status: string;
	sessionTouched: boolean;
}

interface PendingCommit {
	root: string;
	changed: ChangedFile[];
	preferred: string[];
	previousTools: string[];
}

let pendingCommit: PendingCommit | undefined;

function git(cwd: string, args: string[]): string {
	return execFileSync("git", args, {
		cwd,
		encoding: "utf8",
		stdio: ["ignore", "pipe", "pipe"],
	}).trim();
}

function repoRoot(cwd: string): string {
	return git(cwd, ["rev-parse", "--show-toplevel"]);
}

function parseStatus(root: string): ChangedFile[] {
	const out = git(root, ["status", "--porcelain=v1"]);
	if (!out) return [];

	return out.split("\n").filter(Boolean).map((line) => {
		const status = line.slice(0, 2);
		const rawPath = line.slice(2).trim();
		const renameParts = rawPath.split(" -> ");
		return {
			path: renameParts[renameParts.length - 1] ?? rawPath,
			status,
			sessionTouched: false,
		};
	});
}

function normalizeRepoPath(root: string, filePath: string): string {
	const resolved = path.isAbsolute(filePath) ? filePath : path.resolve(root, filePath);
	return path.relative(root, resolved).split(path.sep).join("/");
}

function sessionTouchedFiles(root: string, branch: SessionEntry[]): Set<string> {
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
				files.add(normalizeRepoPath(root, maybePath.trim()));
			}
		}
	}
	return files;
}

function markTouched(changed: ChangedFile[], touched: Set<string>): ChangedFile[] {
	return changed.map((file) => ({ ...file, sessionTouched: touched.has(file.path) }));
}

function requestedPaths(changed: ChangedFile[], args: string): string[] {
	const text = args.trim().toLowerCase();
	const tokens = text.split(/\s+/).filter(Boolean);
	if (!text) return changed.filter((file) => file.sessionTouched).map((file) => file.path);
	if (tokens.includes("all") || tokens.includes("--all") || tokens.includes("-a")) return changed.map((file) => file.path);

	const exact = changed.filter((file) => text.includes(file.path.toLowerCase())).map((file) => file.path);
	if (exact.length > 0) return exact;

	const basename = changed
		.filter((file) => text.includes(path.basename(file.path).toLowerCase()))
		.map((file) => file.path);
	if (basename.length > 0) return basename;

	return changed.filter((file) => file.sessionTouched).map((file) => file.path);
}

function restoreTools(pi: ExtensionAPI): void {
	const previousTools = pendingCommit?.previousTools ?? pi.getActiveTools().filter((tool) => tool !== "gc2_commit");
	pi.setActiveTools(previousTools.filter((tool) => tool !== "gc2_commit"));
	pendingCommit = undefined;
}

export default function (pi: ExtensionAPI) {
	pi.registerTool({
		name: "gc2_commit",
		label: "GC2 Commit",
		description: "Create the pending gc2 git commit with selected files and a commit message.",
		parameters: Type.Object({
			includePaths: Type.Array(Type.String({ description: "Repository-relative paths to commit" })),
			commitMessage: Type.String({ description: "Concise imperative git commit message" }),
		}),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			if (!pendingCommit) throw new Error("No pending gc2 commit");

			const allowed = new Set(pendingCommit.changed.map((file) => file.path));
			const includePaths = params.includePaths.filter((file) => allowed.has(file));
			const commitMessage = params.commitMessage.trim();
			if (includePaths.length === 0) throw new Error("No valid paths");
			if (!commitMessage) throw new Error("No commit message");

			git(pendingCommit.root, ["add", "--", ...includePaths]);
			git(pendingCommit.root, ["commit", "-m", commitMessage]);
			const hash = git(pendingCommit.root, ["rev-parse", "--short", "HEAD"]);
			restoreTools(pi);

			return {
				content: [{ type: "text", text: `Committed ${hash}: ${commitMessage}` }],
				details: { hash, includePaths, commitMessage },
				terminate: true,
			};
		},
	});

	pi.registerCommand("gc2", {
		description: "Fast focused git commit via a temporary gc2 commit tool",
		handler: async (args, ctx) => {
			const root = repoRoot(ctx.cwd);
			let changed = parseStatus(root);
			if (changed.length === 0) {
				ctx.ui.notify("Nothing to commit", "info");
				return;
			}

			changed = markTouched(changed, sessionTouchedFiles(root, ctx.sessionManager.getBranch()));
			let preferred = requestedPaths(changed, args);
			if (preferred.length === 0) preferred = changed.map((file) => file.path);

			const diffStat = git(root, ["diff", "--stat", "--", ...preferred]);
			const diff = git(root, ["diff", "--unified=0", "--no-color", "--", ...preferred]).slice(0, 16000);

			pendingCommit = {
				root,
				changed,
				preferred,
				previousTools: pi.getActiveTools().filter((tool) => tool !== "gc2_commit"),
			};

			ctx.ui.notify("Planning commit...", "info");
			pi.setActiveTools(["gc2_commit"]);
			pi.sendMessage(
				{
					customType: "gc2-context",
					content: `Create a git commit by calling gc2_commit exactly once.

Do not call any other tools. Do not answer in text. Use prior session context to understand intent, but ground the commit in the changed files and diff below.

User commit instruction:
${args || "(none)"}

Rules:
- includePaths must be a subset of changed file paths.
- If the user commit instruction is "all", "--all", or "-a", include every changed file.
- If the user commit instruction mentions paths, filenames, scopes, or intent, choose matching files.
- Otherwise prefer preferred/session-touched paths.
- Use the user commit instruction as guidance for the commit message when relevant.
- commitMessage must be concise, imperative, specific, no trailing period.

Changed files:
${JSON.stringify(changed, null, 2)}

Preferred files:
${JSON.stringify(preferred, null, 2)}

Diff stat:
${diffStat}

Diff:
${diff}`,
					display: false,
				},
				{ triggerTurn: true },
			);
		},
	});

	pi.on("agent_end", async () => {
		restoreTools(pi);
	});

	pi.on("tool_result", async (event) => {
		if (event.toolName === "gc2_commit") restoreTools(pi);
	});
}
