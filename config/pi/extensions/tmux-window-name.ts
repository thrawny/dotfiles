import { execFileSync } from "node:child_process";
import { basename } from "node:path";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

type TmuxState = {
	windowId: string | null;
	hooksInstalled: boolean;
	busy: boolean;
};

const WINDOW_IDLE = "pi";
const WINDOW_BUSY = "pi*";
const STATE_MANAGED = "@pi_tmux_managed";
const STATE_PREV_NAME = "@pi_tmux_prev_name";
const STATE_PREV_AUTO = "@pi_tmux_prev_auto";
const RUNTIME_COMMANDS = new Set(["node", "bun", "deno"]);

function runTmux(args: string[]): string | null {
	try {
		return execFileSync("tmux", args, {
			encoding: "utf8",
			timeout: 500,
			stdio: ["ignore", "pipe", "ignore"],
		}).trim();
	} catch {
		return null;
	}
}

function normalizeCommandName(command: string | null): string | null {
	if (!command) return null;
	const firstToken = command.trim().split(/\s+/)[0];
	if (!firstToken) return null;

	const stripped = firstToken.replace(/^["']|["']$/g, "");
	const normalized = basename(stripped);
	return normalized.length > 0 ? normalized : null;
}

function getWindowIdFromPane(): string | null {
	const pane = process.env.TMUX_PANE;
	if (!pane) return null;
	return runTmux(["display-message", "-p", "-t", pane, "#{window_id}"]);
}

function getPaneCurrentCommand(windowId: string): string | null {
	return normalizeCommandName(
		runTmux([
			"display-message",
			"-p",
			"-t",
			windowId,
			"#{pane_current_command}",
		]),
	);
}

function getPaneStartCommand(windowId: string): string | null {
	return normalizeCommandName(
		runTmux(["display-message", "-p", "-t", windowId, "#{pane_start_command}"]),
	);
}

function setWindowName(windowId: string, name: string): void {
	runTmux(["rename-window", "-t", windowId, name]);
}

function setWindowOption(
	windowId: string,
	option: string,
	value: string,
): void {
	runTmux(["set-option", "-w", "-t", windowId, option, value]);
}

function unsetWindowOption(windowId: string, option: string): void {
	runTmux(["set-option", "-wu", "-t", windowId, option]);
}

function getWindowOption(windowId: string, option: string): string | null {
	return runTmux(["show-options", "-wgv", "-t", windowId, option]);
}

function rememberOriginalWindowState(windowId: string): void {
	const alreadyManaged = getWindowOption(windowId, STATE_MANAGED) === "1";
	if (alreadyManaged) return;

	const originalName = runTmux(["display-message", "-p", "-t", windowId, "#W"]);
	const originalAutoRename =
		getWindowOption(windowId, "automatic-rename") || "on";
	const paneCommand = getPaneCurrentCommand(windowId);

	const isLikelyStalePiName =
		(originalName === WINDOW_IDLE || originalName === WINDOW_BUSY) &&
		paneCommand !== null &&
		RUNTIME_COMMANDS.has(paneCommand);

	setWindowOption(windowId, STATE_MANAGED, "1");
	if (
		originalName !== null &&
		originalName.length > 0 &&
		!isLikelyStalePiName
	) {
		setWindowOption(windowId, STATE_PREV_NAME, originalName);
	}
	setWindowOption(windowId, STATE_PREV_AUTO, originalAutoRename);
}

function activateManagedName(windowId: string): void {
	setWindowOption(windowId, "automatic-rename", "off");
	setWindowName(windowId, WINDOW_IDLE);
}

function restoreOriginalWindowState(windowId: string): void {
	const previousName = getWindowOption(windowId, STATE_PREV_NAME);
	const previousAutoRename = getWindowOption(windowId, STATE_PREV_AUTO) || "on";
	const currentName = runTmux(["display-message", "-p", "-t", windowId, "#W"]);

	// Restore auto-rename first.
	setWindowOption(windowId, "automatic-rename", previousAutoRename);

	if (previousName && previousName.length > 0) {
		setWindowName(windowId, previousName);
	} else if (currentName === WINDOW_IDLE || currentName === WINDOW_BUSY) {
		// Fallback for stale/broken state.
		const currentCmd = getPaneCurrentCommand(windowId);
		if (currentCmd && !RUNTIME_COMMANDS.has(currentCmd)) {
			setWindowName(windowId, currentCmd);
		} else {
			const startCmd = getPaneStartCommand(windowId);
			if (startCmd && startCmd.length > 0) {
				setWindowName(windowId, startCmd);
			} else if (currentCmd && currentCmd.length > 0) {
				setWindowName(windowId, currentCmd);
			}
		}
	}

	unsetWindowOption(windowId, STATE_MANAGED);
	unsetWindowOption(windowId, STATE_PREV_NAME);
	unsetWindowOption(windowId, STATE_PREV_AUTO);
}

function resolveWindowId(state: TmuxState): string | null {
	if (state.windowId) return state.windowId;
	const fromPane = getWindowIdFromPane();
	if (fromPane) state.windowId = fromPane;
	return fromPane;
}

function setupTmuxRename(state: TmuxState): void {
	const windowId = resolveWindowId(state);
	if (!windowId) return;

	rememberOriginalWindowState(windowId);
	activateManagedName(windowId);
}

function updateBusyState(state: TmuxState, busy: boolean): void {
	const windowId = resolveWindowId(state);
	if (!windowId) return;

	const managed = getWindowOption(windowId, STATE_MANAGED) === "1";
	if (!managed) return;
	setWindowName(windowId, busy ? WINDOW_BUSY : WINDOW_IDLE);
}

function cleanupTmuxRename(state: TmuxState): void {
	const windowId = resolveWindowId(state);
	if (!windowId) return;

	const managed = getWindowOption(windowId, STATE_MANAGED) === "1";
	const currentName = runTmux(["display-message", "-p", "-t", windowId, "#W"]);

	if (managed || currentName === WINDOW_IDLE || currentName === WINDOW_BUSY) {
		restoreOriginalWindowState(windowId);
	}

	state.windowId = null;
}

function installProcessExitHooks(state: TmuxState): void {
	if (state.hooksInstalled) return;
	state.hooksInstalled = true;

	const cleanup = () => cleanupTmuxRename(state);

	process.on("beforeExit", cleanup);
	process.on("exit", cleanup);
	process.on("SIGINT", cleanup);
	process.on("SIGTERM", cleanup);
	process.on("SIGHUP", cleanup);
	process.on("uncaughtException", cleanup);
	process.on("unhandledRejection", cleanup);
}

export default function (pi: ExtensionAPI) {
	const state: TmuxState = {
		windowId: null,
		hooksInstalled: false,
		busy: false,
	};

	pi.on("session_start", async () => {
		state.busy = false;
		installProcessExitHooks(state);
		setupTmuxRename(state);
	});

	pi.on("agent_start", async () => {
		state.busy = true;
		updateBusyState(state, true);
	});

	pi.on("agent_end", async () => {
		state.busy = false;
		updateBusyState(state, false);
	});

	pi.on("session_shutdown", async () => {
		cleanupTmuxRename(state);
	});
}
