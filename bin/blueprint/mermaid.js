(() => {
	const figures = [...document.querySelectorAll(".mermaid-figure")];
	if (!figures.length) return;
	const rootStyle = () => getComputedStyle(document.documentElement);
	const color = (name) => rootStyle().getPropertyValue(`--${name}`).trim();
	const dark = () => rootStyle().colorScheme === "dark";
	let count = 0;
	const configure = () =>
		mermaid.initialize({
			startOnLoad: false,
			securityLevel: "strict",
			suppressErrorRendering: true,
			theme: "base",
			themeVariables: {
				darkMode: dark(),
				background: color("bg"),
				fontFamily: "system-ui, sans-serif",
				primaryColor: color("add-bg"),
				primaryTextColor: color("fg"),
				primaryBorderColor: color("add"),
				secondaryColor: color("mod-bg"),
				tertiaryColor: color("code-bg"),
				lineColor: color("muted"),
				textColor: color("fg"),
				noteBkgColor: color("code-bg"),
				noteTextColor: color("fg"),
				edgeLabelBackground: color("bg"),
			},
		});
	async function draw() {
		configure();
		for (const fig of figures) {
			const source = fig.dataset.source;
			const holder = document.createElement("div");
			holder.className = "mermaid-svg";
			try {
				holder.innerHTML = (await mermaid.render(`bpm${count++}`, source)).svg;
			} catch (error) {
				const warn = document.createElement("p");
				warn.className = "figwarn";
				warn.textContent = `mermaid failed, diagram kept as source text: ${String(error?.message || error).split("\n")[0]}`;
				const block = document.createElement("div");
				block.className = "block";
				const pre = document.createElement("pre");
				pre.className = "diffish";
				pre.textContent = source;
				block.append(pre);
				holder.append(warn, block);
			}
			fig.querySelector(".mermaid-svg").replaceWith(holder);
			window.bpZoom?.(fig);
		}
	}
	let pending = Promise.resolve();
	const redraw = () => {
		pending = pending.then(draw);
	};
	addEventListener("DOMContentLoaded", redraw);
	new MutationObserver(redraw).observe(document.documentElement, {
		attributes: true,
		attributeFilter: ["data-theme"],
	});
	matchMedia("(prefers-color-scheme: dark)").addEventListener("change", redraw);
})();
