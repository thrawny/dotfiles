const root = document.documentElement;
let saved = null;
try {
	saved = localStorage.getItem("bp-theme");
} catch {}
if (saved === "light" || saved === "dark") root.dataset.theme = saved;
addEventListener("DOMContentLoaded", () => {
	document.getElementById("themebtn").onclick = () => {
		const dark = root.dataset.theme
			? root.dataset.theme === "dark"
			: matchMedia("(prefers-color-scheme: dark)").matches;
		const next = dark ? "light" : "dark";
		root.dataset.theme = next;
		try {
			localStorage.setItem("bp-theme", next);
		} catch {}
	};
});
