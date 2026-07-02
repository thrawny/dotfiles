import { existsSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export const PRIMARY_LOCAL_INSTRUCTIONS_FILE = "AGENTS.local.md";
export const FALLBACK_LOCAL_INSTRUCTIONS_FILE = "CLAUDE.local.md";
export const LOCAL_INSTRUCTIONS_FILES = [
	PRIMARY_LOCAL_INSTRUCTIONS_FILE,
	FALLBACK_LOCAL_INSTRUCTIONS_FILE,
] as const;

export interface LocalInstructionFile {
	path: string;
	content: string;
}

function isFile(filePath: string): boolean {
	try {
		return statSync(filePath).isFile();
	} catch {
		return false;
	}
}

export function findGitRoot(cwd: string): string | undefined {
	let dir = path.resolve(cwd);
	while (true) {
		if (existsSync(path.join(dir, ".git"))) return dir;
		const parent = path.dirname(dir);
		if (parent === dir) return undefined;
		dir = parent;
	}
}

function directoriesFromRootToCwd(root: string, cwd: string): string[] {
	const absoluteRoot = path.resolve(root);
	const absoluteCwd = path.resolve(cwd);
	const relative = path.relative(absoluteRoot, absoluteCwd);
	if (!relative) return [absoluteRoot];

	const dirs = [absoluteRoot];
	let current = absoluteRoot;
	for (const part of relative.split(path.sep)) {
		if (!part || part === "..") continue;
		current = path.join(current, part);
		dirs.push(current);
	}
	return dirs;
}

function localInstructionPathForDir(dir: string): string | undefined {
	for (const fileName of LOCAL_INSTRUCTIONS_FILES) {
		const filePath = path.join(dir, fileName);
		if (isFile(filePath)) return filePath;
	}
	return undefined;
}

export function findLocalInstructionPaths(cwd: string): string[] {
	const absoluteCwd = path.resolve(cwd);
	const root = findGitRoot(absoluteCwd) ?? absoluteCwd;
	return directoriesFromRootToCwd(root, absoluteCwd).flatMap((dir) => {
		const filePath = localInstructionPathForDir(dir);
		return filePath ? [filePath] : [];
	});
}

export function loadLocalInstructions(cwd: string): LocalInstructionFile[] {
	return findLocalInstructionPaths(cwd).flatMap((filePath) => {
		try {
			const content = readFileSync(filePath, "utf8").trim();
			return content ? [{ path: filePath, content }] : [];
		} catch {
			return [];
		}
	});
}

export function renderLocalInstructions(
	files: LocalInstructionFile[],
	_cwd: string,
): string {
	return files.map((file) => file.content).join("\n\n");
}

export default function agentsLocalExtension(pi: ExtensionAPI) {
	let localInstructions: LocalInstructionFile[] = [];

	pi.on("session_start", async (_event, ctx) => {
		localInstructions = loadLocalInstructions(ctx.cwd);
		if (localInstructions.length > 0 && ctx.hasUI) {
			const label =
				localInstructions.length === 1
					? path.basename(localInstructions[0].path)
					: `${localInstructions.length} local instruction files`;
			ctx.ui.notify(`Loaded local instructions from ${label}`, "info");
		}
	});

	pi.on("before_agent_start", async (event, ctx) => {
		if (localInstructions.length === 0) return;

		return {
			systemPrompt: `${event.systemPrompt}\n\n${renderLocalInstructions(
				localInstructions,
				ctx.cwd,
			)}`,
		};
	});

	pi.registerCommand("local-instructions", {
		description: `Show loaded ${PRIMARY_LOCAL_INSTRUCTIONS_FILE}/${FALLBACK_LOCAL_INSTRUCTIONS_FILE} files`,
		handler: async (_args, ctx) => {
			if (localInstructions.length === 0) {
				ctx.ui.notify("No local instruction files loaded", "warning");
				return;
			}
			const root = findGitRoot(ctx.cwd) ?? path.resolve(ctx.cwd);
			const list = localInstructions
				.map(
					(file) =>
						`- ${path.relative(root, file.path) || path.basename(file.path)}`,
				)
				.join("\n");
			ctx.ui.notify(`Loaded local instructions:\n${list}`, "info");
		},
	});
}
