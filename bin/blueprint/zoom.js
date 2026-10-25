addEventListener("DOMContentLoaded", () => {
	const dlg = Object.assign(document.createElement("dialog"), {
		className: "zoom",
	});
	document.body.append(dlg);
	dlg.addEventListener("click", () => dlg.close());
	for (const fig of document.querySelectorAll(".d2-figure")) {
		const svg = fig.querySelector("svg");
		if (!svg) continue;
		const open = () => {
			dlg.replaceChildren(svg.cloneNode(true));
			dlg.showModal();
		};
		const b = document.createElement("button");
		b.className = "figbtn";
		b.textContent = "\u26f6";
		b.title = "Maximize";
		b.onclick = open;
		fig.append(b);
		fig.addEventListener("dblclick", open);
	}
});
