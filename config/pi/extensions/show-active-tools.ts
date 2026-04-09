import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

export default function (pi: ExtensionAPI) {
	pi.registerCommand("show-active-tools", {
		description: "Show all Pi tools and whether each one is active",
		handler: async (_args, ctx) => {
			const active = new Set(pi.getActiveTools());
			const all = pi
				.getAllTools()
				.map(
					(tool) =>
						`${active.has(tool.name) ? "active  " : "inactive"}  ${tool.name}`,
				)
				.sort((a, b) => a.localeCompare(b));

			ctx.ui.notify(
				all.length > 0
					? `Tools (${all.length})\n${all.join("\n")}`
					: "No tools found",
				"info",
			);
		},
	});
}
