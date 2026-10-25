(() => {
	const script = document.querySelector("script[data-blueprint-revision]");
	const revision = script.dataset.blueprintRevision;
	const key = `blueprint-scroll:${location.pathname}`;
	try {
		const saved = sessionStorage.getItem(key);
		if (saved !== null) {
			sessionStorage.removeItem(key);
			addEventListener(
				"load",
				() => requestAnimationFrame(() => scrollTo(0, Number(saved))),
				{ once: true },
			);
		}
	} catch {}
	let socket;
	let retry;
	let stopped = false;
	function connect() {
		const url = new URL("/_blueprint/events", location.href);
		url.protocol = location.protocol === "https:" ? "wss:" : "ws:";
		socket = new WebSocket(url);
		socket.onmessage = ({ data }) => {
			if (data === revision) return;
			stopped = true;
			socket.close();
			try {
				sessionStorage.setItem(key, String(scrollY));
			} catch {}
			location.reload();
		};
		socket.onclose = () => {
			if (!stopped) retry = setTimeout(connect, 1000);
		};
	}
	addEventListener("pagehide", () => {
		stopped = true;
		clearTimeout(retry);
		socket?.close();
	});
	addEventListener("pageshow", (event) => {
		if (event.persisted) {
			stopped = false;
			connect();
		}
	});
	connect();
})();
