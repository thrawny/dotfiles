import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
	pi.registerCommand("fork-window", {
		description: "Fork this conversation into a Herdr tab or Hyprland window",
		handler: async (args, ctx) => {
			if (args.trim()) {
				ctx.ui.notify("Usage: /fork-window", "error");
				return;
			}
			if (!ctx.isIdle()) {
				ctx.ui.notify(
					"Wait for the current turn to finish before forking.",
					"error",
				);
				return;
			}
			const session = ctx.sessionManager.getSessionFile();
			if (!session) {
				ctx.ui.notify("Save a conversation before forking it.", "error");
				return;
			}
			try {
				const result = await pi.exec("fork-window", [
					"pi",
					session,
					"--cwd",
					ctx.cwd,
				]);
				ctx.ui.notify(
					(result.code === 0
						? result.stdout
						: result.stderr || result.stdout
					).trim(),
					result.code === 0 ? "info" : "error",
				);
			} catch (error) {
				ctx.ui.notify(String(error), "error");
			}
		},
	});
}
