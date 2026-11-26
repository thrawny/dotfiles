// Pieces the list page and the review page share.

import { createContext } from "preact";
import type { BotReview } from "./model.ts";

// Whether a page is the one on screen. Pages that stay open in the
// background keep their state but leave the keys and the title alone.
export const Active = createContext(true);

// The list's address, with its filters, the last time it showed.
export const listHref = { current: "/" };

// Moves between the list and review pages without a page load, so pages
// opened before keep their state.
export function navigate(href: string, state: unknown = null) {
	history.pushState(state, "", href);
	dispatchEvent(new Event("mc-navigate"));
}

// Back to the list with its filters: a step back in history when the list
// opened this page.
export function goBack() {
	if ((history.state as { fromList?: boolean } | null)?.fromList)
		history.back();
	else navigate(listHref.current);
}

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

// The badge colour for the review bot's newest review.
export function botClass(review: BotReview | null) {
	if (!review) return "none";
	if (review.stale) return "stale";
	return review.verdict === "lgtm" ? "lgtm" : "findings";
}

export function botTitle(bot: string, review: BotReview | null) {
	if (!review) return `No ${bot} review`;
	return `${bot} review #${review.n}: ${review.verdict || "no verdict"}${review.stale ? ", new commits since" : ""}`;
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
