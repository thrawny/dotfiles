// Pieces the list page and the review page share.

export function lines(n: number) {
	return n >= 1000 ? `${(n / 1000).toFixed(n >= 10000 ? 0 : 1)}k` : String(n);
}

export function ago(iso: string, now: number) {
	const mins = Math.round((now - Date.parse(iso)) / 60000);
	if (mins < 60) return `${mins}m`;
	const hours = Math.round(mins / 60);
	if (hours < 48) return `${hours}h`;
	return `${Math.round(hours / 24)}d`;
}

export const CI_TEXT = {
	success: "CI green",
	failure: "CI failing",
	pending: "CI running",
	none: "No CI",
};

export const REVIEW_MARK = {
	approved: ["✓", "Approved"],
	changes: ["✗", "Changes requested"],
	commented: ["•", "Commented"],
	none: ["", ""],
};

export function jiraHref(base: string, key: string) {
	return `${base.replace(/\/$/, "")}/${key}`;
}

// The page's scheme: a saved choice, else the system's.
export function isDark() {
	const root = document.documentElement;
	return root.dataset.theme
		? root.dataset.theme === "dark"
		: matchMedia("(prefers-color-scheme: dark)").matches;
}

export function ThemeButton() {
	const toggle = () => {
		const next = isDark() ? "light" : "dark";
		document.documentElement.dataset.theme = next;
		try {
			localStorage.setItem("bp-theme", next);
		} catch {}
	};
	return (
		<button type="button" onClick={toggle} title="Toggle light/dark">
			◐
		</button>
	);
}
