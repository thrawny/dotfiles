// Lower scores rank first. Subsequence matches allow short app abbreviations.
function score(text, query) {
    text = String(text || "").toLowerCase();
    query = String(query || "").trim().toLowerCase();
    if (!query) return 0;
    if (text === query) return 0;
    if (text.startsWith(query)) return 1;
    const direct = text.indexOf(query);
    if (direct >= 0) return 10 + direct;
    let cursor = 0;
    let gaps = 0;
    for (let i = 0; i < query.length; i++) {
        const next = text.indexOf(query[i], cursor);
        if (next < 0) return Infinity;
        gaps += next - cursor;
        cursor = next + 1;
    }
    return 100 + gaps;
}

function apps(entries, query) {
    return entries.filter(entry => !entry.noDisplay).map(entry => ({
        kind: "app", entry: entry, name: entry.name,
        detail: entry.genericName || entry.comment || "",
        icon: entry.icon || "",
        score: Math.min(score(entry.name, query),
            50 + score([entry.genericName, entry.comment, (entry.keywords || []).join(" ")].join(" "), query))
    })).filter(item => Number.isFinite(item.score))
        .sort((a, b) => a.score - b.score || a.name.localeCompare(b.name)).slice(0, 80);
}

// Quickshell 0.3.1's DesktopEntry.execute() ignores Terminal=true.
function appCommand(entry) {
    const command = Array.from(entry.command || []);
    if (!command.length) return [];
    return entry.runInTerminal ? ["ghostty", "-e"].concat(command) : command;
}

function clipboardRows(output) {
    return output.split("\n").filter(line => /^\d+\t/.test(line)).map(line => {
        const tab = line.indexOf("\t");
        return { kind: "clipboard", id: line.slice(0, tab), name: line.slice(tab + 1), detail: "Copy to clipboard", icon: "" };
    });
}

function clipboard(entries, query) {
    const needle = query.trim().toLowerCase();
    // Keep recency order, and avoid fuzzy matching unrelated clipboard content.
    return entries.filter(entry => entry.name.toLowerCase().includes(needle)).slice(0, 80);
}

function modes(query) {
    return [
        { kind: "mode", mode: "apps", name: "Applications", detail: "Search installed applications", icon: "view-app-grid-symbolic" },
        { kind: "mode", mode: "clipboard", name: "Clipboard", detail: "Search clipboard history", icon: "edit-paste-symbolic" }
    ].filter(item => Number.isFinite(score(item.name, query)));
}
