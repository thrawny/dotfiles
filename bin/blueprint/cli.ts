import { mkdir, realpath, stat } from "node:fs/promises";
import { basename, dirname, join } from "node:path";
import { parseArgs } from "node:util";

const mode = Bun.argv[2];
const { values, positionals } = parseArgs({
	args: Bun.argv.slice(3),
	allowPositionals: true,
	options: {
		help: { type: "boolean", short: "h" },
		out: { type: "string", short: "o" },
		"link-base": { type: "string" },
		name: { type: "string" },
		port: { type: "string" },
		tailscale: { type: "boolean" },
		internal: { type: "boolean" },
	},
});

async function main() {
	if (values.help) {
		console.log(
			mode === "render"
				? `Usage: blueprint-html <source.md> [-o output.html] [--link-base URL]
Render Markdown and Blueprint typed fences to standalone HTML.
Default output: lab/<source-name>.html`
				: `Usage: blueprint-serve [directory] [--name hostname] [--tailscale] [--link-base URL]
       blueprint-serve [directory] --port 4321

Serve Markdown and HTML with a searchable index, document links, and live refresh.
Uses Portless by default, local-only. --tailscale opts into tailnet sharing.
--port runs directly on loopback without Portless. Directory defaults to lab/.
Hidden directories, dependencies, and symlinks are excluded from discovery.`,
		);
		return;
	}
	if (positionals.length > 1)
		throw new Error("Expected one directory or source file; see --help.");
	if (mode === "render") {
		if (!positionals[0])
			throw new Error(
				"Expected a source Markdown file; see blueprint-html --help.",
			);
		if (values.name || values.port || values.tailscale || values.internal)
			throw new Error("Server options belong to blueprint-serve.");
		const { render } = await import("./render.ts");
		const source = positionals[0];
		const output =
			values.out ||
			join(
				"lab",
				`${basename(source).replace(/(?:\.blueprint)?\.md$/, "")}.html`,
			);
		if ((await realpath(output).catch(() => null)) === (await realpath(source)))
			throw new Error("Output must differ from the source file.");
		const result = await render(
			await Bun.file(source).text(),
			source,
			values["link-base"],
		);
		for (const warning of result.warnings)
			console.error(`blueprint-html: warning: ${warning}`);
		await mkdir(dirname(output), { recursive: true });
		await Bun.write(output, result.html);
		console.log(output);
		return;
	}
	if (mode !== "serve") throw new Error("Expected render or serve.");
	if (values.out) throw new Error("--out belongs to blueprint-html.");
	const root = await realpath(positionals[0] || "lab");
	if (!(await stat(root)).isDirectory())
		throw new Error(`Not a directory: ${root}`);
	if (values.port && values.tailscale)
		throw new Error("--tailscale requires Portless; omit --port.");
	if (values.port || values.internal) {
		const port = Number(values.port || Bun.env.PORT);
		if (!Number.isInteger(port) || port < 1 || port > 65535)
			throw new Error("Expected a port between 1 and 65535.");
		const { serve } = await import("./server.ts");
		await serve(root, port, values["link-base"]);
		return;
	}
	if (!Bun.which("portless"))
		throw new Error(
			"Portless is not installed. Install Portless or run blueprint-serve <directory> --port 4321.",
		);
	const inferred =
		`${basename(dirname(root))}-${basename(root)}`
			.toLowerCase()
			.replace(/[^a-z0-9-]+/g, "-")
			.replace(/^-+|-+$/g, "")
			.slice(0, 63)
			.replace(/-+$/, "") || "blueprints";
	const name = values.name || inferred;
	if (!/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(name))
		throw new Error(
			"--name must be a hostname label (letters, digits, hyphens; up to 63 characters).",
		);
	const args = [
		"portless",
		name,
		...(values.tailscale ? ["--tailscale"] : []),
		process.execPath,
		"run",
		"--install=fallback",
		import.meta.path,
		"serve",
		root,
		"--internal",
	];
	if (values["link-base"]) args.push("--link-base", values["link-base"]);
	const child = Bun.spawn(args, {
		stdin: "inherit",
		stdout: "inherit",
		stderr: "inherit",
		env: {
			...Bun.env,
			PORTLESS_TAILSCALE: values.tailscale ? "1" : "0",
			PORTLESS_FUNNEL: "0",
			PORTLESS_NGROK: "0",
		},
	});
	const forward = (signal: NodeJS.Signals) => {
		child.kill(signal);
	};
	process.on("SIGINT", () => forward("SIGINT"));
	process.on("SIGTERM", () => forward("SIGTERM"));
	process.exitCode = await child.exited;
}

try {
	await main();
} catch (error) {
	console.error(
		`blueprint-${mode === "render" ? "html" : "serve"}: ${(error as Error).message}`,
	);
	process.exitCode = 1;
}
