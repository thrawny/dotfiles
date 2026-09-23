function counters(text, interfaces) {
    const result = {};
    for (const line of text.split("\n")) {
        const colon = line.indexOf(":");
        if (colon < 0) continue;
        const name = line.slice(0, colon).trim();
        if (!interfaces.includes(name)) continue;
        const fields = line.slice(colon + 1).trim().split(/\s+/).map(Number);
        if (fields.length >= 9 && Number.isFinite(fields[0]) && Number.isFinite(fields[8]))
            result[name] = { rx: fields[0], tx: fields[8] };
    }
    return result;
}
function rates(previous, next, seconds) {
    let rx = 0, tx = 0;
    if (seconds <= 0) return { rx, tx };
    for (const name of Object.keys(next)) {
        if (!previous[name]) continue;
        rx += Math.max(0, next[name].rx - previous[name].rx) / seconds;
        tx += Math.max(0, next[name].tx - previous[name].tx) / seconds;
    }
    return { rx, tx };
}
function bytes(value) {
    if (value >= 1048576) return (value / 1048576).toFixed(1) + " MiB/s";
    if (value >= 1024) return (value / 1024).toFixed(1) + " KiB/s";
    return Math.round(value) + " B/s";
}
if (typeof module !== "undefined") module.exports = { counters, rates, bytes };
